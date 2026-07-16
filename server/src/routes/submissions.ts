import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { query, transaction } from '../db.js';
import { idParams } from '../schemas.js';

const body = z.object({ gymId: z.string().uuid(), routeSetId: z.string().uuid().nullable().optional(), name: z.string().min(1).max(80), grade: z.string().regex(/^V([0-9]|1[0-7])$/), color: z.string().min(1).max(24), wallZone: z.string().max(40).optional(), coverUrl: z.string().url(), points: z.array(z.object({ x: z.number().min(0).max(1), y: z.number().min(0).max(1), type: z.enum(['start','hold','finish']) })).min(2).max(80) });
const reviewBody = z.object({ action: z.enum(['approve','reject']), note: z.string().max(300).optional() });

export const submissionRoutes: FastifyPluginAsync = async (app) => {
  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const b = body.parse(request.body);
    const result = await query(
      `INSERT INTO route_submissions(submitter_id,gym_id,route_set_id,name,grade,color,wall_zone,cover_url,points)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`, [request.user.sub,b.gymId,b.routeSetId??null,b.name,b.grade,b.color,b.wallZone??null,b.coverUrl,JSON.stringify(b.points)]
    );
    return result.rows[0];
  });
  app.get('/mine', { preHandler: app.authenticate }, async (request) => {
    const result = await query(`SELECT rs.*,g.name gym_name FROM route_submissions rs JOIN gyms g ON g.id=rs.gym_id WHERE rs.submitter_id=$1 ORDER BY rs.created_at DESC`, [request.user.sub]);
    return { items: result.rows };
  });
  const admin = async (request: FastifyRequest) => { await app.authenticate(request); if (!['gym_admin','admin'].includes(request.user.role)) throw app.httpErrors.forbidden('需要管理员权限'); };
  app.get('/pending', { preHandler: admin }, async () => {
    const result = await query(`SELECT rs.*,g.name gym_name,u.nickname submitter_name FROM route_submissions rs JOIN gyms g ON g.id=rs.gym_id JOIN users u ON u.id=rs.submitter_id WHERE rs.status='pending' ORDER BY rs.created_at`);
    return { items: result.rows };
  });
  app.post('/:id/review', { preHandler: admin }, async (request) => {
    const { id } = idParams.parse(request.params); const b = reviewBody.parse(request.body);
    return transaction(async (client) => {
      const found = await client.query(`SELECT * FROM route_submissions WHERE id=$1 AND status='pending' FOR UPDATE`, [id]);
      if (!found.rowCount) throw app.httpErrors.notFound('投稿不存在或已审核');
      const item = found.rows[0];
      let routeId: string | null = null;
      if (b.action === 'approve') {
        const route = await client.query(`INSERT INTO routes(gym_id,route_set_id,name,grade,color,wall_zone,cover_url,points) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`, [item.gym_id,item.route_set_id,item.name,item.grade,item.color,item.wall_zone,item.cover_url,JSON.stringify(item.points)]);
        routeId = route.rows[0].id;
      }
      await client.query(`UPDATE route_submissions SET status=$2,review_note=$3,reviewer_id=$4,reviewed_at=now() WHERE id=$1`, [id,b.action==='approve'?'approved':'rejected',b.note??null,request.user.sub]);
      await client.query(`INSERT INTO notifications(user_id,type,title,content,target_path) VALUES($1,'submission_review',$2,$3,'/pages/submissions/index')`, [item.submitter_id,b.action==='approve'?'线路投稿已发布':'线路投稿未通过',b.note??(b.action==='approve'?'你的线路已经可以被岩友看到了':'请根据审核要求修改后重新投稿')]);
      return { status: b.action==='approve'?'approved':'rejected', routeId };
    });
  });
};
