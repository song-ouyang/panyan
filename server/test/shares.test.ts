import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import rateLimit from '@fastify/rate-limit';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

const mocks = vi.hoisted(() => ({ query: vi.fn() }));
vi.mock('../src/db.js', () => ({ query: mocks.query }));
vi.mock('../src/config.js', () => ({ config: { JWT_SECRET: 'share-tests-secret-at-least-32-characters' } }));

import { authPlugin } from '../src/auth.js';
import { shareRoutes } from '../src/routes/shares.js';

const ownerId = '00000000-0000-4000-8000-000000000301';
const routeId = '00000000-0000-4000-8000-000000000302';
const shareToken = 'a'.repeat(43);
const result = (rows: unknown[] = []) => ({ rows, rowCount: rows.length });
const apps: Awaited<ReturnType<typeof createApp>>[] = [];

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
    return reply.send(error);
  });
  await app.register(authPlugin);
  await app.register(shareRoutes, { prefix: '/api/shares' });
  apps.push(app);
  return app;
}

function authenticateNext() {
  mocks.query.mockResolvedValueOnce(result([{ id: ownerId, role: 'user' }]));
}

function authHeader(app: Awaited<ReturnType<typeof createApp>>) {
  return { authorization: `Bearer ${app.jwt.sign({ sub: ownerId, role: 'user' })}` };
}

beforeEach(() => { mocks.query.mockReset(); });
afterEach(async () => { await Promise.all(apps.splice(0).map((app) => app.close())); });

describe('share API public data and authentication', () => {
  it('returns only the published route allowlist without featured sends or submitter data', async () => {
    const route = {
      id: routeId, name: '橙色线', grade: 'V3', color: '橙色', wall_zone: 'A 区',
      cover_url: 'https://example.com/wall.jpg', points: [{ x: 0.2, y: 0.8, type: 'start' }],
      gym_name: '测试岩馆', gym_address: '测试地址', route_set_name: '九月换线', send_count: 2
    };
    mocks.query.mockResolvedValue(result([{ ...route, user_id: ownerId, featuredSend: { caption: '不可分享' } }]));
    const app = await createApp();
    const response = await app.inject(`/api/shares/routes/${routeId}`);
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ kind: 'route', route });
    expect(Object.keys(response.json().route)).toEqual(Object.keys(route));
    expect(response.body).not.toContain('不可分享');
    expect(mocks.query.mock.calls[0]![0]).toContain('r.published=true');
    expect(mocks.query.mock.calls[0]![0]).toContain("s.visibility='public'");
    expect(mocks.query.mock.calls[0]![1]).toEqual([routeId]);
  });

  it('returns 404 for a missing or unpublished route', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp();
    const response = await app.inject(`/api/shares/routes/${routeId}`);
    expect(response.statusCode).toBe(404);
  });

  it.each([`/api/shares/routes/${routeId}`, `/api/shares/monthly/${shareToken}`])(
    'rejects an invalid JWT on a public share: %s', async (url) => {
      const app = await createApp();
      const response = await app.inject({ url, headers: { authorization: 'Bearer invalid' } });
      expect(response.statusCode).toBe(401);
      expect(response.headers['cache-control']).toContain('no-store');
      expect(mocks.query).not.toHaveBeenCalled();
    }
  );

  it.each(['GET', 'POST', 'DELETE'] as const)('requires a session to %s monthly share management', async (method) => {
    const app = await createApp();
    const response = await app.inject({ method, url: method === 'DELETE' ? `/api/shares/monthly/${shareToken}` : '/api/shares/monthly?month=2026-08' });
    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
  });

  it('rejects a valid JWT for a deleted account', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp();
    const response = await app.inject({ method: 'POST', url: '/api/shares/monthly', headers: authHeader(app), payload: { month: '2026-08' } });
    expect(response.statusCode).toBe(401);
    expect(mocks.query).toHaveBeenCalledTimes(1);
  });
});

describe('monthly share validation and ownership', () => {
  it.each(['2026-00', '2026-13', '0000-01', '2026-1', '26-01', '2026-01-01', '', '2026-01\n', '9999-12'])(
    'rejects malformed or future month %j before share SQL', async (month) => {
      const app = await createApp();
      authenticateNext();
      const response = await app.inject({ method: 'POST', url: '/api/shares/monthly', headers: authHeader(app), payload: { month } });
      expect(response.statusCode).toBe(400);
      expect(mocks.query).toHaveBeenCalledTimes(1);
    }
  );

  it('does not accept a different user ID in the creation body', async () => {
    const app = await createApp();
    authenticateNext();
    const response = await app.inject({ method: 'POST', url: '/api/shares/monthly', headers: authHeader(app), payload: { month: '2026-08', userId: routeId } });
    expect(response.statusCode).toBe(400);
    expect(mocks.query).toHaveBeenCalledTimes(1);
  });

  it.each(['short', 'a'.repeat(42), 'a'.repeat(44), `${'a'.repeat(42)}!`, `${'a'.repeat(42)}%0A`])(
    'rejects malformed public tokens before SQL: %s', async (token) => {
      const app = await createApp();
      const response = await app.inject(`/api/shares/monthly/${token}`);
      expect(response.statusCode).toBe(400);
      expect(mocks.query).not.toHaveBeenCalled();
    }
  );

  it('creates a strong owner-scoped token and returns the existing token on retry', async () => {
    const app = await createApp();
    authenticateNext();
    mocks.query.mockResolvedValueOnce(result([{ token: shareToken }]));
    const response = await app.inject({ method: 'POST', url: '/api/shares/monthly', headers: authHeader(app), payload: { month: '2026-08' } });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ token: shareToken, month: '2026-08' });
    const args = mocks.query.mock.calls[1]![1];
    expect(args).toEqual([expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), ownerId, '2026-08-01']);
    expect(Buffer.from(args[0], 'base64url')).toHaveLength(32);
    expect(mocks.query.mock.calls[1]![0]).toContain('ON CONFLICT(user_id,month)');
  });

  it.each([null, shareToken])('restores only the current owner’s active token: %s', async (token) => {
    const app = await createApp();
    authenticateNext();
    mocks.query.mockResolvedValueOnce(result(token ? [{ token }] : []));
    const response = await app.inject({ url: '/api/shares/monthly?month=2026-08', headers: authHeader(app) });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ token, month: '2026-08' });
    expect(mocks.query.mock.calls[1]![1]).toEqual([ownerId, '2026-08-01']);
    expect(mocks.query.mock.calls[1]![0]).toContain('revoked_at IS NULL');
  });

  it('refuses to revoke another owner’s share', async () => {
    const app = await createApp();
    authenticateNext();
    mocks.query.mockResolvedValueOnce(result([{ exists: true, revoked: false }]));
    const response = await app.inject({ method: 'DELETE', url: `/api/shares/monthly/${shareToken}`, headers: authHeader(app) });
    expect(response.statusCode).toBe(404);
    expect(mocks.query.mock.calls[1]![1]).toEqual([shareToken, ownerId]);
  });

  it.each([{ exists: true, revoked: true }, { exists: false, revoked: false }])('revokes idempotently, including rotated-away tokens: %j', async (row) => {
    const app = await createApp();
    authenticateNext();
    mocks.query.mockResolvedValueOnce(result([row]));
    const response = await app.inject({ method: 'DELETE', url: `/api/shares/monthly/${shareToken}`, headers: authHeader(app) });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ revoked: true });
  });
});

describe('monthly public response and limits', () => {
  it('returns an empty live month without internal user IDs or locations', async () => {
    const app = await createApp();
    const summary = { climbing_days: 0, sends: 0, gyms: 0, max_grade: 0, flashes: 0, videos: 0 };
    mocks.query.mockResolvedValue(result([{
      month: '2026-08', nickname: '岩友', avatar_url: null,
      summary, days: [], byGrade: [], user_id: ownerId, caption: '私密正文', gym_name: '私密地点'
    }]));
    const response = await app.inject(`/api/shares/monthly/${shareToken}`);
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ kind: 'monthly', month: '2026-08', author: { nickname: '岩友', avatar_url: null }, summary, days: [], byGrade: [] });
    expect(response.body).not.toContain(ownerId);
    expect(response.body).not.toContain('私密');
    expect(response.headers['cache-control']).toBe('private, no-store, max-age=0');
    expect(response.headers['referrer-policy']).toBe('no-referrer');
    expect(response.headers['x-robots-tag']).toBe('noindex, nofollow');
    expect(mocks.query).toHaveBeenCalledTimes(1);
  });

  it('returns uncacheable 404 for revoked and missing shares', async () => {
    const app = await createApp();
    mocks.query.mockResolvedValue(result());
    const response = await app.inject(`/api/shares/monthly/${shareToken}`);
    expect(response.statusCode).toBe(404);
    expect(response.headers['cache-control']).toContain('no-store');
  });

  it('rate limits creation and keeps errors uncacheable', async () => {
    const app = await createApp();
    mocks.query.mockImplementation(async (sql: string) => sql.startsWith('SELECT id,role')
      ? result([{ id: ownerId, role: 'user' }]) : result([{ token: shareToken }]));
    const headers = authHeader(app);
    for (let index = 0; index < 10; index += 1) {
      const response = await app.inject({ method: 'POST', url: '/api/shares/monthly', headers, payload: { month: '2026-08' } });
      expect(response.statusCode).toBe(200);
    }
    const response = await app.inject({ method: 'POST', url: '/api/shares/monthly', headers, payload: { month: '2026-08' } });
    expect(response.statusCode).toBe(429);
    expect(response.headers['cache-control']).toContain('no-store');
    expect(mocks.query).toHaveBeenCalledTimes(20);
  });
});
