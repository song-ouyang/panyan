import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { query } from "../db.js";

const emptyStringToUndefined = (value: unknown) =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

const optionalUuid = z.preprocess(
  emptyStringToUndefined,
  z.string().uuid().optional(),
);
const optionalRegion = z.preprocess(
  emptyStringToUndefined,
  z.string().trim().min(1).max(40).optional(),
);

const routeRankingQuery = z
  .object({
    gymId: optionalUuid,
    setId: optionalUuid,
    province: optionalRegion,
    city: optionalRegion,
  })
  .superRefine((value, context) => {
    if (
      (value.province === undefined) !== (value.city === undefined)
    ) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: [value.province === undefined ? "province" : "city"],
        message: "线路地区筛选必须同时提供省份和城市",
      });
    }
  });

const userRankingQuery = z
  .object({
    gymId: optionalUuid,
    setId: optionalUuid,
    scope: z.preprocess(
      emptyStringToUndefined,
      z.enum(["national", "province", "city"]).default("national"),
    ),
    province: optionalRegion,
    city: optionalRegion,
  })
  .superRefine((value, context) => {
    if (value.scope === "national" && (value.province || value.city)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["scope"],
        message: "全国榜不接受省市筛选",
      });
    }
    if (value.scope === "province" && !value.province) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["province"],
        message: "省榜必须提供省份",
      });
    }
    if (value.scope === "province" && value.city) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["city"],
        message: "省榜不接受城市筛选",
      });
    }
    if (value.scope === "city" && (!value.province || !value.city)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: !value.province ? ["province"] : ["city"],
        message: "市榜必须同时提供省份和城市",
      });
    }
  });

export const rankingRoutes: FastifyPluginAsync = async (app) => {
  app.get("/regions", { preHandler: app.authenticateOptional }, async () => {
    const result = await query(
      `SELECT province,city FROM gyms GROUP BY province,city ORDER BY province,city`,
    );
    return { items: result.rows };
  });
  app.get("/routes", { preHandler: app.authenticateOptional }, async (request) => {
    const { gymId, setId, province, city } = routeRankingQuery.parse(
      request.query,
    );
    const viewerId = request.user?.sub ?? null;
    const result = await query(
      `WITH send_likes AS (
         SELECT s.id,s.route_id,s.user_id,s.video_url,count(l.user_id)::int likes
         FROM sends s LEFT JOIN post_likes l ON l.send_id=s.id
         WHERE s.visibility='public' AND s.moderation_status='approved'
           AND ($5::uuid IS NULL OR NOT EXISTS (
             SELECT 1 FROM friendships blocked
             WHERE blocked.status='blocked' AND (
               (blocked.requester_id=$5 AND blocked.addressee_id=s.user_id) OR
               (blocked.addressee_id=$5 AND blocked.requester_id=s.user_id)
             )
           ))
         GROUP BY s.id
       ), ranked AS (
         SELECT sl.*,row_number() OVER(PARTITION BY sl.route_id ORDER BY sl.likes DESC,sl.id) rn FROM send_likes sl
       )
       SELECT r.id route_id,r.name route_name,r.grade,r.color,r.cover_url,r.wall_zone,
       g.id gym_id,g.name gym_name,g.province,g.city,
       count(DISTINCT sl.user_id)::int completion_count,
       coalesce(sum(sl.likes),0)::int total_likes,
       max(CASE WHEN ranked.rn=1 THEN ranked.id::text END)::uuid top_send_id,
       max(CASE WHEN ranked.rn=1 THEN ranked.video_url END) top_video_url,
       max(CASE WHEN ranked.rn=1 THEN u.nickname END) top_user_name,
       max(CASE WHEN ranked.rn=1 THEN u.avatar_url END) top_user_avatar
       FROM routes r JOIN gyms g ON g.id=r.gym_id LEFT JOIN route_sets rs ON rs.id=r.route_set_id LEFT JOIN send_likes sl ON sl.route_id=r.id
       LEFT JOIN ranked ON ranked.id=sl.id LEFT JOIN users u ON u.id=ranked.user_id AND ranked.rn=1
       WHERE r.published=true AND ($1::uuid IS NULL OR r.gym_id=$1)
       AND (($2::uuid IS NOT NULL AND r.route_set_id=$2) OR ($2::uuid IS NULL AND (r.route_set_id IS NULL OR rs.active=true)))
       AND ($3::text IS NULL OR (g.province=$3 AND g.city=$4))
       GROUP BY r.id,g.id
       ORDER BY completion_count DESC,total_likes DESC,substring(r.grade from 2)::int DESC,r.id
       LIMIT 100`,
      [
        gymId ?? null,
        setId ?? null,
        province ?? null,
        city ?? null,
        viewerId,
      ],
    );
    return { items: result.rows };
  });

  app.get("/", { preHandler: app.authenticateOptional }, async (request) => {
    const { gymId, setId, scope, province, city } = userRankingQuery.parse(
      request.query,
    );
    const result = await query<{
      user_id: string;
      nickname: string;
      avatar_url: string | null;
      send_count: number;
      total_likes: number;
      points: number;
      max_grade: number;
      last_send: string;
    }>(
      `WITH send_scores AS (
         SELECT s.id,s.user_id,s.route_id,s.sent_at,substring(r.grade from 2)::int grade_number,
         (10 + substring(r.grade from 2)::int * 5 + CASE WHEN s.attempts=1 THEN 5 ELSE 0 END)::int completion_points,
         count(l.user_id)::int likes
         FROM sends s JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
         LEFT JOIN post_likes l ON l.send_id=s.id
         WHERE ($1::uuid IS NULL OR r.gym_id=$1) AND ($2::uuid IS NULL OR r.route_set_id=$2)
           AND s.sent_at >=
             (date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai')
           AND s.moderation_status='approved'
           AND s.visibility='public'
           AND ($3='national' OR ($3='province' AND g.province=$4) OR ($3='city' AND g.province=$4 AND g.city=$5))
           AND ($6::uuid IS NULL OR NOT EXISTS (
             SELECT 1 FROM friendships blocked
             WHERE blocked.status='blocked' AND (
               (blocked.requester_id=$6 AND blocked.addressee_id=s.user_id) OR
               (blocked.addressee_id=$6 AND blocked.requester_id=s.user_id)
             )
           ))
         GROUP BY s.id,r.id
       )
       SELECT u.id user_id,u.nickname,u.avatar_url,count(DISTINCT ss.route_id)::int send_count,
       sum(ss.likes)::int total_likes,(sum(ss.completion_points)+sum(ss.likes)*2)::int points,
       max(ss.grade_number)::int max_grade,max(ss.sent_at) last_send
       FROM send_scores ss JOIN users u ON u.id=ss.user_id
       GROUP BY u.id ORDER BY points DESC,total_likes DESC,send_count DESC,last_send DESC LIMIT 100`,
      [gymId ?? null, setId ?? null, scope, province ?? null, city ?? null, request.user?.sub ?? null],
    );
    const items = result.rows.map((row, index) => ({
      rank: index + 1,
      ...row,
    }));
    const viewerId = request.user?.sub ?? null;
    const myRankResult = viewerId
      ? await query<{
          user_id: string;
          nickname: string;
          avatar_url: string | null;
          send_count: number;
          total_likes: number;
          points: number;
          max_grade: number;
          last_send: string;
          rank: number;
        }>(
          `WITH send_scores AS (
         SELECT s.id,s.user_id,s.route_id,s.sent_at,substring(r.grade from 2)::int grade_number,
         (10 + substring(r.grade from 2)::int * 5 + CASE WHEN s.attempts=1 THEN 5 ELSE 0 END)::int completion_points,
         count(l.user_id)::int likes
         FROM sends s JOIN routes r ON r.id=s.route_id JOIN gyms g ON g.id=r.gym_id
         LEFT JOIN post_likes l ON l.send_id=s.id
         WHERE ($1::uuid IS NULL OR r.gym_id=$1) AND ($2::uuid IS NULL OR r.route_set_id=$2)
           AND s.sent_at >=
             (date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai')
           AND s.moderation_status='approved'
           AND s.visibility='public'
           AND ($3='national' OR ($3='province' AND g.province=$4) OR ($3='city' AND g.province=$4 AND g.city=$5))
           AND NOT EXISTS (
             SELECT 1 FROM friendships blocked
             WHERE blocked.status='blocked' AND (
               (blocked.requester_id=$6 AND blocked.addressee_id=s.user_id) OR
               (blocked.addressee_id=$6 AND blocked.requester_id=s.user_id)
             )
           )
         GROUP BY s.id,r.id
       ), totals AS (
         SELECT u.id user_id,u.nickname,u.avatar_url,count(DISTINCT ss.route_id)::int send_count,
         sum(ss.likes)::int total_likes,(sum(ss.completion_points)+sum(ss.likes)*2)::int points,
         max(ss.grade_number)::int max_grade,max(ss.sent_at) last_send
         FROM send_scores ss JOIN users u ON u.id=ss.user_id GROUP BY u.id
       ), ranked AS (
         SELECT totals.*,row_number() OVER (ORDER BY points DESC,total_likes DESC,send_count DESC,last_send DESC)::int rank
         FROM totals
       ) SELECT * FROM ranked WHERE user_id=$6`,
          [
            gymId ?? null,
            setId ?? null,
            scope,
            province ?? null,
            city ?? null,
            viewerId,
          ],
        )
      : { rows: [] };
    return {
      items,
      myRank: myRankResult.rows[0] ?? null,
      scoring: { completion: 10, gradeStep: 5, flash: 5, like: 2 },
    };
  });
};
