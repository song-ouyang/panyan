import fp from 'fastify-plugin';
import jwt from '@fastify/jwt';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { config } from './config.js';

export const authPlugin = fp(async (app: FastifyInstance) => {
  await app.register(jwt, { secret: config.JWT_SECRET });
  app.decorate('authenticate', async (request: FastifyRequest) => {
    await request.jwtVerify();
  });
});

declare module 'fastify' {
  interface FastifyInstance {
    authenticate(request: FastifyRequest): Promise<void>;
  }
}
