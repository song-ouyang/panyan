import { randomBytes } from 'node:crypto';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query } from '../db.js';
import { idParams } from '../schemas.js';

const monthInput = z.object({
  month: z.string().length(7, '月份格式应为 YYYY-MM').regex(/^(?!0000)\d{4}-(0[1-9]|1[0-2])$/, '月份格式应为 YYYY-MM')
}).strict();
const tokenParams = z.object({
  token: z.string().length(43, '分享链接格式不正确').regex(/^[A-Za-z0-9_-]{43}$/, '分享链接格式不正确')
}).strict();

type SharedRoute = {
  id: string;
  name: string;
  grade: string;
  color: string;
  wall_zone: string | null;
  cover_url: string | null;
  points: { x: number; y: number; type: string }[];
  gym_name: string;
  gym_address: string;
  route_set_name: string | null;
  send_count: number;
};

type MonthlySummary = {
  climbing_days: number;
  sends: number;
  gyms: number;
  max_grade: number;
  flashes: number;
  videos: number;
};

type SharedMonth = {
  month: string;
  nickname: string;
  avatar_url: string | null;
  summary: MonthlySummary;
  days: { day: string; sends: number }[];
  byGrade: { grade: string; sends: number }[];
};

export const shareRoutes: FastifyPluginAsync = async (app) => {
  // Apply onSend to successful responses and errors, including rate limiting.
  // Never cache a capability URL: a revoked share must disappear on next load.
  app.addHook('onSend', async (_request, reply, payload) => {
    reply.header('cache-control', 'private, no-store, max-age=0');
    reply.header('pragma', 'no-cache');
    reply.header('referrer-policy', 'no-referrer');
    reply.header('x-robots-tag', 'noindex, nofollow');
    return payload;
  });

  app.get('/routes/:id', {
    preHandler: app.authenticateOptional,
    // Website SSR requests may share an egress IP during a group-share burst.
    config: { rateLimit: { max: 600, timeWindow: '1 minute' } }
  }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query<SharedRoute>(
      `SELECT r.id,r.name,r.grade,r.color,r.wall_zone,r.cover_url,r.points,
       g.name gym_name,g.address gym_address,rs.name route_set_name,
       count(DISTINCT s.id)::int send_count
       FROM routes r JOIN gyms g ON g.id=r.gym_id LEFT JOIN route_sets rs ON rs.id=r.route_set_id
       LEFT JOIN sends s ON s.route_id=r.id
         AND s.moderation_status='approved' AND s.visibility='public' AND s.video_url IS NOT NULL
       WHERE r.id=$1 AND r.published=true
       GROUP BY r.id,g.id,rs.id`, [id]
    );
    const route = result.rows[0];
    if (!route) throw app.httpErrors.notFound('线路不存在或已下架');
    return {
      kind: 'route',
      // A dedicated allowlist keeps unrelated route/detail fields out of shares.
      route: {
        id: route.id, name: route.name, grade: route.grade, color: route.color,
        wall_zone: route.wall_zone, cover_url: route.cover_url, points: route.points,
        gym_name: route.gym_name, gym_address: route.gym_address,
        route_set_name: route.route_set_name, send_count: route.send_count
      },
      title: `${route.name} · ${route.grade}｜完攀日记`,
      description: `${route.gym_name}的${route.color}${route.grade}线路，来看看岩壁标点，一起完攀。`
    };
  });

  app.get('/monthly', {
    preHandler: app.authenticate,
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request) => {
    const { month } = monthInput.parse(request.query);
    const result = await query<{ token: string }>(
      `SELECT token FROM monthly_record_shares
       WHERE user_id=$1 AND month=$2::date AND revoked_at IS NULL`,
      [request.user.sub, `${month}-01`]
    );
    return { token: result.rows[0]?.token ?? null, month };
  });

  app.post('/monthly', {
    preHandler: app.authenticate,
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
  }, async (request) => {
    const { month } = monthInput.parse(request.body);
    const currentMonth = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString().slice(0, 7);
    if (month > currentMonth) throw app.httpErrors.badRequest('还不能分享未来月份的记录');
    const result = await query<{ token: string }>(
      `INSERT INTO monthly_record_shares(token,user_id,month) VALUES($1,$2,$3::date)
       ON CONFLICT(user_id,month) DO UPDATE SET
         token=CASE WHEN monthly_record_shares.revoked_at IS NULL THEN monthly_record_shares.token ELSE EXCLUDED.token END,
         created_at=CASE WHEN monthly_record_shares.revoked_at IS NULL THEN monthly_record_shares.created_at ELSE now() END,
         revoked_at=NULL
       RETURNING token`,
      [randomBytes(32).toString('base64url'), request.user.sub, `${month}-01`]
    );
    return { token: result.rows[0]!.token, month };
  });

  app.get('/monthly/:token', {
    preHandler: app.authenticateOptional,
    config: { rateLimit: { max: 600, timeWindow: '1 minute' } }
  }, async (request) => {
    const { token } = tokenParams.parse(request.params);
    // One statement gives the capability check and live aggregates one snapshot.
    // Route IDs/gym IDs are used only for counting and never leave this query.
    const result = await query<SharedMonth>(
      `WITH shared AS (
         SELECT ms.user_id,ms.month,u.nickname,u.avatar_url
         FROM monthly_record_shares ms JOIN users u ON u.id=ms.user_id
         WHERE ms.token=$1 AND ms.revoked_at IS NULL
       ), records AS (
         SELECT s.route_id,r.gym_id,r.grade,s.attempts,s.video_url,
                to_char(s.sent_at AT TIME ZONE 'Asia/Shanghai','YYYY-MM-DD') AS "day"
         FROM shared JOIN sends s ON s.user_id=shared.user_id JOIN routes r ON r.id=s.route_id
         WHERE s.moderation_status='approved'
           AND s.sent_at >= (shared.month::timestamp AT TIME ZONE 'Asia/Shanghai')
           AND s.sent_at < ((shared.month + interval '1 month')::timestamp AT TIME ZONE 'Asia/Shanghai')
       )
       SELECT to_char(shared.month,'YYYY-MM') AS "month",shared.nickname,shared.avatar_url,
         (SELECT json_build_object(
           'climbing_days',count(DISTINCT day)::int,
           'sends',count(DISTINCT route_id)::int,
           'gyms',count(DISTINCT gym_id)::int,
           'max_grade',coalesce(max(substring(grade from 2)::int),0)::int,
           'flashes',count(*) FILTER (WHERE attempts=1)::int,
           'videos',count(*) FILTER (WHERE video_url IS NOT NULL)::int
         ) FROM records) summary,
         (SELECT coalesce(json_agg(d ORDER BY d.day),'[]'::json)
          FROM (SELECT day,count(DISTINCT route_id)::int sends FROM records GROUP BY day) d) days,
         (SELECT coalesce(json_agg(g ORDER BY substring(g.grade from 2)::int DESC),'[]'::json)
          FROM (SELECT grade,count(DISTINCT route_id)::int sends FROM records GROUP BY grade) g) "byGrade"
       FROM shared`, [token]
    );
    const monthly = result.rows[0];
    if (!monthly) throw app.httpErrors.notFound('分享不存在或已被撤回');
    return {
      kind: 'monthly', month: monthly.month,
      author: { nickname: monthly.nickname, avatar_url: monthly.avatar_url },
      summary: monthly.summary, days: monthly.days, byGrade: monthly.byGrade,
      title: `${monthly.nickname}的${Number(monthly.month.slice(5))}月攀岩记录｜完攀日记`,
      description: `${monthly.month}，攀岩${monthly.summary.climbing_days}天，完攀${monthly.summary.sends}条线路。每一次出发，都值得记录。`
    };
  });

  app.delete('/monthly/:token', {
    preHandler: app.authenticate,
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
  }, async (request) => {
    const { token } = tokenParams.parse(request.params);
    const result = await query<{ exists: boolean; revoked: boolean }>(
      `WITH candidate AS (
         SELECT user_id FROM monthly_record_shares WHERE token=$1
       ), revoked AS (
         UPDATE monthly_record_shares SET revoked_at=coalesce(revoked_at,now())
         WHERE token=$1 AND user_id=$2 RETURNING token
       )
       SELECT EXISTS(SELECT 1 FROM candidate) "exists",EXISTS(SELECT 1 FROM revoked) revoked`,
      [token, request.user.sub]
    );
    if (result.rows[0]?.exists && !result.rows[0].revoked) {
      throw app.httpErrors.notFound('分享不存在或无权撤回');
    }
    return { revoked: true };
  });
};
