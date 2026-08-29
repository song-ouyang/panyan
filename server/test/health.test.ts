import { mkdir } from 'node:fs/promises';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  transaction: vi.fn()
}));

vi.mock('../src/db.js', () => ({
  query: mocks.query,
  transaction: mocks.transaction
}));

vi.mock('../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    JWT_SECRET: 'unit-test-jwt-secret-at-least-16',
    UPLOAD_DIR: '/tmp/wanpan-health-test',
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

import { buildApp } from '../src/app.js';

beforeEach(async () => {
  vi.clearAllMocks();
  await mkdir('/tmp/wanpan-health-test', { recursive: true });
});

describe('health and database readiness', () => {
  it('keeps liveness independent from the database', async () => {
    mocks.query.mockRejectedValue(new Error('database unavailable'));
    const app = await buildApp();
    const response = await app.inject({ method: 'GET', url: '/health' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ ok: true });
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns ready only after a successful database probe', async () => {
    mocks.query.mockResolvedValue({ rows: [{ '?column?': 1 }], rowCount: 1 });
    const app = await buildApp();
    const response = await app.inject({ method: 'GET', url: '/ready' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ ok: true, database: 'ready' });
    expect(mocks.query).toHaveBeenCalledWith('SELECT 1');
    await app.close();
  });

  it('returns 503 without exposing the database error when readiness fails', async () => {
    mocks.query.mockRejectedValue(new Error('sensitive connection detail'));
    const app = await buildApp();
    const response = await app.inject({ method: 'GET', url: '/ready' });

    expect(response.statusCode).toBe(503);
    expect(response.json()).toEqual({ ok: false, database: 'unavailable' });
    expect(response.body).not.toContain('sensitive connection detail');
    await app.close();
  });
});
