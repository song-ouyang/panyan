import { createHash } from 'node:crypto';
import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import sensible from '@fastify/sensible';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

const mocks = vi.hoisted(() => {
  class SmsProviderError extends Error {
    constructor(message: string, readonly statusCode = 503) {
      super(message);
    }
  }
  return {
    query: vi.fn(),
    jwtVerify: vi.fn(),
    sendSmsCode: vi.fn(),
    verifySmsCode: vi.fn(),
    SmsProviderError,
    config: {
      NODE_ENV: 'development',
      WECHAT_APP_ID: '',
      WECHAT_APP_SECRET: '',
      WECHAT_MOBILE_APP_ID: 'wx-mobile-test',
      WECHAT_MOBILE_APP_SECRET: 'mobile-secret',
      APPLE_CLIENT_ID: 'com.wanpan.wanpanDiary'
    }
  };
});

vi.mock('../src/db.js', () => ({ query: mocks.query }));
vi.mock('../src/config.js', () => ({ config: mocks.config }));
vi.mock('../src/services/sms_provider.js', () => ({
  SmsProviderError: mocks.SmsProviderError,
  sendSmsCode: mocks.sendSmsCode,
  verifySmsCode: mocks.verifySmsCode
}));
vi.mock('jose', () => ({
  createRemoteJWKSet: vi.fn(() => 'apple-jwks'),
  jwtVerify: mocks.jwtVerify
}));

import { authRoutes } from '../src/routes/auth.js';

const user = {
  id: '00000000-0000-4000-8000-000000000001',
  nickname: '岩友',
  avatar_url: null,
  role: 'user',
  profile_completed: false
};

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });
  app.decorateReply('jwtSign', async () => 'signed-session-token');
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: error.issues[0]?.message,
      });
    }
    return reply.send(error);
  });
  await app.register(authRoutes, { prefix: '/api/auth' });
  return app;
}

beforeEach(() => {
  mocks.query.mockReset();
  mocks.query.mockResolvedValue({ rows: [user], rowCount: 1 });
  mocks.jwtVerify.mockReset();
  mocks.sendSmsCode.mockReset();
  mocks.verifySmsCode.mockReset();
  mocks.sendSmsCode.mockResolvedValue(undefined);
  mocks.verifySmsCode.mockResolvedValue({ isReview: false });
  mocks.config.NODE_ENV = 'development';
  mocks.config.WECHAT_APP_ID = '';
  mocks.config.WECHAT_APP_SECRET = '';
  mocks.config.WECHAT_MOBILE_APP_ID = 'wx-mobile-test';
  mocks.config.WECHAT_MOBILE_APP_SECRET = 'mobile-secret';
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('authentication routes', () => {
  it('sends a phone verification code without creating a user', async () => {
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/send',
      payload: { phone: '13800138000' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ sent: true });
    expect(mocks.sendSmsCode).toHaveBeenCalledWith('13800138000');
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('creates a completed App Review session after fixed-code verification', async () => {
    mocks.verifySmsCode.mockResolvedValue({ isReview: true });
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/login',
      payload: { phone: '19000000001', code: '135790' }
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.verifySmsCode).toHaveBeenCalledWith('19000000001', '135790');
    expect(mocks.query.mock.calls[0]![1]).toEqual([
      'phone:+8619000000001',
      'App 审核员',
      null,
      true,
      []
    ]);
    await app.close();
  });

  it('rejects malformed SMS login input before calling the provider', async () => {
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/login',
      payload: { phone: '123', code: '12' }
    });

    expect(response.statusCode).toBe(400);
    expect(mocks.verifySmsCode).not.toHaveBeenCalled();
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('does not create a session when SMS verification fails', async () => {
    mocks.verifySmsCode.mockRejectedValue(
      new mocks.SmsProviderError('验证码错误或已过期。', 401)
    );
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/login',
      payload: { phone: '13800138000', code: '000000' }
    });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns service unavailable when the SMS provider cannot send', async () => {
    mocks.sendSmsCode.mockRejectedValue(
      new mocks.SmsProviderError('短信服务暂不可用，请稍后重试。')
    );
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/send',
      payload: { phone: '13800138000' }
    });

    expect(response.statusCode).toBe(503);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it.each([
    { scope: 'phone', max: 8 },
    { scope: 'IP', max: 20 }
  ])('limits SMS login by $scope for five minutes with an accurate Retry-After', async ({ scope, max }) => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const start = Date.parse('2026-09-05T08:00:00Z');
    vi.setSystemTime(start);
    mocks.verifySmsCode.mockRejectedValue(
      new mocks.SmsProviderError('验证码错误或已过期。', 401)
    );
    const app = await createApp();
    const attemptLogin = (attempt: number) => app.inject({
      method: 'POST',
      url: '/api/auth/sms/login',
      remoteAddress: scope === 'phone' ? `10.0.0.${attempt + 1}` : '10.0.0.1',
      payload: {
        phone: scope === 'phone' ? '13800138000' : `1390000${String(attempt).padStart(4, '0')}`,
        code: '000000'
      }
    });
    for (let attempt = 0; attempt < max; attempt += 1) {
      const response = await attemptLogin(attempt);
      expect(response.statusCode).toBe(401);
    }
    const blocked = await attemptLogin(max);
    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers).toMatchObject({
      'retry-after': '300',
      'x-ratelimit-reset': '300',
      'x-ratelimit-limit': String(max),
      'x-ratelimit-remaining': '0'
    });

    vi.setSystemTime(start + 2 * 60_000);
    const stillBlocked = await attemptLogin(max + 1);
    expect(stillBlocked.statusCode).toBe(429);
    expect(stillBlocked.headers['retry-after']).toBe('180');
    vi.setSystemTime(start + 5 * 60_000 - 1);
    const almostExpired = await attemptLogin(max + 2);
    expect(almostExpired.statusCode).toBe(429);
    expect(almostExpired.headers['retry-after']).toBe('1');
    expect(mocks.verifySmsCode).toHaveBeenCalledTimes(max);
    expect(mocks.query).not.toHaveBeenCalled();

    vi.setSystemTime(start + 5 * 60_000);
    mocks.verifySmsCode.mockResolvedValue({ isReview: false });
    const unblocked = await attemptLogin(max + 3);
    expect(unblocked.statusCode).toBe(200);
    expect(unblocked.headers['retry-after']).toBeUndefined();
    expect(mocks.verifySmsCode).toHaveBeenCalledTimes(max + 1);
    expect(mocks.query).toHaveBeenCalledOnce();
    await app.close();
  });

  it('normalizes whitespace before applying the per-phone send limit', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-05T08:00:00Z'));
    const app = await createApp();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const response = await app.inject({
        method: 'POST',
        url: '/api/auth/sms/send',
        payload: { phone: ' 13800138000 ' }
      });
      expect(response.statusCode).toBe(200);
    }
    const blocked = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/send',
      payload: { phone: '13800138000' }
    });

    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers['retry-after']).toBe('600');
    expect(mocks.sendSmsCode).toHaveBeenCalledTimes(5);
    await app.close();
  });

  it('limits SMS sends by IP even when every phone number is different', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-05T08:00:00Z'));
    const app = await createApp();
    for (let attempt = 0; attempt < 10; attempt += 1) {
      const response = await app.inject({
        method: 'POST',
        url: '/api/auth/sms/send',
        payload: { phone: `1390000000${attempt}` }
      });
      expect(response.statusCode).toBe(200);
    }
    const blocked = await app.inject({
      method: 'POST',
      url: '/api/auth/sms/send',
      payload: { phone: '13900000010' }
    });

    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers['retry-after']).toBe('600');
    expect(mocks.sendSmsCode).toHaveBeenCalledTimes(10);
    await app.close();
  });

  it('allows an explicit development mini-program login only outside production', async () => {
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat',
      payload: { code: 'dev:flutter' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      token: 'signed-session-token',
      needsProfile: true,
      user: { id: user.id, profileCompleted: false }
    });
    expect(mocks.query.mock.calls[0]![1][0]).toBe('dev:flutter');
    await app.close();
  });

  it('never accepts a development login code in production', async () => {
    mocks.config.NODE_ENV = 'production';
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat',
      payload: { code: 'dev:flutter' }
    });

    expect(response.statusCode).toBe(503);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('exchanges a production mini-program code and unifies by unionid', async () => {
    mocks.config.NODE_ENV = 'production';
    mocks.config.WECHAT_APP_ID = 'wx-mini-test';
    mocks.config.WECHAT_APP_SECRET = 'mini-secret';
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ openid: 'mini-openid', unionid: 'shared-unionid' })
    });
    vi.stubGlobal('fetch', fetchMock);
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat',
      payload: { code: 'mini-once-only-code' }
    });

    expect(response.statusCode).toBe(200);
    expect(String(fetchMock.mock.calls[0]![0])).toContain('sns/jscode2session');
    expect(mocks.query.mock.calls[0]![1]).toEqual([
      'wechat:shared-unionid',
      '岩友',
      null,
      false,
      ['mini-openid', 'wechat-mini:mini-openid']
    ]);
    await app.close();
  });

  it('reports missing native WeChat server configuration clearly', async () => {
    mocks.config.WECHAT_MOBILE_APP_ID = '';
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat-mobile',
      payload: { code: 'once-only-code' }
    });

    expect(response.statusCode).toBe(503);
    expect(response.json().message).toContain('尚未配置');
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('exchanges a mobile WeChat code and keys the account by unionid', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          access_token: 'provider-access-token',
          openid: 'mobile-openid',
          unionid: 'shared-unionid'
        })
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          openid: 'mobile-openid',
          unionid: 'shared-unionid',
          nickname: '小欧',
          headimgurl: 'http://example.com/avatar.jpg'
        })
      });
    vi.stubGlobal('fetch', fetchMock);
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat-mobile',
      payload: { code: 'once-only-code' }
    });

    expect(response.statusCode).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[0]![0])).toContain('sns/oauth2/access_token');
    expect(String(fetchMock.mock.calls[1]![0])).toContain('sns/userinfo');
    const values = mocks.query.mock.calls[0]![1];
    expect(values[0]).toBe('wechat:shared-unionid');
    expect(values[2]).toBe('https://example.com/avatar.jpg');
    await app.close();
  });

  it('rejects a failed mobile WeChat code exchange without creating a local account', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ errcode: 40029, errmsg: 'invalid code' })
    }));
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat-mobile',
      payload: { code: 'expired-code' }
    });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('strictly verifies Apple issuer, audience, algorithm, expiry and nonce', async () => {
    const rawNonce = 'raw-nonce-at-least-sixteen-characters';
    const nonce = createHash('sha256').update(rawNonce).digest('hex');
    const now = Math.floor(Date.now() / 1000);
    mocks.jwtVerify.mockResolvedValue({
      payload: { sub: 'apple-subject', nonce, iat: now - 2, exp: now + 300 }
    });
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/apple',
      payload: {
        identityToken: 'x'.repeat(120),
        rawNonce,
        givenName: 'Song',
        familyName: 'Ouyang'
      }
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.jwtVerify).toHaveBeenCalledWith(
      'x'.repeat(120),
      'apple-jwks',
      expect.objectContaining({
        algorithms: ['RS256'],
        issuer: 'https://appleid.apple.com',
        audience: 'com.wanpan.wanpanDiary'
      })
    );
    expect(mocks.query.mock.calls[0]![1][0]).toBe('apple:apple-subject');
    await app.close();
  });

  it('rejects an Apple token whose nonce is not bound to this login attempt', async () => {
    const now = Math.floor(Date.now() / 1000);
    mocks.jwtVerify.mockResolvedValue({
      payload: {
        sub: 'apple-subject',
        nonce: 'wrong-nonce',
        iat: now - 2,
        exp: now + 300
      }
    });
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/apple',
      payload: {
        identityToken: 'x'.repeat(120),
        rawNonce: 'raw-nonce-at-least-sixteen-characters'
      }
    });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('rejects Apple claims issued unreasonably far in the future', async () => {
    const rawNonce = 'raw-nonce-at-least-sixteen-characters';
    const nonce = createHash('sha256').update(rawNonce).digest('hex');
    const now = Math.floor(Date.now() / 1000);
    mocks.jwtVerify.mockResolvedValue({
      payload: { sub: 'apple-subject', nonce, iat: now + 120, exp: now + 600 }
    });
    const app = await createApp();
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/apple',
      payload: {
        identityToken: 'x'.repeat(120),
        rawNonce
      }
    });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });
});
