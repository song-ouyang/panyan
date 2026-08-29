import type { FastifyPluginAsync } from 'fastify';
import { query } from '../db.js';
import { idParams } from '../schemas.js';

export const routeRoutes: FastifyPluginAsync = async (app) => {
  app.get('/:id', async (request) => {
    const { id } = idParams.parse(request.params);
    let viewerId: string | null = null;
    if (request.headers.authorization) {
      await app.authenticate(request);
      viewerId = request.user.sub;
    }
    const result = await query(
      `SELECT r.*,g.name gym_name,g.address gym_address,rs.name route_set_name,
       count(DISTINCT s.id)::int send_count
       FROM routes r JOIN gyms g ON g.id=r.gym_id LEFT JOIN route_sets rs ON rs.id=r.route_set_id
       LEFT JOIN sends s ON s.route_id=r.id
         AND s.moderation_status='approved' AND s.visibility='public' AND s.video_url IS NOT NULL
       WHERE r.id=$1 AND r.published=true
       GROUP BY r.id,g.id,rs.id`, [id]
    );
    if (!result.rowCount) throw app.httpErrors.notFound('线路不存在');
    const featured = await query(
      `SELECT s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.visibility,s.moderation_status,s.sent_at,
              u.id user_id,u.nickname,u.avatar_url,r.id route_id,r.name route_name,r.grade,r.color,
              g.id gym_id,g.name gym_name,count(DISTINCT l.user_id)::int like_count,
              (SELECT count(*)::int FROM comments c WHERE c.send_id=s.id AND c.moderation_status='approved') comment_count,
              coalesce(bool_or(l.user_id=$2::uuid),false) liked
       FROM sends s
       JOIN users u ON u.id=s.user_id
       JOIN routes r ON r.id=s.route_id
       JOIN gyms g ON g.id=r.gym_id
       LEFT JOIN post_likes l ON l.send_id=s.id
       WHERE s.route_id=$1 AND s.video_url IS NOT NULL AND (
         s.user_id=$2::uuid OR (
           s.moderation_status='approved' AND (
             s.visibility='public' OR (
               s.visibility='friends' AND $2::uuid IS NOT NULL AND EXISTS (
                 SELECT 1 FROM friendships f
                 WHERE f.status='accepted' AND (
                   (f.requester_id=$2::uuid AND f.addressee_id=s.user_id) OR
                   (f.addressee_id=$2::uuid AND f.requester_id=s.user_id)
                 )
               )
             )
           )
         )
       )
       GROUP BY s.id,u.id,r.id,g.id
       ORDER BY (s.user_id=$2::uuid) DESC NULLS LAST,
                count(DISTINCT l.user_id) DESC,s.sent_at DESC,s.id DESC
       LIMIT 1`,
      [id, viewerId]
    );
    return { ...result.rows[0], featuredSend: featured.rows[0] ?? null };
  });

  app.get('/:id/leaderboard', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(
      `SELECT row_number() OVER (ORDER BY count(DISTINCT l.user_id) DESC,s.sent_at ASC)::int rank,
       s.id,s.video_url,s.caption,s.attempts,s.sent_at,u.id user_id,u.nickname,u.avatar_url,
       count(DISTINCT l.user_id)::int like_count,coalesce(bool_or(l.user_id=$2),false) liked
       FROM sends s JOIN users u ON u.id=s.user_id LEFT JOIN post_likes l ON l.send_id=s.id
       WHERE s.route_id=$1 AND s.visibility='public' AND s.moderation_status='approved' AND s.video_url IS NOT NULL
       GROUP BY s.id,u.id ORDER BY like_count DESC,s.sent_at ASC`, [id,request.user.sub]
    );
    return { items: result.rows, completionCount: result.rows.length };
  });
};
