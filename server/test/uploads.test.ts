import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Fastify from 'fastify';
import multipart from '@fastify/multipart';
import sensible from '@fastify/sensible';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  initMultipartUpload: vi.fn(),
  signatureUrl: vi.fn(),
  completeMultipartUpload: vi.fn(),
  abortMultipartUpload: vi.fn(),
  config: {
    UPLOAD_MODE: 'oss',
    OSS_REGION: 'oss-cn-test',
    OSS_BUCKET: 'test-bucket',
    OSS_ACCESS_KEY_ID: 'test-access-key',
    OSS_ACCESS_KEY_SECRET: 'test-access-secret',
    OSS_PUBLIC_BASE_URL: 'https://cdn.example.com',
    PUBLIC_BASE_URL: 'https://api.example.com',
    UPLOAD_DIR: ''
  }
}));

vi.mock('../src/config.js', () => ({ config: mocks.config }));
vi.mock('ali-oss', () => ({
  default: class {
    initMultipartUpload = mocks.initMultipartUpload;
    signatureUrl = mocks.signatureUrl;
    completeMultipartUpload = mocks.completeMultipartUpload;
    abortMultipartUpload = mocks.abortMultipartUpload;
  }
}));

import { uploadRoutes } from '../src/routes/uploads.js';

const viewerId = '00000000-0000-4000-8000-000000000001';
let uploadDir = '';

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  await app.register(multipart);
  app.decorate('authenticate', async (request) => {
    request.user = { sub: viewerId, role: 'user' };
  });
  await app.register(uploadRoutes, { prefix: '/api/uploads' });
  return app;
}

function multipartPayload(input: { filename: string; mimeType: string; contents: string }) {
  const boundary = '----wanpan-upload-test';
  const body = Buffer.from(
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${input.filename}"\r\n` +
    `Content-Type: ${input.mimeType}\r\n\r\n` +
    `${input.contents}\r\n` +
    `--${boundary}--\r\n`
  );
  return { body, headers: { 'content-type': `multipart/form-data; boundary=${boundary}` } };
}

beforeEach(async () => {
  vi.clearAllMocks();
  uploadDir = await mkdtemp(join(tmpdir(), 'wanpan-upload-test-'));
  mocks.config.UPLOAD_DIR = uploadDir;
  mocks.config.UPLOAD_MODE = 'oss';
  mocks.initMultipartUpload.mockResolvedValue({ uploadId: 'upload-id' });
  mocks.signatureUrl.mockReturnValue('https://signed.example.com/part');
  mocks.completeMultipartUpload.mockResolvedValue({});
  mocks.abortMultipartUpload.mockResolvedValue({});
});

afterEach(async () => {
  if (uploadDir) await rm(uploadDir, { recursive: true, force: true });
});

describe('upload safety and ownership', () => {
  it('derives the stored extension from trusted MIME instead of the user filename', async () => {
    mocks.config.UPLOAD_MODE = 'local';
    const app = await createApp();
    const upload = multipartPayload({
      filename: 'avatar.html',
      mimeType: 'image/jpeg',
      contents: 'not-a-real-jpeg-but-streaming-is-covered'
    });

    const response = await app.inject({
      method: 'POST',
      url: '/api/uploads',
      headers: upload.headers,
      payload: upload.body
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().url).toMatch(/^https:\/\/api\.example\.com\/uploads\/\d{4}-\d{2}\/[\w-]+\.jpg$/);
    expect(response.json().url).not.toContain('.html');
    const [month] = await readdir(uploadDir);
    expect(month).toMatch(/^\d{4}-\d{2}$/);
    expect((await readdir(join(uploadDir, month!)))[0]).toMatch(/\.jpg$/);
    await app.close();
  });

  it('rejects an unsupported MIME type before storing it', async () => {
    mocks.config.UPLOAD_MODE = 'local';
    const app = await createApp();
    const upload = multipartPayload({ filename: 'payload.svg', mimeType: 'image/svg+xml', contents: '<svg />' });

    const response = await app.inject({
      method: 'POST',
      url: '/api/uploads',
      headers: upload.headers,
      payload: upload.body
    });

    expect(response.statusCode).toBe(400);
    expect(await readdir(uploadDir)).toEqual([]);
    await app.close();
  });

  it('creates multipart uploads only under the authenticated user prefix', async () => {
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/uploads/multipart/init',
      payload: { filename: 'attempt.exe', mimeType: 'video/mp4', size: 8_000_000 }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ uploadId: 'upload-id', partSize: 5 * 1024 * 1024, size: 8_000_000 });
    expect(response.json().key).toMatch(new RegExp(`^videos/${viewerId}/\\d{4}-\\d{2}/[\\w-]+\\.mp4$`));
    expect(mocks.initMultipartUpload).toHaveBeenCalledWith(
      response.json().key,
      expect.objectContaining({ mime: 'video/mp4' })
    );
    await app.close();
  });

  it('returns 403 and never signs a part belonging to another user', async () => {
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/uploads/multipart/part-url',
      payload: {
        key: 'videos/00000000-0000-4000-8000-000000000099/2026-08/file.mp4',
        uploadId: 'foreign-upload',
        partNumber: 1
      }
    });

    expect(response.statusCode).toBe(403);
    expect(mocks.signatureUrl).not.toHaveBeenCalled();
    await app.close();
  });

  it('sorts completed parts and returns the configured public object URL', async () => {
    const app = await createApp();
    const key = `videos/${viewerId}/2026-08/video.mp4`;
    const response = await app.inject({
      method: 'POST',
      url: '/api/uploads/multipart/complete',
      payload: {
        key,
        uploadId: 'upload-id',
        parts: [{ number: 2, etag: 'etag-2' }, { number: 1, etag: 'etag-1' }]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ url: `https://cdn.example.com/${key}` });
    expect(mocks.completeMultipartUpload).toHaveBeenCalledWith(key, 'upload-id', [
      { number: 1, etag: 'etag-1' },
      { number: 2, etag: 'etag-2' }
    ]);
    await app.close();
  });
});
