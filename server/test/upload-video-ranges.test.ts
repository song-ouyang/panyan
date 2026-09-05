import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  transaction: vi.fn(),
  config: {
    NODE_ENV: 'test',
    JWT_SECRET: 'unit-test-jwt-secret-at-least-16',
    UPLOAD_DIR: '',
    UPLOAD_MODE: 'local',
    PUBLIC_BASE_URL: 'https://api.example.com',
    OSS_REGION: 'oss-cn-test',
    OSS_BUCKET: '',
    OSS_ACCESS_KEY_ID: '',
    OSS_ACCESS_KEY_SECRET: '',
    OSS_PUBLIC_BASE_URL: '',
    WECHAT_APP_ID: '',
    WECHAT_APP_SECRET: '',
    WECHAT_MOBILE_APP_ID: '',
    WECHAT_MOBILE_APP_SECRET: '',
    APPLE_CLIENT_ID: 'com.wanpan.wanpanDiary',
    APPLE_TEAM_ID: 'TESTTEAM'
  }
}));

vi.mock('../src/db.js', () => ({ query: mocks.query, transaction: mocks.transaction }));
vi.mock('../src/config.js', () => ({ config: mocks.config }));

import { buildApp } from '../src/app.js';

// Binary content makes accidental text decoding or full-file responses observable.
const video = Buffer.from(Array.from({ length: 513 }, (_, index) => index % 256));
const videoPath = '/uploads/2026-09/attempt.mp4';
let app: Awaited<ReturnType<typeof buildApp>> | undefined;
let uploadDir = '';

beforeEach(async () => {
  vi.clearAllMocks();
  uploadDir = await mkdtemp(join(tmpdir(), 'wanpan-video-range-test-'));
  mocks.config.UPLOAD_DIR = uploadDir;
  await mkdir(join(uploadDir, '2026-09'));
  await writeFile(join(uploadDir, '2026-09/attempt.mp4'), video);
  await writeFile(join(uploadDir, '2026-09/attempt.mov'), video);
  app = await buildApp();
});

afterEach(async () => {
  try {
    await app?.close();
  } finally {
    app = undefined;
    if (uploadDir) await rm(uploadDir, { recursive: true, force: true });
  }
});

describe('uploaded video HTTP byte ranges through the real app', () => {
  it.each([
    ['mp4', 'video/mp4'],
    ['mov', 'video/quicktime']
  ])('serves a complete %s video to an unauthenticated GET', async (extension, contentType) => {
    const response = await app!.inject({
      method: 'GET',
      url: `/uploads/2026-09/attempt.${extension}`
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers['content-type']).toBe(contentType);
    expect(response.headers['accept-ranges']).toBe('bytes');
    expect(response.headers['content-length']).toBe(String(video.length));
    expect(response.headers['content-range']).toBeUndefined();
    expect(response.rawPayload).toEqual(video);
    expect(mocks.query).not.toHaveBeenCalled();
  });

  it('advertises the complete video length on HEAD without returning a body', async () => {
    const response = await app!.inject({ method: 'HEAD', url: videoPath });

    expect(response.statusCode).toBe(200);
    expect(response.headers['content-type']).toBe('video/mp4');
    expect(response.headers['accept-ranges']).toBe('bytes');
    expect(response.headers['content-length']).toBe(String(video.length));
    expect(response.headers['content-range']).toBeUndefined();
    expect(response.rawPayload.length).toBe(0);
  });

  it.each([
    ['bytes=0-1', 0, 1],
    ['bytes=256-300', 256, 300],
    ['bytes=510-', 510, 512],
    ['bytes=-3', 510, 512],
    ['bytes=510-999', 510, 512]
  ])('returns exactly the requested bytes for %s', async (range, start, end) => {
    const response = await app!.inject({
      method: 'GET',
      url: videoPath,
      headers: { range }
    });

    expect(response.statusCode).toBe(206);
    expect(response.headers['content-type']).toBe('video/mp4');
    expect(response.headers['accept-ranges']).toBe('bytes');
    expect(response.headers['content-range']).toBe(`bytes ${start}-${end}/${video.length}`);
    expect(response.headers['content-length']).toBe(String(end - start + 1));
    expect(response.rawPayload).toEqual(video.subarray(start, end + 1));
  });

  it('returns 416 with the actual length for a range starting beyond the video', async () => {
    const response = await app!.inject({
      method: 'GET',
      url: videoPath,
      headers: { range: `bytes=${video.length}-` }
    });

    expect(response.statusCode).toBe(416);
    expect(response.headers['content-range']).toBe(`bytes */${video.length}`);
    expect(response.rawPayload).not.toEqual(video);
  });
});
