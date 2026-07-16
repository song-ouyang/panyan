import type { FastifyPluginAsync } from 'fastify';
import { query } from '../db.js';
import { idParams } from '../schemas.js';

export const notificationRoutes: FastifyPluginAsync = async (app) => {
  app.get('/', { preHandler: app.authenticate }, async (request) => {
    const result = await query(`SELECT * FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100`, [request.user.sub]);
    return { items: result.rows, unread: result.rows.filter(row => !row.read_at).length };
  });
  app.post('/read-all', { preHandler: app.authenticate }, async (request) => {
    await query('UPDATE notifications SET read_at=now() WHERE user_id=$1 AND read_at IS NULL', [request.user.sub]);
    return { read: true };
  });
  app.post('/:id/read', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await query('UPDATE notifications SET read_at=now() WHERE id=$1 AND user_id=$2', [id,request.user.sub]);
    return { read: true };
  });
};
