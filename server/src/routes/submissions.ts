import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { query, transaction } from '../db.js';
import { idParams } from '../schemas.js';

const body = z.object({
  gymId: z.string().uuid(),
  routeSetId: z.string().uuid().nullable().optional(),
  name: z.string().min(1).max(80),
  grade: z.string().regex(/^V([0-9]|1[0-7])$/),
  color: z.string().min(1).max(24),
  // Accept null for compatibility with older mini-program builds; new clients
  // omit the field when the optional wall zone is empty.
  wallZone: z.string().trim().max(40).nullable().optional(),
  coverUrl: z.string().url(),
  videoUrl: z.string().url().nullable().optional(),
  caption: z.string().trim().max(300).nullable().optional(),
  visibility: z.enum(['public', 'friends', 'private']).default('public'),
  clientRequestId: z.string().uuid().optional(),
  points: z.array(z.object({
    x: z.number().min(0).max(1),
    y: z.number().min(0).max(1),
    type: z.enum(['start','hold','finish'])
  })).min(2).max(80)
}).superRefine((submission, context) => {
  if (!submission.points.some((point) => point.type === 'start')) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: '请至少标记一个起点', path: ['points'] });
  }
  if (!submission.points.some((point) => point.type === 'finish')) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: '请至少标记一个终点', path: ['points'] });
  }
});
const reviewBody = z.object({ action: z.enum(['approve','reject']), note: z.string().max(300).optional() });

export const submissionRoutes: FastifyPluginAsync = async (app) => {
  app.post('/', {
    preHandler: app.authenticate,
    config: { rateLimit: { max: 12, timeWindow: '1 minute' } }
  }, async (request) => {
    const b = body.parse(request.body);
    return transaction(async (client) => {
      if (b.clientRequestId) {
        const existing = await client.query(
          `SELECT rs.*,s.id send_id,s.moderation_status send_moderation_status
           FROM route_submissions rs
           LEFT JOIN sends s ON s.route_id=rs.published_route_id AND s.user_id=rs.submitter_id
           WHERE rs.submitter_id=$1 AND rs.client_request_id=$2`,
          [request.user.sub, b.clientRequestId]
        );
        if (existing.rowCount) return existing.rows[0];
      }

      const gym = await client.query('SELECT id FROM gyms WHERE id=$1 FOR SHARE', [b.gymId]);
      if (!gym.rowCount) throw app.httpErrors.notFound('岩馆不存在');
      if (b.routeSetId) {
        const routeSet = await client.query(
          'SELECT id FROM route_sets WHERE id=$1 AND gym_id=$2 FOR SHARE',
          [b.routeSetId, b.gymId]
        );
        if (!routeSet.rowCount) throw app.httpErrors.badRequest('换线周期不属于所选岩馆');
      }

      const inserted = await client.query(
        `INSERT INTO route_submissions(
           submitter_id,client_request_id,gym_id,route_set_id,name,grade,color,wall_zone,
           cover_url,video_url,caption,visibility,points,status,reviewed_at
         )
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'approved',now())
         ON CONFLICT (submitter_id,client_request_id) DO NOTHING
         RETURNING *`,
        [
          request.user.sub,b.clientRequestId??null,b.gymId,b.routeSetId??null,b.name,b.grade,b.color,
          b.wallZone??null,b.coverUrl,b.videoUrl??null,b.caption||null,b.visibility,JSON.stringify(b.points)
        ]
      );
      if (!inserted.rowCount) {
        const existing = await client.query(
          `SELECT rs.*,s.id send_id,s.moderation_status send_moderation_status
           FROM route_submissions rs
           LEFT JOIN sends s ON s.route_id=rs.published_route_id AND s.user_id=rs.submitter_id
           WHERE rs.submitter_id=$1 AND rs.client_request_id=$2`,
          [request.user.sub, b.clientRequestId]
        );
        if (existing.rowCount) return existing.rows[0];
        throw app.httpErrors.conflict('请求已处理，请刷新查看');
      }

      const route = await client.query<{ id: string }>(
        `INSERT INTO routes(gym_id,route_set_id,name,grade,color,wall_zone,cover_url,points)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
        [b.gymId,b.routeSetId??null,b.name,b.grade,b.color,b.wallZone??null,b.coverUrl,JSON.stringify(b.points)]
      );
      const routeId = route.rows[0]!.id;
      if (b.videoUrl) {
        await client.query<{ id: string }>(
          `INSERT INTO sends(user_id,route_id,attempts,video_url,caption,visibility,moderation_status)
           VALUES($1,$2,1,$3,$4,$5,$6) RETURNING id`,
          [request.user.sub,routeId,b.videoUrl,b.caption||null,b.visibility,'approved']
        );
      }
      await client.query(
        `UPDATE route_submissions
         SET published_route_id=$2
         WHERE id=$1`,
        [inserted.rows[0]!.id,routeId]
      );
      const published = await client.query(
        `SELECT rs.*,s.id send_id,s.moderation_status send_moderation_status
         FROM route_submissions rs
         LEFT JOIN sends s ON s.route_id=rs.published_route_id AND s.user_id=rs.submitter_id
         WHERE rs.id=$1`,
        [inserted.rows[0]!.id]
      );
      return published.rows[0];
    });
  });
  app.get('/mine', { preHandler: app.authenticate }, async (request) => {
    const result = await query(
      `SELECT rs.*,g.name gym_name,s.id send_id,s.moderation_status send_moderation_status
       FROM route_submissions rs
       JOIN gyms g ON g.id=rs.gym_id
       LEFT JOIN sends s ON s.route_id=rs.published_route_id AND s.user_id=rs.submitter_id
       WHERE rs.submitter_id=$1
       ORDER BY rs.created_at DESC`,
      [request.user.sub]
    );
    return { items: result.rows };
  });
  const admin = async (request: FastifyRequest) => {
    await app.authenticate(request);
    if (!['gym_admin','admin'].includes(request.user.role)) {
      throw app.httpErrors.forbidden('需要管理员权限');
    }
  };
  app.get('/pending', { preHandler: admin }, async (request) => {
    const result = await query(
      `SELECT rs.*,g.name gym_name,u.nickname submitter_name
       FROM route_submissions rs
       JOIN gyms g ON g.id=rs.gym_id
       JOIN users u ON u.id=rs.submitter_id
       WHERE rs.status='pending' AND (
         $1::text='admin' OR EXISTS (
           SELECT 1 FROM gym_admins ga WHERE ga.user_id=$2 AND ga.gym_id=rs.gym_id
         )
       )
       ORDER BY rs.created_at`,
      [request.user.role, request.user.sub]
    );
    return { items: result.rows };
  });
  app.post('/:id/review', { preHandler: admin }, async (request) => {
    const { id } = idParams.parse(request.params); const b = reviewBody.parse(request.body);
    return transaction(async (client) => {
      const found = await client.query(
        `SELECT rs.* FROM route_submissions rs
         WHERE rs.id=$1 AND rs.status='pending' AND (
           $2::text='admin' OR EXISTS (
             SELECT 1 FROM gym_admins ga WHERE ga.user_id=$3 AND ga.gym_id=rs.gym_id
           )
         )
         FOR UPDATE`,
        [id, request.user.role, request.user.sub]
      );
      if (!found.rowCount) throw app.httpErrors.notFound('投稿不存在或已审核');
      const item = found.rows[0];
      let routeId: string | null = null;
      if (b.action === 'approve') {
        const route = await client.query(`INSERT INTO routes(gym_id,route_set_id,name,grade,color,wall_zone,cover_url,points) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`, [item.gym_id,item.route_set_id,item.name,item.grade,item.color,item.wall_zone,item.cover_url,JSON.stringify(item.points)]);
        routeId = route.rows[0].id;
      }
      await client.query(
        `UPDATE route_submissions
         SET status=$2,review_note=$3,reviewer_id=$4,published_route_id=$5,reviewed_at=now()
         WHERE id=$1`,
        [id,b.action==='approve'?'approved':'rejected',b.note??null,request.user.sub,routeId]
      );
      await client.query(
        `INSERT INTO notifications(user_id,type,title,content,target_path)
         VALUES($1,'submission_review',$2,$3,'/submissions/mine')`,
        [item.submitter_id,b.action==='approve'?'线路投稿已发布':'线路投稿未通过',b.note??(b.action==='approve'?'你的线路已经可以被岩友看到了':'请根据审核要求修改后重新投稿')]
      );
      return { status: b.action==='approve'?'approved':'rejected', routeId };
    });
  });
};
