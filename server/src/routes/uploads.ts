import type { FastifyPluginAsync } from 'fastify';
import { createWriteStream } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { randomUUID } from 'node:crypto';
import OSS from 'ali-oss';
import { z } from 'zod';
import { config } from '../config.js';

const extensionByMime = new Map([
  ['video/mp4', '.mp4'],
  ['video/quicktime', '.mov'],
  ['image/jpeg', '.jpg'],
  ['image/png', '.png'],
  ['image/webp', '.webp']
]);

const multipartSessionSchema = z.object({
  key: z.string().min(1).max(1024),
  uploadId: z.string().min(1).max(1024)
});
const uploadedPartSchema = z.object({
  number: z.number().int().min(1).max(10000),
  etag: z.string().min(1).max(256).regex(/^[^<>&\r\n]+$/),
  size: z.number().int().positive()
});

function uploadError(statusCode: number, code: string, message: string) {
  return Object.assign(new Error(message), { statusCode, code });
}

function providerCode(error: unknown) {
  return typeof error === 'object' && error !== null && 'code' in error ? error.code : undefined;
}

function mapOssError(error: unknown): Error {
  if (error instanceof Error && 'statusCode' in error && 'code' in error &&
      typeof error.code === 'string' && /^(UPLOAD_|OSS_)/.test(error.code)) return error;
  const status = typeof error === 'object' && error !== null && 'status' in error ? error.status : undefined;
  if (status === 403 || providerCode(error) === 'AccessDenied') {
    return uploadError(403, 'OSS_ACCESS_DENIED', '视频存储访问被拒绝，请稍后重试');
  }
  if (['InvalidPart', 'InvalidPartOrder', 'EntityTooSmall', 'InvalidArgument'].includes(String(providerCode(error)))) {
    return uploadError(400, 'UPLOAD_INVALID_PARTS', '视频分片无效，请重新上传');
  }
  // A timeout or generic 404 must not make the client discard its checkpoint.
  return uploadError(503, 'OSS_UNAVAILABLE', '视频上传暂时不可用，请稍后重试');
}

function ossClient() {
  if (config.UPLOAD_MODE !== 'oss' || !config.OSS_BUCKET || !config.OSS_ACCESS_KEY_ID || !config.OSS_ACCESS_KEY_SECRET) {
    throw uploadError(503, 'OSS_NOT_CONFIGURED', 'OSS 分片上传尚未配置');
  }
  return new OSS({ region: config.OSS_REGION, bucket: config.OSS_BUCKET, accessKeyId: config.OSS_ACCESS_KEY_ID, accessKeySecret: config.OSS_ACCESS_KEY_SECRET, secure: true });
}

function publicOssUrl(key: string) {
  const base = config.OSS_PUBLIC_BASE_URL || `https://${config.OSS_BUCKET}.${config.OSS_REGION}.aliyuncs.com`;
  return `${base.replace(/\/$/, '')}/${key.split('/').map(encodeURIComponent).join('/')}`;
}

async function completedObject(client: OSS, key: string) {
  try {
    const object = await client.head(key);
    const size = Number((object.res.headers as Record<string, unknown>)['content-length']);
    if (object.status !== 200 || !Number.isSafeInteger(size) || size <= 0) {
      throw uploadError(503, 'OSS_UNAVAILABLE', '暂时无法确认视频上传状态');
    }
    return { state: 'completed' as const, url: publicOssUrl(key), size };
  } catch (error) {
    if (providerCode(error) === 'NoSuchKey') {
      throw uploadError(404, 'UPLOAD_NOT_FOUND', '上传任务已失效，请重新上传');
    }
    throw mapOssError(error);
  }
}

async function uploadedParts(client: OSS, key: string, uploadId: string) {
  const parts: z.infer<typeof uploadedPartSchema>[] = [];
  let marker = 0;
  while (true) {
    const page = await client.listParts(key, uploadId, {
      'max-parts': 1000,
      'part-number-marker': marker,
      'encoding-type': 'url'
    });
    // ali-oss returns the raw XML values, despite its narrower type declarations:
    // string booleans/numbers, capitalized Size, and a single object for one part.
    const rawParts: unknown[] = Array.isArray(page.parts) ? page.parts : page.parts ? [page.parts] : [];
    let lastNumber = marker;
    for (const rawPart of rawParts) {
      const value = rawPart as Record<string, unknown> | null;
      const parsed = uploadedPartSchema.safeParse({
        number: Number(value?.PartNumber ?? value?.number),
        etag: value?.ETag ?? value?.etag,
        size: Number(value?.Size ?? value?.size)
      });
      if (!parsed.success || parsed.data.number <= lastNumber || parts.length >= 10000) {
        throw uploadError(503, 'OSS_UNAVAILABLE', '暂时无法确认视频分片状态');
      }
      parts.push(parsed.data);
      lastNumber = parsed.data.number;
    }
    const truncated: unknown = page.isTruncated;
    if (truncated === false || truncated === 'false') return parts;
    const nextMarker = Number(page.nextPartNumberMarker);
    if ((truncated !== true && truncated !== 'true') || !Number.isInteger(nextMarker) ||
        nextMarker <= marker || nextMarker < lastNumber || nextMarker >= 10000) {
      throw uploadError(503, 'OSS_UNAVAILABLE', '暂时无法确认视频分片状态');
    }
    marker = nextMarker;
  }
}

export const uploadRoutes: FastifyPluginAsync = async (app) => {
  const assertOwnedKey = (key: string, userId: string) => {
    const prefix = `videos/${userId}/`;
    if (!key.startsWith(prefix) || !/^\d{4}-(?:0[1-9]|1[0-2])\/[\w-]+\.(?:mp4|mov)$/.test(key.slice(prefix.length))) {
      throw app.httpErrors.forbidden('无权操作该上传任务');
    }
  };

  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const part = await request.file({ limits: { fileSize: 100 * 1024 * 1024, files: 1 } });
    const extension = part ? extensionByMime.get(part.mimetype) : null;
    if (!part || !extension) throw app.httpErrors.badRequest('仅支持 MP4/MOV/JPG/PNG/WebP');
    const date = new Date().toISOString().slice(0, 7);
    const relative = `${date}/${randomUUID()}${extension}`;
    const directory = resolve(config.UPLOAD_DIR, date);
    await mkdir(directory, { recursive: true });
    const target = resolve(config.UPLOAD_DIR, relative);
    await pipeline(part.file, createWriteStream(target));
    if (part.file.truncated) {
      await rm(target, { force: true });
      throw app.httpErrors.payloadTooLarge('文件不能超过 100MB');
    }
    return { url: `${config.PUBLIC_BASE_URL}/uploads/${relative}` };
  });

  app.post('/multipart/init', { preHandler: app.authenticate, config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request) => {
    const body = z.object({
      filename: z.string().min(1).max(180),
      mimeType: z.enum(['video/mp4', 'video/quicktime']),
      size: z.number().int().positive().max(1024 * 1024 * 1024)
    }).parse(request.body);
    const client = ossClient();
    const extension = body.mimeType === 'video/quicktime' ? '.mov' : '.mp4';
    const key = `videos/${request.user.sub}/${new Date().toISOString().slice(0, 7)}/${randomUUID()}${extension}`;
    try {
      const result = await client.initMultipartUpload(key, { mime: body.mimeType, headers: { 'Cache-Control': 'public, max-age=31536000' } });
      return { key, uploadId: result.uploadId, partSize: 5 * 1024 * 1024, size: body.size };
    } catch (error) {
      throw mapOssError(error);
    }
  });

  app.post('/multipart/part-url', { preHandler: app.authenticate }, async (request) => {
    const body = multipartSessionSchema.extend({ partNumber: z.number().int().min(1).max(10000) }).parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    try {
      const url = ossClient().signatureUrl(body.key, { method: 'PUT', expires: 900, subResource: { partNumber: String(body.partNumber), uploadId: body.uploadId } });
      return { url };
    } catch (error) {
      throw mapOssError(error);
    }
  });

  app.post('/multipart/status', { preHandler: app.authenticate }, async (request) => {
    const body = multipartSessionSchema.parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    const client = ossClient();
    try {
      return { state: 'uploading', parts: await uploadedParts(client, body.key, body.uploadId) };
    } catch (error) {
      if (providerCode(error) === 'NoSuchUpload') return completedObject(client, body.key);
      throw mapOssError(error);
    }
  });

  app.post('/multipart/complete', { preHandler: app.authenticate }, async (request) => {
    const body = multipartSessionSchema.extend({
      parts: z.array(uploadedPartSchema.omit({ size: true })).min(1).max(10000)
        .refine((parts) => new Set(parts.map((part) => part.number)).size === parts.length, '视频分片编号不能重复')
    }).parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    const client = ossClient();
    try {
      await client.completeMultipartUpload(body.key, body.uploadId, body.parts.sort((a, b) => a.number - b.number));
    } catch (error) {
      if (providerCode(error) !== 'NoSuchUpload') throw mapOssError(error);
      // Complete can succeed at OSS even if its HTTP response never reaches us.
      // Only the already-authorized exact object key can prove that outcome.
      await completedObject(client, body.key);
    }
    return { url: publicOssUrl(body.key) };
  });

  app.post('/multipart/abort', { preHandler: app.authenticate }, async (request) => {
    const body = multipartSessionSchema.parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    try {
      await ossClient().abortMultipartUpload(body.key, body.uploadId);
    } catch (error) {
      if (providerCode(error) !== 'NoSuchUpload') throw mapOssError(error);
    }
    return { aborted: true };
  });
};
