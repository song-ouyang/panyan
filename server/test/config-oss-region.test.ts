import OSS from 'ali-oss';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Exercise the real environment parser without reading any developer .env.
vi.mock('dotenv', () => ({ config: vi.fn() }));

beforeEach(() => {
  vi.resetModules();
  const environment: Record<string, string | undefined> = {
    NODE_ENV: 'test',
    PORT: '3000',
    HOST: '127.0.0.1',
    DATABASE_URL: 'postgres://test:test@127.0.0.1/wanpan_config_test',
    PGPORT: '5432',
    JWT_SECRET: 'config-test-only-secret-not-for-production',
    UPLOAD_MODE: 'oss',
    OSS_REGION: undefined,
    OSS_BUCKET: 'wanpan-test',
    OSS_ACCESS_KEY_ID: 'test-access-key',
    OSS_ACCESS_KEY_SECRET: 'test-access-secret',
    OSS_PUBLIC_BASE_URL: 'https://cdn.example.com',
    PUBLIC_BASE_URL: 'https://api.example.com',
    ALIYUN_SMS_TEMPLATE_MIN: '5',
    MODERATION_MODE: 'off',
    ALLOW_PRODUCTION_GYM_IMPORT: 'false',
    ALLOW_PRODUCTION_SQUARE_SEED: 'false',
    WECHAT_MOBILE_APP_ID: '',
    WECHAT_MOBILE_APP_SECRET: '',
    ALIYUN_ACCESS_KEY_ID: '',
    ALIYUN_ACCESS_KEY_SECRET: '',
    ALIYUN_SMS_SIGN_NAME: '',
    ALIYUN_SMS_TEMPLATE_CODE: '',
    APP_REVIEW_LOGIN_PHONE: '',
    APP_REVIEW_LOGIN_CODE: ''
  };
  for (const [name, value] of Object.entries(environment)) vi.stubEnv(name, value);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('OSS region environment compatibility', () => {
  it.each([
    ['cn-chengdu', 'oss-cn-chengdu'],
    ['oss-cn-chengdu', 'oss-cn-chengdu'],
    ['cn-beijing', 'oss-cn-beijing'],
    ['oss-cn-beijing', 'oss-cn-beijing'],
    ['  cn-chengdu  ', 'oss-cn-chengdu'],
    ['OSS-CN-CHENGDU', 'oss-cn-chengdu'],
    ['ap-southeast-1', 'oss-ap-southeast-1'],
    ['us-west-1', 'oss-us-west-1'],
    ['oss-cn-chengdu-internal', 'oss-cn-chengdu-internal'],
    ['vpc100-oss-cn-hangzhou', 'vpc100-oss-cn-hangzhou']
  ])('normalizes %s to %s for SDK endpoint construction', async (configured, expected) => {
    vi.stubEnv('OSS_REGION', configured);
    const { config } = await import('../src/config.js');
    expect(config.OSS_REGION).toBe(expected);

    const client = new OSS({
      region: config.OSS_REGION,
      bucket: config.OSS_BUCKET,
      accessKeyId: config.OSS_ACCESS_KEY_ID,
      accessKeySecret: config.OSS_ACCESS_KEY_SECRET,
      secure: true
    });
    // Signing is local: verify the real SDK host without creating an upload or
    // making a network request, and never print the signed URL.
    const url = new URL(client.signatureUrl('videos/config-test.mp4'));
    expect(url.protocol).toBe('https:');
    expect(url.hostname).toBe(`wanpan-test.${expected}.aliyuncs.com`);
  });

  it('retains the existing default region when the setting is absent', async () => {
    const { config } = await import('../src/config.js');
    expect(config.OSS_REGION).toBe('oss-cn-shenzhen');
  });

  it.each([
    '',
    '   ',
    'https://oss-cn-chengdu.aliyuncs.com',
    'oss-cn-chengdu.aliyuncs.com',
    'wanpan-test.oss-cn-chengdu.aliyuncs.com',
    'cn chengdu',
    'cn-chengdu/path',
    'cn-chengdu?uploads'
  ])('rejects malformed or endpoint-valued OSS_REGION: %s', async (region) => {
    vi.stubEnv('OSS_REGION', region);
    await expect(import('../src/config.js')).rejects.toMatchObject({
      issues: expect.arrayContaining([
        expect.objectContaining({
          path: ['OSS_REGION'],
          message: expect.stringContaining('地域 ID')
        })
      ])
    });
  });
});
