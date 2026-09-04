import fp from 'fastify-plugin';
import jwt from '@fastify/jwt';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { config } from './config.js';
import { query } from './db.js';

type CurrentUser = {
  id: string;
  role: 'user' | 'gym_admin' | 'admin';
};

export const authPlugin = fp(async (app: FastifyInstance) => {
  await app.register(jwt, { secret: config.JWT_SECRET });

  const verifyCurrentSession = async (request: FastifyRequest) => {
    await request.jwtVerify();

    // A signed token proves who originally logged in, but account deletion and
    // role changes must take effect immediately instead of waiting for the
    // 30-day JWT expiry. The primary-key lookup is intentionally performed for
    // every authenticated request so authorization never relies on stale role
    // claims.
    const current = await query<CurrentUser>(
      'SELECT id,role FROM users WHERE id=$1 LIMIT 1',
      [request.user.sub]
    );
    const user = current.rows[0];
    if (!user) throw app.httpErrors.unauthorized('登录已失效，请重新登录');

    request.user = { sub: user.id, role: user.role };
  };

  app.decorate('authenticate', verifyCurrentSession);
  app.decorate('authenticateOptional', async (request: FastifyRequest) => {
    if (request.headers.authorization === undefined) return;
    await verifyCurrentSession(request);
  });
});

declare module 'fastify' {
  interface FastifyInstance {
    authenticate(request: FastifyRequest): Promise<void>;
    authenticateOptional(request: FastifyRequest): Promise<void>;
  }
}
