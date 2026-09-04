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
    JWT_SECRET: 'validation-test-jwt-secret-at-least-16',
    UPLOAD_DIR: '/tmp/wanpan-validation-errors-test',
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
  await mkdir('/tmp/wanpan-validation-errors-test', { recursive: true });
});

describe('global request validation errors', () => {
  it.each([
    {
      name: 'an empty SMS login body',
      request: {
        method: 'POST' as const,
        url: '/api/auth/sms/login',
        payload: {}
      },
      issuePath: 'phone'
    },
    {
      name: 'an invalid ranking gym id',
      request: {
        method: 'GET' as const,
        url: '/api/rankings?gymId=not-a-uuid'
      },
      issuePath: 'gymId'
    }
  ])('maps $name to a safe 400 response before database access', async ({ request, issuePath }) => {
    const app = await buildApp();

    const response = await app.inject(request);

    expect(response.statusCode).toBe(400);
    const body = response.json();
    expect(body.code).toBe('VALIDATION_ERROR');
    expect(body.issues).toEqual(
      expect.arrayContaining([expect.objectContaining({ path: [issuePath] })])
    );
    expect(body).not.toHaveProperty('statusCode');
    expect(body).not.toHaveProperty('error');
    expect(mocks.query).not.toHaveBeenCalled();
    expect(mocks.transaction).not.toHaveBeenCalled();
    await app.close();
  });
});
