import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { query, transaction } from '../db.js';
import { invalidateSendFacts, lockGrowth, recomputeGrowth, recordClimbingFact } from '../services/growth.js';
import { idParams } from '../schemas.js';

const gym = z.object({ name: z.string().min(2).max(80), city: z.string().min(2).max(40), district: z.string().max(40).optional(), brandId: z.string().uuid().optional(), address: z.string().min(2).max(160), latitude: z.number().optional(), longitude: z.number().optional(), coverUrl: z.string().url().optional(), description: z.string().optional() });
const brand = z.object({ name: z.string().min(2).max(80), logoUrl: z.string().url().optional(), description: z.string().optional() });
const routeSet = z.object({ gymId: z.string().uuid(), name: z.string().min(2).max(80), startsOn: z.string().date(), endsOn: z.string().date().nullable().optional() });
const route = z.object({ gymId: z.string().uuid(), routeSetId: z.string().uuid().nullable().optional(), name: z.string().min(1).max(80), grade: z.string().regex(/^V([0-9]|1[0-7])$/), color: z.string().min(1).max(24), wallZone: z.string().max(40).optional(), coverUrl: z.string().url().optional(), setterName: z.string().max(40).optional(), points: z.array(z.object({ x: z.number().min(0).max(1), y: z.number().min(0).max(1), type: z.enum(['start', 'hold', 'finish']) })).default([]) });

export const adminRoutes: FastifyPluginAsync = async (app) => {
  const admin = async (request: FastifyRequest) => {
    await app.authenticate(request);
    if (!['gym_admin', 'admin'].includes(request.user.role)) throw app.httpErrors.forbidden('需要岩馆管理员权限');
  };
  const platformAdmin = async (request: FastifyRequest) => {
    await app.authenticate(request);
    if (request.user.role !== 'admin') throw app.httpErrors.forbidden('需要平台管理员权限');
  };
  const assertGymAccess = async (request: FastifyRequest, gymId: string) => {
    if (request.user.role === 'admin') return;
    const membership = await query(
      'SELECT 1 FROM gym_admins WHERE user_id=$1 AND gym_id=$2',
      [request.user.sub, gymId]
    );
    if (!membership.rowCount) throw app.httpErrors.forbidden('无权管理这个岩馆');
  };
  app.post('/gyms', { preHandler: platformAdmin }, async (request) => {
    const b = gym.parse(request.body);
    const result = await query(`INSERT INTO gyms(name,city,district,brand_id,address,latitude,longitude,cover_url,description) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`, [b.name,b.city,b.district??null,b.brandId??null,b.address,b.latitude??null,b.longitude??null,b.coverUrl??null,b.description??null]);
    return result.rows[0];
  });
  app.post('/brands', { preHandler: platformAdmin }, async (request) => {
    const b = brand.parse(request.body);
    const result = await query(`INSERT INTO gym_brands(name,logo_url,description) VALUES($1,$2,$3) ON CONFLICT(name) DO UPDATE SET logo_url=EXCLUDED.logo_url,description=EXCLUDED.description RETURNING *`, [b.name,b.logoUrl??null,b.description??null]);
    return result.rows[0];
  });
  app.post('/route-sets', { preHandler: admin }, async (request) => {
    const b = routeSet.parse(request.body);
    await assertGymAccess(request, b.gymId);
    const result = await query(`INSERT INTO route_sets(gym_id,name,starts_on,ends_on) VALUES($1,$2,$3,$4) RETURNING *`, [b.gymId,b.name,b.startsOn,b.endsOn??null]);
    return result.rows[0];
  });
  app.post('/routes', { preHandler: admin }, async (request) => {
    const b = route.parse(request.body);
    await assertGymAccess(request, b.gymId);
    const result = await query(`INSERT INTO routes(gym_id,route_set_id,name,grade,color,wall_zone,cover_url,setter_name,points) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`, [b.gymId,b.routeSetId??null,b.name,b.grade,b.color,b.wallZone??null,b.coverUrl??null,b.setterName??null,JSON.stringify(b.points)]);
    return result.rows[0];
  });
  app.post('/growth/sends/:id/invalidate', { preHandler: platformAdmin }, async (request) => {
    const { id } = idParams.parse(request.params);
    const { reason } = z.object({ reason: z.string().trim().min(2).max(300) }).parse(request.body);
    return transaction(async (client) => {
      const owner = await client.query<{ user_id: string }>('SELECT user_id FROM sends WHERE id=$1 AND route_id IS NOT NULL', [id]);
      if (!owner.rowCount) throw app.httpErrors.notFound('完攀记录不存在');
      const userId = owner.rows[0]!.user_id;
      await lockGrowth(client, userId);
      const found = await client.query("UPDATE sends SET moderation_status='rejected' WHERE id=$1 AND user_id=$2 RETURNING id", [id, userId]);
      if (!found.rowCount) throw app.httpErrors.notFound('完攀记录不存在');
      const growth = await invalidateSendFacts(client, userId, id, reason, request.user.sub);
      return { invalidated: true, growth };
    });
  });
  app.get('/moderation', { preHandler: platformAdmin }, async () => {
    const sends = await query(`SELECT s.id,s.caption,s.video_url,s.created_at,u.nickname FROM sends s JOIN users u ON u.id=s.user_id WHERE s.moderation_status='pending' ORDER BY s.created_at`);
    const comments = await query(`SELECT c.id,c.content,c.created_at,u.nickname FROM comments c JOIN users u ON u.id=c.user_id WHERE c.moderation_status='pending' ORDER BY c.created_at`);
    const reports = await query(`SELECT * FROM reports WHERE status='pending' ORDER BY created_at`);
    return { sends: sends.rows, comments: comments.rows, reports: reports.rows };
  });
  app.post('/moderation/:id', { preHandler: platformAdmin }, async (request) => {
    const { id } = idParams.parse(request.params);
    const b = z.object({ targetType: z.enum(['send','comment','report']), action: z.enum(['approve','reject']) }).parse(request.body);
    const status = b.action === 'approve' ? 'approved' : 'rejected';
    if (b.targetType === 'send') {
      const reviewed = await transaction(async (client) => {
        const owner = await client.query<{ user_id: string }>('SELECT user_id FROM sends WHERE id=$1', [id]);
        if (!owner.rowCount) return { rows: [] };
        await lockGrowth(client, owner.rows[0]!.user_id);
        const result = await client.query<{ user_id: string; route_id: string | null; visibility: string; sent_at: Date }>(
          `UPDATE sends SET moderation_status=$2 WHERE id=$1 AND moderation_status='pending' RETURNING user_id,route_id,visibility,sent_at`,
          [id,status]
        );
        const item = result.rows[0];
        if (item?.route_id && status === 'approved') {
          await recordClimbingFact(client, { userId: item.user_id, sendId: id, routeId: item.route_id,
            sourceKind: 'checkin', occurredAt: item.sent_at });
          await recomputeGrowth(client, item.user_id);
        } else if (item) await invalidateSendFacts(client, item.user_id, id, 'moderation_rejected', request.user.sub);
        return result;
      });
      const item = reviewed.rows[0];
      if (item) {
        const isCheckin = Boolean(item.route_id);
        const title = b.action === 'approve'
          ? (isCheckin ? '完攀审核已通过' : '动态审核已通过')
          : (isCheckin ? '完攀审核未通过' : '动态审核未通过');
        const content = b.action === 'approve'
          ? (item.visibility === 'public'
              ? (isCheckin ? '本次完攀已进入线路榜和月度排名' : '你的动态已经发布到广场')
              : item.visibility === 'friends'
                ? (isCheckin ? '本次完攀已分享给岩友，公开榜单不会展示' : '你的动态已经发布到朋友圈')
                : '内容已通过审核，仅你自己可见')
          : '你可以前往“我的动态”查看本次审核结果';
        await query(
          `INSERT INTO notifications(user_id,type,title,content,target_path) VALUES($1,'content_review',$2,$3,'/pages/my-posts/index')`,
          [item.user_id,title,content]
        );
      }
    }
    if (b.targetType === 'comment') {
      const reviewed = await query<{ user_id: string; send_id: string }>(
        `UPDATE comments SET moderation_status=$2 WHERE id=$1 AND moderation_status='pending' RETURNING user_id,send_id`,
        [id,status]
      );
      const item = reviewed.rows[0];
      if (item) {
        await query(
          `INSERT INTO notifications(user_id,type,title,content,target_path) VALUES($1,'comment_review',$2,$3,$4)`,
          [
            item.user_id,
            b.action === 'approve' ? '评论审核已通过' : '评论审核未通过',
            b.action === 'approve' ? '你的评论已经公开展示' : '请调整评论内容后重新发送',
            `/pages/post/index?id=${item.send_id}`
          ]
        );
      }
    }
    if (b.targetType === 'report') await query(`UPDATE reports SET status=$2 WHERE id=$1`, [id,b.action==='approve'?'approved':'rejected']);
    return { status };
  });
};
