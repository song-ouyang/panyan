import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query, transaction } from '../db.js';
import { invalidateSendFacts, lockGrowth, readGrowth, recomputeGrowth, recordClimbingFact, requestHash, retryResponse, saveResponse } from '../services/growth.js';
import { commentBody, idParams, pagination, sendBody } from '../schemas.js';

const feedCursorPayload = z.object({
  version: z.literal(1),
  sentAt: z.string().datetime(),
  id: z.string().uuid()
});

type FeedCursor = { sentAt: string; id: string | null };

const feedCursor = z.string().transform((value, context): FeedCursor => {
  const legacyTimestamp = z.string().datetime().safeParse(value);
  if (legacyTimestamp.success) {
    return { sentAt: legacyTimestamp.data, id: null };
  }

  try {
    const decoded = JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as unknown;
    const parsed = feedCursorPayload.safeParse(decoded);
    if (parsed.success) {
      return { sentAt: parsed.data.sentAt, id: parsed.data.id };
    }
  } catch {
    // The validation issue below intentionally hides decoder details.
  }

  context.addIssue({
    code: z.ZodIssueCode.custom,
    message: '分页位置已失效，请刷新后重试'
  });
  return z.NEVER;
});

const feedQuery = pagination.omit({ cursor: true }).extend({
  cursor: feedCursor.optional(),
  scope: z.enum(['square', 'friends']).default('square')
});

function encodeFeedCursor(row: { id: string; sent_at: string | Date }): string {
  return Buffer.from(JSON.stringify({
    version: 1,
    sentAt: new Date(row.sent_at).toISOString(),
    id: row.id
  }), 'utf8').toString('base64url');
}

export const sendRoutes: FastifyPluginAsync = async (app) => {
  const assertVisibleSend = async (sendId: string, viewerId: string) => {
    const visible = await query(
      `SELECT s.id
       FROM sends s
       WHERE s.id=$1 AND NOT EXISTS (
         SELECT 1 FROM friendships blocked
         WHERE blocked.status='blocked' AND (
           (blocked.requester_id=$2 AND blocked.addressee_id=s.user_id) OR
           (blocked.addressee_id=$2 AND blocked.requester_id=s.user_id)
         )
       ) AND (
         s.user_id=$2 OR (
           s.moderation_status='approved' AND (
             s.visibility='public' OR (
               s.visibility='friends' AND EXISTS (
                 SELECT 1 FROM friendships f
                 WHERE f.status='accepted' AND (
                   (f.requester_id=$2 AND f.addressee_id=s.user_id) OR
                   (f.addressee_id=$2 AND f.requester_id=s.user_id)
                 )
               )
             )
           )
         )
       )`,
      [sendId, viewerId]
    );
    if (!visible.rowCount) throw app.httpErrors.notFound('动态不存在');
  };

  app.post('/moments', { preHandler: app.authenticate }, async (request) => {
    const body = z.object({ caption: z.string().trim().max(300).default(''), imageUrls: z.array(z.string().url()).max(9).default([]), visibility: z.enum(['public', 'friends', 'private']).default('public') }).parse(request.body);
    if (!body.caption && !body.imageUrls.length) throw app.httpErrors.badRequest('请填写内容或选择图片');
    const result = await query(
      `INSERT INTO sends(user_id,route_id,attempts,caption,image_urls,visibility,moderation_status)
       VALUES($1,NULL,1,$2,$3,$4,$5) RETURNING *`,
      [request.user.sub, body.caption || null, body.imageUrls, body.visibility, 'approved']
    );
    const row = result.rows[0]!;
    return { ...row, moderationStatus: row.moderation_status };
  });

  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const body = sendBody.parse(request.body);
    const userId = request.user.sub;
    const hash = requestHash({ kind: 'send', ...body, videoUrl: body.videoUrl ?? null, caption: body.caption ?? null });
    return transaction(async (client) => {
      await lockGrowth(client, userId);
      const retry = await retryResponse(client, userId, body.clientRequestId, 'send', hash);
      if (retry) return retry;
      const route = await client.query(`SELECT grade,substring(grade from 2)::int grade_number FROM routes WHERE id=$1`, [body.routeId]);
      if (!route.rowCount) throw app.httpErrors.notFound('线路不存在');
      const previous = await client.query(
        `SELECT coalesce(max(substring(r.grade from 2)::int),-1)::int max_grade
         FROM sends s JOIN routes r ON r.id=s.route_id
         WHERE s.user_id=$1 AND s.moderation_status='approved'`, [userId]
      );
      const values = [userId, body.routeId, body.attempts, body.videoUrl ?? null, body.caption ?? null, body.visibility];
      const result = body.operation === 'edit'
        ? await client.query(
          `UPDATE sends SET attempts=$3,video_url=$4,caption=$5,visibility=$6
           WHERE user_id=$1 AND route_id=$2 RETURNING *`, values)
        : await client.query(
          `INSERT INTO sends(user_id,route_id,attempts,video_url,caption,visibility,moderation_status)
           VALUES($1,$2,$3,$4,$5,$6,'approved')
           ON CONFLICT(user_id,route_id) DO UPDATE SET attempts=EXCLUDED.attempts,video_url=EXCLUDED.video_url,
           caption=EXCLUDED.caption,visibility=EXCLUDED.visibility,moderation_status=EXCLUDED.moderation_status,sent_at=now()
           RETURNING *`, values);
      if (!result.rowCount) throw app.httpErrors.notFound('完攀记录不存在');
      const send = result.rows[0]!;
      if (body.operation === 'record') await recordClimbingFact(client, {
        userId, sendId: send.id, routeId: body.routeId, sourceKind: 'checkin',
        clientRequestId: body.clientRequestId, hash
      });
      const growth = body.operation === 'record' ? await recomputeGrowth(client, userId) : await readGrowth(client, userId);
      const gradeNumber = route.rows[0]!.grade_number as number;
      const response = {
        send, sendId: send.id, moderationStatus: send.moderation_status,
        milestone: body.operation === 'record' && gradeNumber > (previous.rows[0]?.max_grade ?? -1)
          ? { type: 'first_grade', grade: route.rows[0]!.grade } : null,
        pointsEarned: 10 + gradeNumber * 5 + (body.attempts === 1 ? 5 : 0), pendingPoints: 0, growth
      };
      await saveResponse(client, userId, body.clientRequestId, 'send', hash, response);
      return response;
    });
  });

  app.get('/feed', { preHandler: app.authenticateOptional }, async (request) => {
    const { cursor, limit, scope } = feedQuery.parse(request.query);
    const viewerId = request.user?.sub ?? null;
    if (scope === 'friends' && !viewerId) {
      throw app.httpErrors.unauthorized('登录后才能查看朋友圈');
    }
    const result = await query<{ id: string; sent_at: string | Date } & Record<string, unknown>>(
      `WITH visible_sends AS (
         SELECT s.*
         FROM sends s
         WHERE s.moderation_status='approved'
           AND (
             $2::timestamptz IS NULL OR
             ($3::uuid IS NULL AND s.sent_at<$2::timestamptz) OR
             ($3::uuid IS NOT NULL AND (s.sent_at,s.id)<($2::timestamptz,$3::uuid))
           )
           AND ($1::uuid IS NULL OR NOT EXISTS (
             SELECT 1 FROM friendships blocked
             WHERE blocked.status='blocked' AND (
               (blocked.requester_id=$1 AND blocked.addressee_id=s.user_id) OR
               (blocked.addressee_id=$1 AND blocked.requester_id=s.user_id)
             )
           ))
           AND (
             ($5::text='square' AND s.visibility='public') OR
             ($5::text='friends' AND s.visibility IN ('public','friends') AND (
               s.user_id=$1 OR EXISTS (
                 SELECT 1 FROM friendships f
                 WHERE f.status='accepted' AND (
                   (f.requester_id=$1 AND f.addressee_id=s.user_id) OR
                   (f.addressee_id=$1 AND f.requester_id=s.user_id)
                 )
               )
             ))
           )
         ORDER BY s.sent_at DESC,s.id DESC
         LIMIT $4
       )
       SELECT s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.visibility,s.sent_at,u.id user_id,u.nickname,u.avatar_url,
              r.id route_id,r.name route_name,r.grade,r.color,g.id gym_id,g.name gym_name,
              (SELECT count(*)::int FROM post_likes l WHERE l.send_id=s.id) like_count,
              (SELECT count(*)::int FROM comments c
               WHERE c.send_id=s.id AND (
                 c.moderation_status='approved' OR
                 (c.moderation_status='pending' AND c.user_id=$1::uuid)
               )
                 AND ($1::uuid IS NULL OR NOT EXISTS (
                   SELECT 1 FROM friendships blocked_commenter
                   WHERE blocked_commenter.status='blocked' AND (
                     (blocked_commenter.requester_id=$1 AND blocked_commenter.addressee_id=c.user_id) OR
                     (blocked_commenter.addressee_id=$1 AND blocked_commenter.requester_id=c.user_id)
                   )
                 ))) comment_count,
              EXISTS(SELECT 1 FROM post_likes own_like WHERE own_like.send_id=s.id AND own_like.user_id=$1::uuid) liked,
              EXISTS(SELECT 1 FROM post_favorites own_favorite WHERE own_favorite.send_id=s.id AND own_favorite.user_id=$1::uuid) favorited
       FROM visible_sends s
       JOIN users u ON u.id=s.user_id
       LEFT JOIN routes r ON r.id=s.route_id
       LEFT JOIN gyms g ON g.id=r.gym_id
       ORDER BY s.sent_at DESC,s.id DESC`,
      [viewerId, cursor?.sentAt ?? null, cursor?.id ?? null, limit, scope]
    );
    const last = result.rows.at(-1);
    return {
      items: result.rows,
      nextCursor: last && result.rows.length === limit ? encodeFeedCursor(last) : null
    };
  });

  app.get('/:id', { preHandler: app.authenticateOptional }, async (request) => {
    const { id } = idParams.parse(request.params);
    const viewerId = request.user?.sub ?? null;
    const result = await query(
      `SELECT s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.visibility,s.moderation_status,s.sent_at,
              u.id user_id,u.nickname,u.avatar_url,r.id route_id,r.name route_name,r.grade,r.color,
              g.id gym_id,g.name gym_name,count(DISTINCT l.user_id)::int like_count,
              (SELECT count(*)::int FROM comments c
               WHERE c.send_id=s.id AND (
                 c.moderation_status='approved' OR
                 (c.moderation_status='pending' AND c.user_id=$2::uuid)
               )
                 AND ($2::uuid IS NULL OR NOT EXISTS (
                   SELECT 1 FROM friendships blocked_commenter
                   WHERE blocked_commenter.status='blocked' AND (
                     (blocked_commenter.requester_id=$2 AND blocked_commenter.addressee_id=c.user_id) OR
                     (blocked_commenter.addressee_id=$2 AND blocked_commenter.requester_id=c.user_id)
                   )
                 ))) comment_count,
              coalesce(bool_or(l.user_id=$2::uuid),false) liked,
              EXISTS(SELECT 1 FROM post_favorites own_favorite WHERE own_favorite.send_id=s.id AND own_favorite.user_id=$2::uuid) favorited
       FROM sends s JOIN users u ON u.id=s.user_id LEFT JOIN routes r ON r.id=s.route_id LEFT JOIN gyms g ON g.id=r.gym_id
       LEFT JOIN post_likes l ON l.send_id=s.id
       WHERE s.id=$1 AND ($2::uuid IS NULL OR NOT EXISTS (
         SELECT 1 FROM friendships blocked
         WHERE blocked.status='blocked' AND (
           (blocked.requester_id=$2 AND blocked.addressee_id=s.user_id) OR
           (blocked.addressee_id=$2 AND blocked.requester_id=s.user_id)
         )
       )) AND (
         ($2::uuid IS NULL AND s.moderation_status='approved' AND s.visibility='public') OR
         ($2::uuid IS NOT NULL AND (s.user_id=$2 OR (
           s.moderation_status='approved' AND (
             s.visibility='public' OR (
               s.visibility='friends' AND EXISTS (
                 SELECT 1 FROM friendships f
                 WHERE f.status='accepted' AND (
                   (f.requester_id=$2 AND f.addressee_id=s.user_id) OR
                   (f.addressee_id=$2 AND f.requester_id=s.user_id)
                 )
               )
             )
           )
         )))
       )
       GROUP BY s.id,u.id,r.id,g.id`, [id, viewerId]
    );
    if (!result.rowCount) throw app.httpErrors.notFound('动态不存在');
    const comments = await query(
      `SELECT c.id,c.content,c.created_at,c.moderation_status,u.id user_id,u.nickname,u.avatar_url
       FROM comments c JOIN users u ON u.id=c.user_id
       WHERE c.send_id=$1 AND (
         c.moderation_status='approved' OR
         (c.moderation_status='pending' AND c.user_id=$2::uuid)
       )
       AND ($2::uuid IS NULL OR NOT EXISTS (
         SELECT 1 FROM friendships blocked
         WHERE blocked.status='blocked' AND (
           (blocked.requester_id=$2 AND blocked.addressee_id=c.user_id) OR
           (blocked.addressee_id=$2 AND blocked.requester_id=c.user_id)
         )
       ))
       ORDER BY c.created_at`, [id, viewerId]
    );
    return { ...result.rows[0], comments: comments.rows };
  });

  app.post('/:id/like', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await assertVisibleSend(id, request.user.sub);
    await query('INSERT INTO post_likes(send_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [id, request.user.sub]);
    return { liked: true };
  });
  app.delete('/:id/like', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await query('DELETE FROM post_likes WHERE send_id=$1 AND user_id=$2', [id, request.user.sub]);
    return { liked: false };
  });
  app.post('/:id/favorite', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await assertVisibleSend(id, request.user.sub);
    await query('INSERT INTO post_favorites(send_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [id, request.user.sub]);
    return { favorited: true };
  });
  app.delete('/:id/favorite', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    // Unsave remains available after friendship or visibility changes.
    await query('DELETE FROM post_favorites WHERE send_id=$1 AND user_id=$2', [id, request.user.sub]);
    return { favorited: false };
  });
  app.post('/:id/comments', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const { content } = commentBody.parse(request.body);
    await assertVisibleSend(id, request.user.sub);
    const result = await query(
      `WITH inserted AS (
         INSERT INTO comments(send_id,user_id,content,moderation_status)
         VALUES($1,$2,$3,$4) RETURNING *
       )
       SELECT c.*,u.nickname,u.avatar_url
       FROM inserted c JOIN users u ON u.id=c.user_id`,
      [id, request.user.sub, content, 'approved']
    );
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
    return transaction(async (client) => {
      await lockGrowth(client, request.user.sub);
      const owned = await client.query('SELECT id FROM sends WHERE id=$1 AND user_id=$2 FOR UPDATE', [id, request.user.sub]);
      if (!owned.rowCount) throw app.httpErrors.notFound('动态不存在或无权删除');
      await invalidateSendFacts(client, request.user.sub, id, 'owner_deleted');
      await client.query('DELETE FROM sends WHERE id=$1 AND user_id=$2', [id, request.user.sub]);
      return { deleted: true };
    });
  });
};
