import type { FastifyPluginAsync } from 'fastify';
import { createWriteStream } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { randomUUID } from 'node:crypto';
import OSS from 'ali-oss';
import { z } from 'zod';
import { config } from '../config.js';

const allowed = new Set(['video/mp4', 'video/quicktime', 'image/jpeg', 'image/png', 'image/webp']);

function ossClient() {
  if (config.UPLOAD_MODE !== 'oss' || !config.OSS_BUCKET || !config.OSS_ACCESS_KEY_ID || !config.OSS_ACCESS_KEY_SECRET) {
    throw new Error('OSS 分片上传尚未配置');
  }
  return new OSS({ region: config.OSS_REGION, bucket: config.OSS_BUCKET, accessKeyId: config.OSS_ACCESS_KEY_ID, accessKeySecret: config.OSS_ACCESS_KEY_SECRET, secure: true });
}

function assertOwnedKey(key: string, userId: string) {
  if (!key.startsWith(`videos/${userId}/`) || key.includes('..')) throw new Error('无权操作该上传任务');
}

function publicOssUrl(key: string) {
  const base = config.OSS_PUBLIC_BASE_URL || `https://${config.OSS_BUCKET}.${config.OSS_REGION}.aliyuncs.com`;
  return `${base.replace(/\/$/, '')}/${key.split('/').map(encodeURIComponent).join('/')}`;
}

export const uploadRoutes: FastifyPluginAsync = async (app) => {
  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const part = await request.file({ limits: { fileSize: 100 * 1024 * 1024, files: 1 } });
    if (!part || !allowed.has(part.mimetype)) throw app.httpErrors.badRequest('仅支持 MP4/MOV/JPG/PNG/WebP');
    const extension = extname(part.filename).toLowerCase() || (part.mimetype.startsWith('video/') ? '.mp4' : '.jpg');
    const date = new Date().toISOString().slice(0, 7);
    const relative = `${date}/${randomUUID()}${extension}`;
    const directory = resolve(config.UPLOAD_DIR, date);
    await mkdir(directory, { recursive: true });
    await pipeline(part.file, createWriteStream(resolve(config.UPLOAD_DIR, relative)));
    return { url: `${config.PUBLIC_BASE_URL}/uploads/${relative}` };
  });

  app.post('/multipart/init', { preHandler: app.authenticate, config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request) => {
    const body = z.object({ filename: z.string().min(1).max(180), mimeType: z.literal('video/mp4'), size: z.number().int().positive().max(1024 * 1024 * 1024) }).parse(request.body);
    const client = ossClient();
    const key = `videos/${request.user.sub}/${new Date().toISOString().slice(0, 7)}/${randomUUID()}.mp4`;
    const result = await client.initMultipartUpload(key, { mime: body.mimeType, headers: { 'Cache-Control': 'public, max-age=31536000' } });
    return { key, uploadId: result.uploadId, partSize: 5 * 1024 * 1024, size: body.size };
  });

  app.post('/multipart/part-url', { preHandler: app.authenticate }, async (request) => {
    const body = z.object({ key: z.string(), uploadId: z.string().min(1), partNumber: z.number().int().min(1).max(10000) }).parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    const url = ossClient().signatureUrl(body.key, { method: 'PUT', expires: 900, subResource: { partNumber: String(body.partNumber), uploadId: body.uploadId } });
    return { url };
  });

  app.post('/multipart/complete', { preHandler: app.authenticate }, async (request) => {
    const body = z.object({ key: z.string(), uploadId: z.string().min(1), parts: z.array(z.object({ number: z.number().int().positive(), etag: z.string().min(1) })).min(1).max(10000) }).parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    await ossClient().completeMultipartUpload(body.key, body.uploadId, body.parts.sort((a, b) => a.number - b.number));
    return { url: publicOssUrl(body.key) };
  });

  app.post('/multipart/abort', { preHandler: app.authenticate }, async (request) => {
    const body = z.object({ key: z.string(), uploadId: z.string().min(1) }).parse(request.body);
    assertOwnedKey(body.key, request.user.sub);
    await ossClient().abortMultipartUpload(body.key, body.uploadId);
    return { aborted: true };
  });
};
