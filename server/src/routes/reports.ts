import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query } from '../db.js';

const body = z.object({ targetType: z.enum(['send','comment','user','meetup','route']), targetId: z.string().uuid(), reason: z.enum(['spam','abuse','unsafe','privacy','false_info','other']), detail: z.string().max(300).optional() });

export const reportRoutes: FastifyPluginAsync = async (app) => {
  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const b = body.parse(request.body);
    await query(`INSERT INTO reports(reporter_id,target_type,target_id,reason,detail) VALUES($1,$2,$3,$4,$5) ON CONFLICT(reporter_id,target_type,target_id) DO UPDATE SET reason=EXCLUDED.reason,detail=EXCLUDED.detail,status='pending',created_at=now()`, [request.user.sub,b.targetType,b.targetId,b.reason,b.detail??null]);
    return { reported: true };
  });
};
