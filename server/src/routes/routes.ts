import type { FastifyPluginAsync } from 'fastify';
import { query } from '../db.js';
import { idParams } from '../schemas.js';

export const routeRoutes: FastifyPluginAsync = async (app) => {
  app.get('/:id', async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(
      `SELECT r.*,g.name gym_name,g.address gym_address,rs.name route_set_name,
       count(DISTINCT s.id)::int send_count
       FROM routes r JOIN gyms g ON g.id=r.gym_id LEFT JOIN route_sets rs ON rs.id=r.route_set_id
       LEFT JOIN sends s ON s.route_id=r.id WHERE r.id=$1 AND r.published=true
       GROUP BY r.id,g.id,rs.id`, [id]
    );
    if (!result.rowCount) throw app.httpErrors.notFound('线路不存在');
    return result.rows[0];
  });

  app.get('/:id/leaderboard', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(
      `SELECT row_number() OVER (ORDER BY count(DISTINCT l.user_id) DESC,s.sent_at ASC)::int rank,
       s.id,s.video_url,s.caption,s.attempts,s.sent_at,u.id user_id,u.nickname,u.avatar_url,
       count(DISTINCT l.user_id)::int like_count,coalesce(bool_or(l.user_id=$2),false) liked
       FROM sends s JOIN users u ON u.id=s.user_id LEFT JOIN post_likes l ON l.send_id=s.id
       WHERE s.route_id=$1 AND s.visibility='public' AND s.moderation_status='approved'
       GROUP BY s.id,u.id ORDER BY like_count DESC,s.sent_at ASC`, [id,request.user.sub]
    );
    return { items: result.rows, completionCount: result.rows.length };
  });
};
