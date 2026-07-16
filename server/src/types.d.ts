import '@fastify/jwt';

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: { sub: string; role: 'user' | 'gym_admin' | 'admin' };
    user: { sub: string; role: 'user' | 'gym_admin' | 'admin' };
  }
}

