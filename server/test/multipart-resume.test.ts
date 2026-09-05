import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  transaction: vi.fn(),
  initMultipartUpload: vi.fn(),
  signatureUrl: vi.fn(),
  listParts: vi.fn(),
  head: vi.fn(),
  completeMultipartUpload: vi.fn(),
  abortMultipartUpload: vi.fn(),
  config: {
    NODE_ENV: 'test',
    JWT_SECRET: 'upload-resume-test-jwt-secret-at-least-16',
    UPLOAD_MODE: 'oss',
    UPLOAD_DIR: '',
    OSS_REGION: 'oss-cn-test',
    OSS_BUCKET: 'test-bucket',
    OSS_ACCESS_KEY_ID: 'test-access-key',
    OSS_ACCESS_KEY_SECRET: 'test-access-secret',
    OSS_PUBLIC_BASE_URL: 'https://cdn.example.com',
    PUBLIC_BASE_URL: 'https://api.example.com',
    WECHAT_APP_ID: '',
    WECHAT_APP_SECRET: '',
    WECHAT_MOBILE_APP_ID: '',
    WECHAT_MOBILE_APP_SECRET: '',
    APPLE_CLIENT_ID: 'com.wanpan.wanpanDiary',
    APPLE_TEAM_ID: 'TESTTEAM'
  }
}));

vi.mock('../src/config.js', () => ({ config: mocks.config }));
vi.mock('../src/db.js', () => ({ query: mocks.query, transaction: mocks.transaction }));
vi.mock('ali-oss', () => ({
  default: class {
    initMultipartUpload = mocks.initMultipartUpload;
    signatureUrl = mocks.signatureUrl;
    listParts = mocks.listParts;
    head = mocks.head;
    completeMultipartUpload = mocks.completeMultipartUpload;
    abortMultipartUpload = mocks.abortMultipartUpload;
  }
}));

import { buildApp } from '../src/app.js';

const viewerId = '00000000-0000-4000-8000-000000000001';
const key = `videos/${viewerId}/2026-09/attempt.mp4`;
const session = { key, uploadId: 'upload-id' };
const partSize = 5 * 1024 * 1024;
const completeBody = { ...session, parts: [{ number: 1, etag: 'etag-1' }] };
const providerError = (code: string, status?: number) => Object.assign(new Error('private provider detail'), { code, status });
let app: Awaited<ReturnType<typeof buildApp>>;
let uploadDir = '';
let authorization = '';

beforeEach(async () => {
  vi.resetAllMocks();
  mocks.config.UPLOAD_MODE = 'oss';
  uploadDir = await mkdtemp(join(tmpdir(), 'wanpan-multipart-resume-test-'));
  mocks.config.UPLOAD_DIR = uploadDir;
  mocks.query.mockResolvedValue({ rows: [{ id: viewerId, role: 'user' }] });
  mocks.initMultipartUpload.mockResolvedValue({ uploadId: 'upload-id' });
  mocks.signatureUrl.mockReturnValue('https://signed.example.com/part');
  mocks.listParts.mockResolvedValue({ parts: [], isTruncated: 'false' });
  mocks.head.mockResolvedValue({ status: 200, res: { headers: { 'content-length': '1500000' } } });
  mocks.completeMultipartUpload.mockResolvedValue({});
  mocks.abortMultipartUpload.mockResolvedValue({});
  app = await buildApp();
  app.log.level = 'silent';
  authorization = `Bearer ${app.jwt.sign({ sub: viewerId, role: 'user' })}`;
});

afterEach(async () => {
  await app?.close();
  if (uploadDir) await rm(uploadDir, { recursive: true, force: true });
});

function post(endpoint: string, payload: object = session) {
  return app.inject({
    method: 'POST', url: `/api/uploads/multipart/${endpoint}`,
    headers: { authorization }, payload
  });
}

describe('multipart resume authentication and ownership', () => {
  it.each([undefined, 'Bearer invalid-token'])('requires a valid session for status (%s)', async (token) => {
    const response = await app.inject({
      method: 'POST', url: '/api/uploads/multipart/status',
      headers: token ? { authorization: token } : {}, payload: session
    });
    expect(response.statusCode).toBe(401);
    expect(mocks.listParts).not.toHaveBeenCalled();
    expect(mocks.head).not.toHaveBeenCalled();
  });

  it('rejects a deleted account before checking OSS', async () => {
    mocks.query.mockResolvedValue({ rows: [] });
    const response = await post('status');
    expect(response.statusCode).toBe(401);
    expect(mocks.listParts).not.toHaveBeenCalled();
  });

  it.each([
    `videos/00000000-0000-4000-8000-000000000099/2026-09/attempt.mp4`,
    `videos/${viewerId}/../2026-09/attempt.mp4`,
    `videos/${viewerId}/2026-09/%2e%2e/attempt.mp4`,
    `videos/${viewerId}/2026-09/..%2fattempt.mp4`,
    `videos/${viewerId}/2026-09/..\\attempt.mp4`,
    `videos/${viewerId}/2026-09/attempt.mp4/extra`,
    `videos/${viewerId}/2026-09/attempt.mp4?x=1`
  ])('rejects an unowned or non-canonical key %s', async (invalidKey) => {
    for (const [endpoint, payload] of [
      ['status', session], ['complete', completeBody],
      ['part-url', { ...session, partNumber: 1 }], ['abort', session]
    ] as const) {
      const response = await post(endpoint, { ...payload, key: invalidKey });
      expect(response.statusCode).toBe(403);
    }
    expect(mocks.listParts).not.toHaveBeenCalled();
    expect(mocks.head).not.toHaveBeenCalled();
    expect(mocks.completeMultipartUpload).not.toHaveBeenCalled();
    expect(mocks.signatureUrl).not.toHaveBeenCalled();
    expect(mocks.abortMultipartUpload).not.toHaveBeenCalled();
  });

  it('validates status input before calling OSS', async () => {
    const response = await post('status', { key, uploadId: '' });
    expect(response.statusCode).toBe(400);
    expect(response.json().code).toBe('VALIDATION_ERROR');
    expect(mocks.listParts).not.toHaveBeenCalled();
  });
});

describe('multipart status reconciliation', () => {
  it('returns no completed parts for a new upload', async () => {
    const response = await post('status');
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ state: 'uploading', parts: [] });
    expect(mocks.head).not.toHaveBeenCalled();
  });

  it('follows pagination and normalizes OSS XML strings and singleton parts', async () => {
    mocks.listParts.mockResolvedValueOnce({
      isTruncated: 'true', nextPartNumberMarker: '2',
      parts: [
        { PartNumber: '1', ETag: '"etag-1"', Size: String(partSize) },
        { PartNumber: '2', ETag: '"etag-2"', Size: String(partSize) }
      ]
    }).mockResolvedValueOnce({
      isTruncated: 'false',
      parts: { PartNumber: '3', ETag: '"etag-3"', Size: '1500000' }
    });
    const response = await post('status');
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ state: 'uploading', parts: [
      { number: 1, etag: '"etag-1"', size: partSize },
      { number: 2, etag: '"etag-2"', size: partSize },
      { number: 3, etag: '"etag-3"', size: 1500000 }
    ] });
    expect(mocks.listParts).toHaveBeenNthCalledWith(1, key, 'upload-id', {
      'max-parts': 1000, 'part-number-marker': 0, 'encoding-type': 'url'
    });
    expect(mocks.listParts).toHaveBeenNthCalledWith(2, key, 'upload-id', {
      'max-parts': 1000, 'part-number-marker': 2, 'encoding-type': 'url'
    });
    expect(mocks.head).not.toHaveBeenCalled();
  });

  it.each([
    { parts: [], isTruncated: 'true', nextPartNumberMarker: 0 },
    { parts: [], isTruncated: 'maybe' },
    { parts: { PartNumber: '1', ETag: 'etag', Size: 'bad-size' }, isTruncated: false },
    { parts: [{ PartNumber: '2', ETag: 'etag', Size: '1' }], isTruncated: true, nextPartNumberMarker: 1 }
  ])('preserves the checkpoint when OSS returns malformed page data (%j)', async (page) => {
    mocks.listParts.mockResolvedValue(page);
    const response = await post('status');
    expect(response.statusCode).toBe(503);
    expect(response.json().code).toBe('OSS_UNAVAILABLE');
    expect(mocks.listParts).toHaveBeenCalledTimes(1);
    expect(mocks.head).not.toHaveBeenCalled();
  });

  it('recovers a completed upload after NoSuchUpload with the exact authorized key', async () => {
    mocks.listParts.mockRejectedValue(providerError('NoSuchUpload', 404));
    const response = await post('status');
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ state: 'completed', url: `https://cdn.example.com/${key}`, size: 1500000 });
    expect(mocks.head).toHaveBeenCalledExactlyOnceWith(key);
  });

  it('reports a missing upload only after both NoSuchUpload and NoSuchKey', async () => {
    mocks.listParts.mockRejectedValue(providerError('NoSuchUpload', 404));
    mocks.head.mockRejectedValue(providerError('NoSuchKey', 404));
    const response = await post('status');
    expect(response.statusCode).toBe(404);
    expect(response.json().code).toBe('UPLOAD_NOT_FOUND');
  });

  it.each([
    ['ConnectionTimeoutError', -2, 503, 'OSS_UNAVAILABLE'],
    ['ECONNRESET', undefined, 503, 'OSS_UNAVAILABLE'],
    ['UnknownError', 404, 503, 'OSS_UNAVAILABLE'],
    ['NoSuchBucket', 404, 503, 'OSS_UNAVAILABLE'],
    ['AccessDenied', 403, 403, 'OSS_ACCESS_DENIED']
  ])('does not mistake list error %s for a missing upload', async (code, status, expectedStatus, expectedCode) => {
    mocks.listParts.mockRejectedValue(providerError(code, status));
    const response = await post('status');
    expect(response.statusCode).toBe(expectedStatus);
    expect(response.json().code).toBe(expectedCode);
    expect(response.body).not.toContain('private provider detail');
    expect(mocks.head).not.toHaveBeenCalled();
  });

  it.each([
    ['ECONNRESET', undefined, 503, 'OSS_UNAVAILABLE'],
    ['UnknownError', 404, 503, 'OSS_UNAVAILABLE'],
    ['AccessDenied', 403, 403, 'OSS_ACCESS_DENIED']
  ])('does not mistake HEAD error %s for a missing object', async (code, status, expectedStatus, expectedCode) => {
    mocks.listParts.mockRejectedValue(providerError('NoSuchUpload', 404));
    mocks.head.mockRejectedValue(providerError(code, status));
    const response = await post('status');
    expect(response.statusCode).toBe(expectedStatus);
    expect(response.json().code).toBe(expectedCode);
    expect(response.body).not.toContain('private provider detail');
  });

  it('does not return a completed URL without a reliable object size', async () => {
    mocks.listParts.mockRejectedValue(providerError('NoSuchUpload', 404));
    mocks.head.mockResolvedValue({ status: 200, res: { headers: {} } });
    const response = await post('status');
    expect(response.statusCode).toBe(503);
    expect(response.json().code).toBe('OSS_UNAVAILABLE');
  });
});

describe('retry-safe multipart operations', () => {
  it('returns the same URL when a completed upload is completed again', async () => {
    mocks.completeMultipartUpload.mockResolvedValueOnce({}).mockRejectedValueOnce(providerError('NoSuchUpload', 404));
    const first = await post('complete', completeBody);
    const retry = await post('complete', completeBody);
    expect(first.statusCode).toBe(200);
    expect(retry.statusCode).toBe(200);
    expect(retry.json()).toEqual(first.json());
    expect(mocks.head).toHaveBeenCalledExactlyOnceWith(key);
  });

  it('allows a retry when completion succeeded remotely but its response was lost', async () => {
    mocks.completeMultipartUpload.mockRejectedValueOnce(providerError('ECONNRESET'))
      .mockRejectedValueOnce(providerError('NoSuchUpload', 404));
    const first = await post('complete', completeBody);
    expect(first.statusCode).toBe(503);
    expect(mocks.head).not.toHaveBeenCalled();
    const retry = await post('complete', completeBody);
    expect(retry.statusCode).toBe(200);
    expect(retry.json()).toEqual({ url: `https://cdn.example.com/${key}` });
  });

  it('does not call complete successfully when the session and object are both absent', async () => {
    mocks.completeMultipartUpload.mockRejectedValue(providerError('NoSuchUpload', 404));
    mocks.head.mockRejectedValue(providerError('NoSuchKey', 404));
    const response = await post('complete', completeBody);
    expect(response.statusCode).toBe(404);
    expect(response.json().code).toBe('UPLOAD_NOT_FOUND');
  });

  it.each([
    { parts: [{ number: 1, etag: 'etag-1' }, { number: 1, etag: 'etag-2' }] },
    { parts: [{ number: 10001, etag: 'etag-1' }] },
    { parts: [{ number: 1, etag: '</ETag><PartNumber>2</PartNumber><ETag>' }] }
  ])('rejects invalid complete parts before sending OSS XML (%j)', async ({ parts }) => {
    const response = await post('complete', { ...session, parts });
    expect(response.statusCode).toBe(400);
    expect(mocks.completeMultipartUpload).not.toHaveBeenCalled();
  });

  it('keeps abort idempotent without inspecting or deleting a completed object', async () => {
    mocks.abortMultipartUpload.mockRejectedValue(providerError('NoSuchUpload', 404));
    const response = await post('abort');
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ aborted: true });
    expect(mocks.head).not.toHaveBeenCalled();
  });

  it.each(['init', 'part-url', 'status', 'complete', 'abort'])('returns an explicit config code for %s local-mode fallback', async (endpoint) => {
    mocks.config.UPLOAD_MODE = 'local';
    const payload = endpoint === 'init' ? { filename: 'small.mp4', mimeType: 'video/mp4', size: 1500000 }
      : endpoint === 'complete' ? completeBody : { ...session, partNumber: 1 };
    const response = await post(endpoint, payload);
    expect(response.statusCode).toBe(503);
    expect(response.json().code).toBe('OSS_NOT_CONFIGURED');
    expect(mocks.initMultipartUpload).not.toHaveBeenCalled();
    expect(mocks.signatureUrl).not.toHaveBeenCalled();
    expect(mocks.listParts).not.toHaveBeenCalled();
    expect(mocks.completeMultipartUpload).not.toHaveBeenCalled();
    expect(mocks.abortMultipartUpload).not.toHaveBeenCalled();
  });

  it('initializes OSS multipart even when a video is smaller than one part', async () => {
    const response = await post('init', { filename: 'small.mp4', mimeType: 'video/mp4', size: 1500000 });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ uploadId: 'upload-id', partSize, size: 1500000 });
    expect(mocks.initMultipartUpload).toHaveBeenCalledOnce();
  });
});
