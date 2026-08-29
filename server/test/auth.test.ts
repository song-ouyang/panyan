import { createHash } from 'node:crypto';
import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  jwtVerify: vi.fn(),
  config: {
    NODE_ENV: 'development',
    WECHAT_APP_ID: '',
    WECHAT_APP_SECRET: '',
    WECHAT_MOBILE_APP_ID: 'wx-mobile-test',
    WECHAT_MOBILE_APP_SECRET: 'mobile-secret',
    APPLE_CLIENT_ID: 'com.wanpan.wanpanDiary'
  }
}));

vi.mock('../src/db.js', () => ({ query: mocks.query }));
vi.mock('../src/config.js', () => ({ config: mocks.config }));
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
  app.decorateReply('jwtSign', async () => 'signed-session-token');
  await app.register(authRoutes, { prefix: '/api/auth' });
  return app;
}

beforeEach(() => {
  mocks.query.mockReset();
  mocks.query.mockResolvedValue({ rows: [user], rowCount: 1 });
  mocks.jwtVerify.mockReset();
  mocks.config.NODE_ENV = 'development';
  mocks.config.WECHAT_APP_ID = '';
  mocks.config.WECHAT_APP_SECRET = '';
  mocks.config.WECHAT_MOBILE_APP_ID = 'wx-mobile-test';
  mocks.config.WECHAT_MOBILE_APP_SECRET = 'mobile-secret';
});

afterEach(() => vi.unstubAllGlobals());

describe('authentication routes', () => {
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
