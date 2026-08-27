import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query } from '../db.js';
import { commentBody, idParams, pagination, sendBody } from '../schemas.js';
import { initialModerationStatus } from '../moderation.js';

export const sendRoutes: FastifyPluginAsync = async (app) => {
  app.post('/moments', { preHandler: app.authenticate }, async (request) => {
    const body = z.object({ caption: z.string().trim().max(300).default(''), imageUrls: z.array(z.string().url()).max(9).default([]), visibility: z.enum(['public', 'friends', 'private']).default('public') }).parse(request.body);
    if (!body.caption && !body.imageUrls.length) throw app.httpErrors.badRequest('请填写内容或选择图片');
    const result = await query(
      `INSERT INTO sends(user_id,route_id,attempts,caption,image_urls,visibility,moderation_status)
       VALUES($1,NULL,1,$2,$3,$4,$5) RETURNING *`,
      [request.user.sub, body.caption || null, body.imageUrls, body.visibility, initialModerationStatus()]
    );
    const row = result.rows[0]!;
    return { ...row, moderationStatus: row.moderation_status };
  });

  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const body = sendBody.parse(request.body);
    const route = await query(`SELECT grade,substring(grade from 2)::int grade_number FROM routes WHERE id=$1`, [body.routeId]);
    if (!route.rowCount) throw app.httpErrors.notFound('线路不存在');
    const moderationStatus = initialModerationStatus();
    const previous = await query(
      `SELECT coalesce(max(substring(r.grade from 2)::int),-1)::int max_grade
       FROM sends s JOIN routes r ON r.id=s.route_id
       WHERE s.user_id=$1 AND s.moderation_status='approved'`, [request.user.sub]
    );
    const result = await query(
      `INSERT INTO sends(user_id,route_id,attempts,video_url,caption,visibility,moderation_status)
       VALUES($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT(user_id,route_id) DO UPDATE SET attempts=EXCLUDED.attempts,video_url=EXCLUDED.video_url,
       caption=EXCLUDED.caption,visibility=EXCLUDED.visibility,moderation_status=EXCLUDED.moderation_status,sent_at=now()
       RETURNING *`, [request.user.sub, body.routeId, body.attempts, body.videoUrl ?? null, body.caption ?? null, body.visibility, moderationStatus]
    );
    const routeInfo = route.rows[0]!;
    const previousMax = previous.rows[0]?.max_grade ?? -1;
    const gradeNumber = routeInfo.grade_number as number;
    const milestone = gradeNumber > previousMax ? { type: 'first_grade', grade: routeInfo.grade } : null;
    const points = 10 + gradeNumber * 5 + (body.attempts === 1 ? 5 : 0);
    const send = result.rows[0]!;
    return {
      send,
      sendId: send.id,
      moderationStatus,
      milestone,
      pointsEarned: moderationStatus === 'approved' ? points : 0,
      pendingPoints: moderationStatus === 'pending' ? points : 0
    };
  });

  app.get('/feed', { preHandler: app.authenticate }, async (request) => {
    const { cursor, limit } = pagination.parse(request.query);
    const result = await query(
      `SELECT s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.sent_at,u.id user_id,u.nickname,u.avatar_url,
              r.id route_id,r.name route_name,r.grade,r.color,g.id gym_id,g.name gym_name,
              count(DISTINCT l.user_id)::int like_count,count(DISTINCT c.id)::int comment_count,
              coalesce(bool_or(l.user_id=$1),false) liked
       FROM sends s JOIN users u ON u.id=s.user_id LEFT JOIN routes r ON r.id=s.route_id LEFT JOIN gyms g ON g.id=r.gym_id
       LEFT JOIN post_likes l ON l.send_id=s.id LEFT JOIN comments c ON c.send_id=s.id
       WHERE s.visibility='public' AND s.moderation_status='approved' AND ($2::timestamptz IS NULL OR s.sent_at<$2)
       GROUP BY s.id,u.id,r.id,g.id ORDER BY s.sent_at DESC LIMIT $3`, [request.user.sub, cursor ?? null, limit]
    );
    return { items: result.rows, nextCursor: result.rows.at(-1)?.sent_at ?? null };
  });

  app.get('/:id', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(
      `SELECT s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.visibility,s.sent_at,
              u.id user_id,u.nickname,u.avatar_url,r.id route_id,r.name route_name,r.grade,r.color,
              g.id gym_id,g.name gym_name,count(DISTINCT l.user_id)::int like_count,
              coalesce(bool_or(l.user_id=$2),false) liked
       FROM sends s JOIN users u ON u.id=s.user_id LEFT JOIN routes r ON r.id=s.route_id LEFT JOIN gyms g ON g.id=r.gym_id
       LEFT JOIN post_likes l ON l.send_id=s.id WHERE s.id=$1
       GROUP BY s.id,u.id,r.id,g.id`, [id, request.user.sub]
    );
    if (!result.rowCount) throw app.httpErrors.notFound('动态不存在');
    const comments = await query(
      `SELECT c.id,c.content,c.created_at,u.id user_id,u.nickname,u.avatar_url
       FROM comments c JOIN users u ON u.id=c.user_id WHERE c.send_id=$1 AND c.moderation_status='approved' ORDER BY c.created_at`, [id]
    );
    return { ...result.rows[0], comments: comments.rows };
  });

  app.post('/:id/like', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await query('INSERT INTO post_likes(send_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [id, request.user.sub]);
    return { liked: true };
  });
  app.delete('/:id/like', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await query('DELETE FROM post_likes WHERE send_id=$1 AND user_id=$2', [id, request.user.sub]);
    return { liked: false };
  });
  app.post('/:id/comments', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const { content } = commentBody.parse(request.body);
    const result = await query('INSERT INTO comments(send_id,user_id,content,moderation_status) VALUES($1,$2,$3,$4) RETURNING *', [id, request.user.sub, content, initialModerationStatus()]);
    return result.rows[0];
  });
  app.delete('/:sendId/comments/:commentId', { preHandler: app.authenticate }, async (request) => {
    const { sendId, commentId } = z.object({ sendId: z.string().uuid(), commentId: z.string().uuid() }).parse(request.params);
    const result = await query(
      `DELETE FROM comments c USING sends s WHERE c.id=$1 AND c.send_id=$2 AND s.id=c.send_id AND (c.user_id=$3 OR s.user_id=$3) RETURNING c.id`,
      [commentId,sendId,request.user.sub]
    );
    if (!result.rowCount) throw app.httpErrors.notFound('评论不存在或无权删除');
    return { deleted: true };
  });

  app.delete('/:id', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query('DELETE FROM sends WHERE id=$1 AND user_id=$2 RETURNING id', [id, request.user.sub]);
    if (!result.rowCount) throw app.httpErrors.notFound('动态不存在或无权删除');
    return { deleted: true };
  });
};
