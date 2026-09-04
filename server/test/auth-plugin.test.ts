import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  config: {
    JWT_SECRET: 'auth-plugin-test-secret-at-least-32-characters'
  }
}));

vi.mock('../src/db.js', () => ({ query: mocks.query }));
vi.mock('../src/config.js', () => ({ config: mocks.config }));

import { authPlugin } from '../src/auth.js';

const userId = '00000000-0000-4000-8000-000000000401';

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  await app.register(authPlugin);
  app.get('/required', { preHandler: app.authenticate }, async (request) => ({
    user: request.user
  }));
  app.get('/optional', { preHandler: app.authenticateOptional }, async (request) => ({
    user: request.user ?? null
  }));
  return app;
}

beforeEach(() => mocks.query.mockReset());

describe('current-session authentication', () => {
  it('uses the current database role instead of a stale JWT role', async () => {
    mocks.query.mockResolvedValueOnce({
      rows: [{ id: userId, role: 'user' }],
      rowCount: 1
    });
    const app = await createApp();
    const staleAdminToken = app.jwt.sign({ sub: userId, role: 'admin' });

    const response = await app.inject({
      method: 'GET',
      url: '/required',
      headers: { authorization: `Bearer ${staleAdminToken}` }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ user: { sub: userId, role: 'user' } });
    expect(mocks.query).toHaveBeenCalledWith(
      expect.stringContaining('SELECT id,role FROM users'),
      [userId]
    );
    await app.close();
  });

  it('rejects a still-signed token after its account has been deleted', async () => {
    mocks.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const app = await createApp();
    const oldToken = app.jwt.sign({ sub: userId, role: 'user' });

    const response = await app.inject({
      method: 'GET',
      url: '/required',
      headers: { authorization: `Bearer ${oldToken}` }
    });

    expect(response.statusCode).toBe(401);
    expect(response.json().message).toBe('登录已失效，请重新登录');
    await app.close();
  });

  it('keeps a truly anonymous optional request database-free', async () => {
    const app = await createApp();

    const response = await app.inject({ method: 'GET', url: '/optional' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ user: null });
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });
});
