import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  config: { JWT_SECRET: 'weekly-routes-contract-test-secret-32-characters' }
}));
vi.mock('../src/db.js', () => ({ query: mocks.query }));
vi.mock('../src/config.js', () => ({ config: mocks.config }));

import { authPlugin } from '../src/auth.js';
import { routeRoutes } from '../src/routes/routes.js';

const now = '2026-09-07T04:00:00.000Z';
const empty = { items: [], weekStart: '2026-09-06T16:00:00.000Z', weekEnd: now };
const apps: FastifyInstance[] = [];
const result = (rows: unknown[]) => ({ rows, rowCount: rows.length });

async function createApp() {
  const app = Fastify();
  apps.push(app);
  await app.register(sensible);
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
    return reply.send(error);
  });
  await app.register(authPlugin);
  await app.register(routeRoutes, { prefix: '/api/routes' });
  return app;
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(now));
  mocks.query.mockReset();
  mocks.query.mockResolvedValue(result([empty]));
});

afterEach(async () => {
  await Promise.all(apps.splice(0).map((app) => app.close()));
  vi.useRealTimers();
});

describe('weekly routes public API contract', () => {
  it('allows guests and returns a dated empty list with the default limit', async () => {
    const app = await createApp();
    const response = await app.inject('/api/routes/weekly');

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(empty);
    expect(mocks.query).toHaveBeenCalledOnce();
    expect(mocks.query.mock.calls[0]![1]).toEqual([now, null, 10]);
  });

  it.each(['', '   '])('treats empty city %j as nationwide', async (city) => {
    const app = await createApp();
    const response = await app.inject(`/api/routes/weekly?city=${encodeURIComponent(city)}`);

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([now, null, 10]);
  });

  it.each([1, 20])('accepts a trimmed city and the limit boundary %i', async (limit) => {
    const app = await createApp();
    const response = await app.inject(`/api/routes/weekly?city=${encodeURIComponent(' 上海 ')}&limit=${limit}`);

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([now, '上海', limit]);
  });

  it('returns route and gym fields without depending on video or send counts', async () => {
    const item = {
      id: '00000000-0000-4000-8000-000000000001',
      gym_id: '00000000-0000-4000-8000-000000000002',
      name: '蓝色新线', grade: 'V4', color: '蓝色', points: [],
      cover_url: null, created_at: '2026-09-07T02:00:00.000Z',
      gym_name: '测试岩馆', gym_address: '上海测试地址', gym_city: '上海'
    };
    mocks.query.mockResolvedValue(result([{ ...empty, items: [item] }]));
    const app = await createApp();
    const response = await app.inject('/api/routes/weekly');

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ...empty, items: [item] });
  });

  it.each([
    'limit=0', 'limit=21', 'limit=-1', 'limit=1.5', 'limit=abc', 'limit=',
    'limit=1&limit=2', `city=${encodeURIComponent('城'.repeat(41))}`, 'city=上海&city=北京'
  ])('rejects invalid input before querying the database: %s', async (query) => {
    const app = await createApp();
    const response = await app.inject(`/api/routes/weekly?${query}`);

    expect(response.statusCode).toBe(400);
    expect(response.json()).toMatchObject({ code: 'VALIDATION_ERROR' });
    expect(mocks.query).not.toHaveBeenCalled();
  });

  it('applies the 40-character city limit after trimming', async () => {
    const city = '城'.repeat(40);
    const app = await createApp();
    const response = await app.inject(`/api/routes/weekly?city=${encodeURIComponent(` ${city} `)}`);

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([now, city, 10]);
  });

  it.each(['Bearer invalid-token', '', '   ', 'Basic invalid-token'])(
    'rejects a supplied invalid Authorization header %j', async (authorization) => {
      const app = await createApp();
      const response = await app.inject({ url: '/api/routes/weekly', headers: { authorization } });

      expect(response.statusCode).toBe(401);
      expect(mocks.query).not.toHaveBeenCalled();
    }
  );

  it('rejects expired JWTs rather than downgrading them to guest access', async () => {
    const app = await createApp();
    const token = app.jwt.sign({ sub: '00000000-0000-4000-8000-000000000003', role: 'user', exp: 1 });
    const response = await app.inject({ url: '/api/routes/weekly', headers: { authorization: `Bearer ${token}` } });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
  });

  it('accepts an existing signed-in user through the real auth plugin', async () => {
    const user = { id: '00000000-0000-4000-8000-000000000003', role: 'user' as const };
    mocks.query.mockResolvedValueOnce(result([user])).mockResolvedValueOnce(result([empty]));
    const app = await createApp();
    const token = app.jwt.sign({ sub: user.id, role: user.role });
    const response = await app.inject({ url: '/api/routes/weekly', headers: { authorization: `Bearer ${token}` } });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(empty);
    expect(mocks.query.mock.calls[0]![1]).toEqual([user.id]);
    expect(mocks.query.mock.calls[1]![1]).toEqual([now, null, 10]);
  });
});
