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
    UPLOAD_DIR: '/tmp/wanpan-public-pages-test',
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
    APPLE_CLIENT_ID: '',
    APPLE_TEAM_ID: ''
  }
}));

import { buildApp } from '../src/app.js';

beforeEach(async () => {
  vi.clearAllMocks();
  await mkdir('/tmp/wanpan-public-pages-test', { recursive: true });
});

describe('public App Store information pages', () => {
  it.each([
    ['/privacy', '完攀日记隐私政策'],
    ['/privacy-choices', '隐私选择与账号删除'],
    ['/terms', '完攀日记用户协议'],
    ['/support', '完攀日记支持与联系']
  ])('serves %s as a public HTML page', async (url, title) => {
    const app = await buildApp();
    const response = await app.inject({ method: 'GET', url });

    expect(response.statusCode).toBe(200);
    expect(response.headers['content-type']).toContain('text/html');
    expect(response.headers['cache-control']).toBe('public, max-age=300');
    expect(response.headers['content-security-policy']).toContain("default-src 'none'");
    expect(response.headers['referrer-policy']).toBe('no-referrer');
    expect(response.headers['x-frame-options']).toBe('DENY');
    expect(response.body).toContain(title);
    expect(response.body).toContain('ouyangsong8@gmail.com');
    expect(response.body).not.toMatch(/正式上线前|请补充|example\.com/);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('documents the data deletion path without requiring authentication', async () => {
    const app = await buildApp();
    const response = await app.inject({
      method: 'GET',
      url: '/privacy-choices'
    });

    expect(response.statusCode).toBe(200);
    expect(response.body).toContain('注销账号并删除数据');
    expect(response.body).toContain('完攀日记账号删除');
    await app.close();
  });
});
