import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

// Run the real migration and API queries in a private schema, never against
// another suite's fixtures or an application database.
const database = vi.hoisted(() => ({ query: vi.fn(), transaction: vi.fn() }));
vi.mock('../src/db.js', () => database);

import { config } from '../src/config.js';
import { authPlugin } from '../src/auth.js';
import { userRoutes } from '../src/routes/users.js';
import { sendRoutes } from '../src/routes/sends.js';
import { rankingRoutes } from '../src/routes/rankings.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;
const marker = 'all_pending_content_publish_immediately_v1';
type Status = 'pending' | 'approved' | 'rejected';
type Visibility = 'public' | 'friends' | 'private';

suite('all pending content publication migration with isolated local PostgreSQL', () => {
  let app: FastifyInstance | undefined;
  let client: pg.Client | undefined;
  let schemaCreated = false;
  let schemaSql: string;
  const schema = `all_pending_migration_test_${randomUUID().replaceAll('-', '')}`;
  let ownerId: string;
  let otherId: string;
  let gymId: string;
  let setId: string;
  let sentAt: Date;
  let day: string;
  let month: string;

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) {
      throw new Error('Pending publication migration E2E requires a dedicated local test/e2e/CI database');
    }
    client = new pg.Client(config.DATABASE_URL ? { connectionString: config.DATABASE_URL } : {
      host: config.PGHOST, port: config.PGPORT, database: config.PGDATABASE,
      user: config.PGUSER, password: config.PGPASSWORD
    });
    await client.connect();
    await client.query(`CREATE SCHEMA "${schema}"`);
    schemaCreated = true;
    await client.query(`SET search_path TO "${schema}",public`);
    await client.query("SET TIME ZONE 'America/Los_Angeles'");
    schemaSql = await readFile(new URL('../src/db/schema.sql', import.meta.url), 'utf8');
    await client.query(schemaSql);
    database.query.mockImplementation((sql: string, values: unknown[] = []) => client!.query(sql, values));
    app = Fastify();
    await app.register(sensible);
    await app.register(authPlugin);
    await app.register(userRoutes, { prefix: '/api/users' });
    await app.register(sendRoutes, { prefix: '/api/sends' });
    await app.register(rankingRoutes, { prefix: '/api/rankings' });
    await app.ready();
  });

  beforeEach(async () => {
    await client!.query('TRUNCATE users,gyms CASCADE');
    // The older, narrower repair remains applied. Only the new policy is due.
    await client!.query('DELETE FROM data_migrations WHERE name=$1', [marker]);
    ownerId = randomUUID();
    otherId = randomUUID();
    gymId = randomUUID();
    setId = randomUUID();
    await client!.query(
      `INSERT INTO users(id,openid) VALUES($1::uuid,$1::uuid::text),($2::uuid,$2::uuid::text)`, [ownerId, otherId]
    );
    await client!.query(
      `INSERT INTO gyms(id,name,city,address) VALUES($1,'历史发布测试岩馆','上海','测试地址')`, [gymId]
    );
    await client!.query(
      `INSERT INTO route_sets(id,gym_id,name,starts_on) VALUES($1,$2,'历史换线周期','2020-01-01')`, [setId, gymId]
    );
    // Verify Shanghai calendar dates even when PostgreSQL uses another zone.
    ({ sent_at: sentAt, day, month } = (await client!.query<{ sent_at: Date; day: string; month: string }>(
      `SELECT (date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') + interval '5 minutes')
                AT TIME ZONE 'Asia/Shanghai' sent_at,
              to_char(now() AT TIME ZONE 'Asia/Shanghai','YYYY-MM-01') AS "day",
              to_char(now() AT TIME ZONE 'Asia/Shanghai','YYYY-MM') AS "month"`
    )).rows[0]!);
  });

  afterAll(async () => {
    if (app) await app.close();
    if (client && schemaCreated) await client.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (client) await client.end();
  });

  const headers = (userId = ownerId) => ({ authorization: `Bearer ${app!.jwt.sign({ sub: userId, role: 'user' })}` });
  const rows = async (table: string) => (await client!.query(`SELECT * FROM ${table} ORDER BY id`)).rows;
  const markers = async () => (await client!.query('SELECT * FROM data_migrations ORDER BY name')).rows;
  const snapshot = async () => ({
    routes: await rows('routes'), sends: await rows('sends'), comments: await rows('comments'),
    submissions: await rows('route_submissions'), reports: await rows('reports'), markers: await markers()
  });

  async function route(name: string, published = true, grade = 'V2') {
    return (await client!.query<{ id: string }>(
      `INSERT INTO routes(gym_id,route_set_id,name,grade,color,published,created_at)
       VALUES($1,$2,$3,$4,'红色',$5,$6) RETURNING id`, [gymId, setId, name, grade, published, sentAt]
    )).rows[0]!.id;
  }

  async function send(caption: string, status: Status, visibility: Visibility, routeId: string | null = null) {
    return (await client!.query<{ id: string }>(
      `INSERT INTO sends(user_id,route_id,attempts,video_url,image_urls,caption,visibility,
                         moderation_status,sent_at,created_at)
       VALUES($1,$2,3,'https://example.com/original.mp4',ARRAY['https://example.com/original.jpg'],
              $3,$4,$5,$6::timestamptz,$6::timestamptz - interval '1 hour') RETURNING id`,
      [ownerId, routeId, caption, visibility, status, sentAt]
    )).rows[0]!.id;
  }

  async function submission(name: string, options: {
    status?: Status; routeId?: string; video?: boolean; visibility?: Visibility;
  } = {}) {
    return (await client!.query<{ id: string }>(
      `INSERT INTO route_submissions(submitter_id,client_request_id,gym_id,route_set_id,name,
          grade,color,wall_zone,cover_url,video_url,caption,visibility,points,status,
          published_route_id,created_at)
       VALUES($1,$2,$3,$4,$5,'V4','黄色','侧墙','https://example.com/route.jpg',$6,
          '投稿原文',$7,$8,$9,$10,$11) RETURNING id`,
      [ownerId, randomUUID(), gymId, setId, name, options.video === false ? null : 'https://example.com/submission.mp4',
        options.visibility ?? 'friends', JSON.stringify([{ x: .1, y: .9, type: 'start' }, { x: .4, y: .1, type: 'finish' }]),
        options.status ?? 'pending', options.routeId ?? null, sentAt]
    )).rows[0]!.id;
  }

  it('approves every pending moment, check-in and comment while preserving privacy, reports, dates and scores', async () => {
    const publicMoment = await send('公开动态', 'pending', 'public');
    const friendsMoment = await send('岩友动态', 'pending', 'friends');
    const privateMoment = await send('私人动态', 'pending', 'private');
    await send('驳回动态', 'rejected', 'public');
    await send('已通过动态', 'approved', 'public');
    const hiddenRoute = await route('不关联待审投稿的隐藏线路', false);
    await send('隐藏线路待审打卡', 'pending', 'private', hiddenRoute);
    const reportedCheckin = await send('被举报待审打卡', 'pending', 'public', await route('公开线路', true, 'V3'));
    await send('被拒绝打卡', 'rejected', 'public', await route('拒绝记录线路', true, 'V9'));
    for (const status of ['pending', 'approved', 'rejected'] as const) {
      const comment = (await client!.query<{ id: string }>(
        `INSERT INTO comments(send_id,user_id,content,moderation_status,created_at)
         VALUES($1,$2,$3,$4,$5) RETURNING id`, [publicMoment, otherId, status, status, sentAt]
      )).rows[0]!.id;
      await client!.query(
        `INSERT INTO reports(reporter_id,target_type,target_id,reason,status)
         VALUES($1,'comment',$2,'unsafe',$3)`, [ownerId, comment, status]
      );
    }
    await client!.query(
      `INSERT INTO reports(reporter_id,target_type,target_id,reason,status)
       VALUES($1,'send',$2,'unsafe','pending'),($1,'send',$3,'unsafe','approved')`,
      [otherId, reportedCheckin, publicMoment]
    );
    await client!.query('INSERT INTO post_likes(send_id,user_id) VALUES($1,$2)', [reportedCheckin, otherId]);
    await client!.query(
      `INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')`, [ownerId, otherId]
    );
    const before = await snapshot();
    const interactions = (await client!.query('SELECT * FROM post_likes ORDER BY send_id,user_id')).rows;
    await client!.query(schemaSql);
    const after = await snapshot();
    expect(after.sends).toEqual(before.sends.map(row => row.moderation_status === 'pending'
      ? { ...row, moderation_status: 'approved' } : row));
    expect(after.comments).toEqual(before.comments.map(row => row.moderation_status === 'pending'
      ? { ...row, moderation_status: 'approved' } : row));
    expect(after.routes).toEqual(before.routes);
    expect(after.reports).toEqual(before.reports);
    expect((await client!.query('SELECT * FROM post_likes ORDER BY send_id,user_id')).rows).toEqual(interactions);

    expect((await app!.inject({ url: `/api/sends/${publicMoment}` })).statusCode).toBe(200);
    expect((await app!.inject({ url: `/api/sends/${friendsMoment}` })).statusCode).toBe(404);
    expect((await app!.inject({ url: `/api/sends/${friendsMoment}`, headers: headers(otherId) })).statusCode).toBe(200);
    expect((await app!.inject({ url: `/api/sends/${privateMoment}`, headers: headers(otherId) })).statusCode).toBe(404);
    expect((await app!.inject({ url: `/api/sends/${privateMoment}`, headers: headers() })).statusCode).toBe(200);
    const calendar = await app!.inject({ url: `/api/users/me/month-dashboard?month=${month}`, headers: headers() });
    expect(calendar.statusCode).toBe(200);
    expect(calendar.json().days).toEqual([
      { day, gym_name: '历史发布测试岩馆', grade: 'V2', sends: 1 },
      { day, gym_name: '历史发布测试岩馆', grade: 'V3', sends: 1 }
    ]);
    expect(calendar.json().summary).toEqual({ climbing_days: 1, sends: 2, gyms: 1, max_grade: 3, flashes: 0, videos: 2 });
    const ranking = await app!.inject({ url: '/api/rankings/' });
    expect(ranking.statusCode).toBe(200);
    expect(ranking.json().items).toEqual([expect.objectContaining({ user_id: ownerId, send_count: 1, points: 27 })]);

    await client!.query(schemaSql);
    expect(await snapshot()).toEqual(after);
    expect((await app!.inject({ url: '/api/rankings/' })).json()).toEqual(ranking.json());
  });

  it('publishes missing routes and videos, reuses linked routes and check-ins, and never republishes rejected records', async () => {
    const newVideo = await submission('带视频投稿');
    const newRouteOnly = await submission('纯线路投稿', { video: false });
    const linkedHiddenRoute = await route('已关联但隐藏', false);
    const linked = await submission('已有线路待发布', { routeId: linkedHiddenRoute, visibility: 'private' });
    const existingRoute = await route('已有成绩线路', false);
    const existingSend = await send('已有成绩和媒体', 'pending', 'public', existingRoute);
    await submission('已有完攀的投稿', { routeId: existingRoute });
    const rejectedRoute = await route('已拒绝视频线路');
    await send('已拒绝视频', 'rejected', 'private', rejectedRoute);
    await submission('有拒绝视频的待审投稿', { routeId: rejectedRoute });
    const rejectedHidden = await route('拒绝投稿关联的隐藏线路', false);
    await submission('拒绝投稿', { status: 'rejected', routeId: rejectedHidden });
    await submission('已发布投稿', { status: 'approved', routeId: await route('已发布线路') });
    const before = await snapshot();
    await client!.query(schemaSql);
    const after = await snapshot();
    expect(after.routes).toHaveLength(before.routes.length + 2);
    expect(after.sends).toHaveLength(before.sends.length + 2);
    for (const original of before.submissions) {
      const published = after.submissions.find(row => row.id === original.id)!;
      if (original.status !== 'pending') {
        expect(published).toEqual(original);
        continue;
      }
      expect(published).toEqual({
        ...original, status: 'approved', published_route_id: original.published_route_id ?? expect.any(String),
        reviewed_at: expect.any(Date)
      });
      const publishedRoute = after.routes.find(row => row.id === published.published_route_id)!;
      expect(publishedRoute.published).toBe(true);
      if (!original.published_route_id) {
        expect(publishedRoute).toMatchObject({
          gym_id: original.gym_id, route_set_id: original.route_set_id, name: original.name,
          grade: original.grade, color: original.color, wall_zone: original.wall_zone,
          cover_url: original.cover_url, points: original.points, created_at: original.created_at
        });
      }
      if ([newVideo, linked].includes(original.id)) {
        expect(after.sends.find(row => row.route_id === publishedRoute.id)).toMatchObject({
          user_id: original.submitter_id, attempts: 1, video_url: original.video_url,
          caption: original.caption, visibility: original.visibility, moderation_status: 'approved',
          sent_at: original.created_at, created_at: original.created_at
        });
      }
      if (original.id === newRouteOnly) {
        expect(after.sends.some(row => row.route_id === publishedRoute.id)).toBe(false);
      }
    }
    expect(after.routes.find(row => row.id === rejectedHidden)).toEqual(before.routes.find(row => row.id === rejectedHidden));
    for (const original of before.sends) {
      expect(after.sends.find(row => row.id === original.id)).toEqual(original.id === existingSend
        ? { ...original, moderation_status: 'approved' } : original);
    }
    expect(after.reports).toEqual(before.reports);
    await client!.query(schemaSql);
    expect(await snapshot()).toEqual(after);

    // A later explicit moderation action must not be undone by application restarts.
    await client!.query("UPDATE sends SET moderation_status='pending' WHERE id=$1", [existingSend]);
    await client!.query("UPDATE route_submissions SET status='pending' WHERE id=$1", [newVideo]);
    await client!.query(
      `INSERT INTO comments(send_id,user_id,content,moderation_status) VALUES($1,$2,'后来送审的评论','pending')`,
      [existingSend, otherId]
    );
    const later = await snapshot();
    await client!.query(schemaSql);
    expect(await snapshot()).toEqual(later);
  });

  it('rolls back the marker and every publication if any migration step fails, then retries successfully', async () => {
    await submission('需要原子发布的投稿');
    const moment = await send('原子更新动态', 'pending', 'public');
    await client!.query(
      `INSERT INTO comments(send_id,user_id,content,moderation_status) VALUES($1,$2,'原子更新评论','pending')`,
      [moment, otherId]
    );
    const before = await snapshot();
    await client!.query(`
      CREATE FUNCTION fail_comment_publication() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'migration atomicity test'; END $$;
      CREATE TRIGGER fail_comment_publication BEFORE UPDATE ON comments
      FOR EACH ROW EXECUTE FUNCTION fail_comment_publication();
    `);
    try {
      await expect(client!.query(schemaSql)).rejects.toThrow('migration atomicity test');
      expect(await snapshot()).toEqual(before);
    } finally {
      await client!.query('DROP TRIGGER fail_comment_publication ON comments; DROP FUNCTION fail_comment_publication()');
    }
    await client!.query(schemaSql);
    const after = await snapshot();
    expect(after.routes).toHaveLength(before.routes.length + 1);
    expect(after.sends).toHaveLength(before.sends.length + 1);
    expect(after.submissions[0]).toMatchObject({ status: 'approved', published_route_id: expect.any(String) });
    expect(after.comments[0]).toMatchObject({ moderation_status: 'approved' });
    expect(after.markers.filter(row => row.name === marker)).toHaveLength(1);
  });

  it('defaults new submissions to approved after upgrading without changing report or explicit pending defaults', async () => {
    await client!.query("ALTER TABLE route_submissions ALTER COLUMN status SET DEFAULT 'pending'");
    await client!.query(schemaSql);
    const inserted = (await client!.query(
      `INSERT INTO route_submissions(submitter_id,gym_id,name,grade,color)
       VALUES($1,$2,'默认立即通过','V1','红色') RETURNING status`, [ownerId, gymId]
    )).rows[0]!;
    expect(inserted.status).toBe('approved');
    const explicitPending = await submission('显式历史待审');
    expect((await client!.query('SELECT status FROM route_submissions WHERE id=$1', [explicitPending])).rows[0]!.status).toBe('pending');
    const report = (await client!.query(
      `INSERT INTO reports(reporter_id,target_type,target_id,reason)
       VALUES($1,'user',$2,'unsafe') RETURNING status`, [otherId, ownerId]
    )).rows[0]!;
    expect(report.status).toBe('pending');
  });

  it('serializes concurrent migration connections without creating duplicate routes or videos', async () => {
    await submission('并发启动只发布一次');
    const migrationStart = schemaSql.indexOf('DO $publish_pending_content$');
    expect(migrationStart).toBeGreaterThan(0);
    const migrationSql = schemaSql.slice(migrationStart);
    const peer = new pg.Client(config.DATABASE_URL ? { connectionString: config.DATABASE_URL } : {
      host: config.PGHOST, port: config.PGPORT, database: config.PGDATABASE,
      user: config.PGUSER, password: config.PGPASSWORD
    });
    let transactionOpen = false;
    let concurrentReplay: Promise<pg.QueryResult> | undefined;
    await peer.connect();
    try {
      await peer.query(`SET search_path TO "${schema}",public`);
      const peerId = (await peer.query<{ id: number }>('SELECT pg_backend_pid() AS id')).rows[0]!.id;
      await client!.query('BEGIN');
      transactionOpen = true;
      await client!.query(migrationSql);
      const once = await snapshot();
      concurrentReplay = peer.query(migrationSql);
      // The second application startup must wait for the first marker's commit.
      await vi.waitFor(async () => {
        const waiting = await client!.query<{ blocked: boolean }>(
          'SELECT pg_backend_pid() = ANY(pg_blocking_pids($1::integer)) AS blocked', [peerId]
        );
        expect(waiting.rows[0]!.blocked).toBe(true);
      }, { timeout: 2000, interval: 10 });
      await client!.query('COMMIT');
      transactionOpen = false;
      await concurrentReplay;
      expect(await snapshot()).toEqual(once);
      expect(once.routes).toHaveLength(1);
      expect(once.sends).toHaveLength(1);
      expect(once.markers.filter(row => row.name === marker)).toHaveLength(1);
    } finally {
      if (transactionOpen) await client!.query('ROLLBACK');
      if (concurrentReplay) await Promise.resolve(concurrentReplay).catch(() => undefined);
      await peer.end();
    }
  });
});
