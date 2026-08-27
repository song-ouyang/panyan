import type { FastifyPluginAsync } from 'fastify';
import { query } from '../db.js';
import { idParams, profileBody } from '../schemas.js';

export const userRoutes: FastifyPluginAsync = async (app) => {
  app.get('/search', { preHandler: app.authenticate }, async (request) => {
    const { q = '' } = request.query as { q?: string };
    if (q.trim().length < 1) return { items: [] };
    const result = await query(
      `SELECT u.id,u.nickname,u.avatar_url,u.bio,
       CASE WHEN f.status='accepted' THEN 'accepted' WHEN f.status='pending' AND f.requester_id=$1 THEN 'sent'
            WHEN f.status='pending' AND f.addressee_id=$1 THEN 'received' ELSE 'none' END friendship
       FROM users u LEFT JOIN friendships f ON
       ((f.requester_id=$1 AND f.addressee_id=u.id) OR (f.addressee_id=$1 AND f.requester_id=u.id))
       WHERE u.id<>$1 AND u.nickname ILIKE '%'||$2||'%' ORDER BY u.nickname LIMIT 30`, [request.user.sub, q.trim()]
    );
    return { items: result.rows };
  });
  app.get('/me', { preHandler: app.authenticate }, async (request) => {
    const user = await query('SELECT id,nickname,avatar_url,bio,role,created_at FROM users WHERE id=$1', [request.user.sub]);
    const stats = await query(
      `SELECT count(*)::int total_sends,count(DISTINCT r.gym_id)::int gym_count,
       coalesce(max(substring(r.grade from 2)::int),0)::int max_grade,
       count(*) FILTER (WHERE s.sent_at>=date_trunc('month',now()))::int monthly_sends,
       coalesce(max(substring(r.grade from 2)::int) FILTER (WHERE s.sent_at>=date_trunc('month',now())),0)::int monthly_max_grade
       FROM sends s JOIN routes r ON r.id=s.route_id WHERE s.user_id=$1`, [request.user.sub]
    );
    return { ...user.rows[0], stats: stats.rows[0] };
  });
  app.patch('/me', { preHandler: app.authenticate }, async (request) => {
    const body = profileBody.parse(request.body);
    const result = await query(
      `UPDATE users SET nickname=$2,avatar_url=$3,bio=$4,updated_at=now() WHERE id=$1
       RETURNING id,nickname,avatar_url,bio`, [request.user.sub, body.nickname, body.avatarUrl ?? null, body.bio ?? null]
    );
    return result.rows[0];
  });
  app.get('/me/growth', { preHandler: app.authenticate }, async (request) => {
    const { months = '6' } = request.query as { months?: string };
    const safeMonths = Math.min(24, Math.max(1, Number(months) || 6));
    const result = await query(
      `SELECT date_trunc('month',s.sent_at)::date AS "month",r.grade,count(*)::int sends
       FROM sends s JOIN routes r ON r.id=s.route_id
       WHERE s.user_id=$1 AND s.sent_at >= date_trunc('month',now()) - ($2::int-1)*interval '1 month'
       GROUP BY 1,2 ORDER BY 1,substring(r.grade from 2)::int`, [request.user.sub, safeMonths]
    );
    return { items: result.rows };
  });
  app.get('/me/month-dashboard', { preHandler: app.authenticate }, async (request) => {
    const rawMonth = (request.query as { month?: string }).month ?? new Date().toISOString().slice(0, 7);
    if (!/^\d{4}-\d{2}$/.test(rawMonth)) throw app.httpErrors.badRequest('月份格式应为 YYYY-MM');
    const monthStart = `${rawMonth}-01`;
    const daily = await query(
      `SELECT to_char(s.sent_at AT TIME ZONE 'Asia/Shanghai','YYYY-MM-DD') AS "day",g.name gym_name,r.grade,
       count(DISTINCT s.route_id)::int sends
       FROM sends s JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
       WHERE s.user_id=$1 AND s.sent_at >= $2::date AND s.sent_at < $2::date + interval '1 month'
       GROUP BY 1,g.id,r.grade ORDER BY 1,g.name,substring(r.grade from 2)::int`, [request.user.sub, monthStart]
    );
    const summary = await query(
      `SELECT count(DISTINCT (s.sent_at AT TIME ZONE 'Asia/Shanghai')::date)::int climbing_days,
       count(DISTINCT s.route_id)::int sends,count(DISTINCT r.gym_id)::int gyms,
       coalesce(max(substring(r.grade from 2)::int),0)::int max_grade,
       count(*) FILTER (WHERE s.attempts=1)::int flashes,count(*) FILTER (WHERE s.video_url IS NOT NULL)::int videos
       FROM sends s JOIN routes r ON r.id=s.route_id
       WHERE s.user_id=$1 AND s.sent_at >= $2::date AND s.sent_at < $2::date + interval '1 month'`, [request.user.sub, monthStart]
    );
    const byGrade = await query(
      `SELECT r.grade,count(DISTINCT s.route_id)::int sends FROM sends s JOIN routes r ON r.id=s.route_id
       WHERE s.user_id=$1 AND s.sent_at >= $2::date AND s.sent_at < $2::date + interval '1 month'
       GROUP BY r.grade ORDER BY substring(r.grade from 2)::int DESC`, [request.user.sub, monthStart]
    );
    const byGym = await query(
      `SELECT g.id gym_id,g.name gym_name,count(DISTINCT s.route_id)::int sends FROM sends s
       JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
       WHERE s.user_id=$1 AND s.sent_at >= $2::date AND s.sent_at < $2::date + interval '1 month'
       GROUP BY g.id ORDER BY sends DESC,g.name`, [request.user.sub, monthStart]
    );
    return { month: rawMonth, days: daily.rows, summary: summary.rows[0], byGrade: byGrade.rows, byGym: byGym.rows };
  });
  app.get('/me/growth-summary', { preHandler: app.authenticate }, async (request) => {
    const { gymId, setId } = request.query as { gymId?: string; setId?: string };
    const byGrade = await query(
      `SELECT r.grade,count(DISTINCT s.route_id)::int sends
       FROM sends s JOIN routes r ON r.id=s.route_id
       WHERE s.user_id=$1 AND ($2::uuid IS NULL OR r.gym_id=$2) AND ($3::uuid IS NULL OR r.route_set_id=$3)
       GROUP BY r.grade ORDER BY substring(r.grade from 2)::int`, [request.user.sub, gymId ?? null, setId ?? null]
    );
    const byGym = await query(
      `SELECT g.id gym_id,g.name gym_name,count(DISTINCT s.route_id)::int sends,
       max(substring(r.grade from 2)::int)::int max_grade
       FROM sends s JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
       WHERE s.user_id=$1 GROUP BY g.id ORDER BY sends DESC`, [request.user.sub]
    );
    return { byGrade: byGrade.rows, byGym: byGym.rows };
  });
  app.get('/me/cycle-summary', { preHandler: app.authenticate }, async (request) => {
    const result = await query(
      `SELECT g.id gym_id,g.name gym_name,rs.id route_set_id,rs.name route_set_name,
       rs.starts_on,rs.ends_on,r.grade,count(DISTINCT s.route_id)::int sends
       FROM sends s JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
       JOIN route_sets rs ON rs.id=r.route_set_id
       WHERE s.user_id=$1 AND rs.active=true
       GROUP BY g.id,rs.id,r.grade ORDER BY g.name,rs.starts_on DESC,substring(r.grade from 2)::int`, [request.user.sub]
    );
    return { items: result.rows };
  });
  app.get('/me/sends', { preHandler: app.authenticate }, async (request) => {
    const result = await query(
      `SELECT s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.visibility,s.moderation_status,s.sent_at,
       r.id route_id,r.name route_name,r.grade,g.name gym_name
       FROM sends s LEFT JOIN routes r ON r.id=s.route_id LEFT JOIN gyms g ON g.id=r.gym_id
       WHERE s.user_id=$1 ORDER BY s.sent_at DESC`, [request.user.sub]
    );
    return { items: result.rows };
  });
  app.get('/:id/public', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const user = await query(`SELECT id,nickname,avatar_url,bio,created_at FROM users WHERE id=$1`, [id]);
    if (!user.rowCount) throw app.httpErrors.notFound('岩友不存在');
    const stats = await query(
      `SELECT count(DISTINCT s.route_id)::int total_sends,count(DISTINCT r.gym_id)::int gym_count,
       coalesce(max(substring(r.grade from 2)::int),0)::int max_grade
       FROM sends s JOIN routes r ON r.id=s.route_id WHERE s.user_id=$1 AND s.visibility='public'`, [id]
    );
    const monthly = await query(
      `SELECT to_char(date_trunc('month',s.sent_at),'YYYY-MM') AS "month",g.name gym_name,r.grade,
       count(DISTINCT s.route_id)::int sends
       FROM sends s JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
       WHERE s.user_id=$1 AND s.visibility='public' AND s.moderation_status='approved'
       GROUP BY 1,g.id,r.grade ORDER BY 1 DESC,g.name,substring(r.grade from 2)::int`, [id]
    );
    const friendship = await query(
      `SELECT CASE WHEN status='accepted' THEN 'accepted' WHEN requester_id=$1 THEN 'sent' ELSE 'received' END friendship
       FROM friendships WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)`, [request.user.sub,id]
    );
    return { ...user.rows[0], stats: stats.rows[0], monthly: monthly.rows,
      friendship: id === request.user.sub ? 'self' : (friendship.rows[0]?.friendship ?? 'none') };
  });
  app.post('/:id/friend-request', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    if (id === request.user.sub) throw app.httpErrors.badRequest('不能添加自己');
    const created = await query(
      `INSERT INTO friendships(requester_id,addressee_id)
       SELECT $1,$2 WHERE NOT EXISTS (SELECT 1 FROM friendships WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1))
       ON CONFLICT DO NOTHING RETURNING requester_id`, [request.user.sub, id]
    );
    if (created.rowCount) await query(`INSERT INTO notifications(user_id,type,title,content,target_path) VALUES($1,'friend_request','新的岩友申请','有人想添加你为岩友','/pages/friends/index')`, [id]);
    return { status: 'pending' };
  });
  app.post('/:id/friend-accept', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(`UPDATE friendships SET status='accepted',updated_at=now() WHERE requester_id=$1 AND addressee_id=$2 RETURNING status`, [id, request.user.sub]);
    if (!result.rowCount) throw app.httpErrors.notFound('好友申请不存在');
    await query(`INSERT INTO notifications(user_id,type,title,content,target_path) VALUES($1,'friend_accepted','岩友申请已通过','你们现在可以一起约爬了','/pages/friends/index')`, [id]);
    return result.rows[0];
  });
  app.get('/me/friends', { preHandler: app.authenticate }, async (request) => {
    const result = await query(
      `SELECT u.id,u.nickname,u.avatar_url FROM friendships f JOIN users u
       ON u.id=CASE WHEN f.requester_id=$1 THEN f.addressee_id ELSE f.requester_id END
       WHERE f.status='accepted' AND (f.requester_id=$1 OR f.addressee_id=$1) ORDER BY u.nickname`, [request.user.sub]
    );
    return { items: result.rows };
  });
  app.get('/me/friend-requests', { preHandler: app.authenticate }, async (request) => {
    const result = await query(
      `SELECT u.id,u.nickname,u.avatar_url,f.created_at FROM friendships f JOIN users u ON u.id=f.requester_id
       WHERE f.addressee_id=$1 AND f.status='pending' ORDER BY f.created_at DESC`, [request.user.sub]
    );
    return { items: result.rows };
  });
  app.delete('/:id/friend', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    await query(`DELETE FROM friendships WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)`, [request.user.sub,id]);
    return { removed: true };
  });
  app.delete('/me', { preHandler: app.authenticate }, async (request) => {
    await query('DELETE FROM users WHERE id=$1', [request.user.sub]);
    return { deleted: true };
  });
};
