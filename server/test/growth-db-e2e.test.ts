import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

const database = vi.hoisted(() => ({ query: vi.fn(), transaction: vi.fn() }));
vi.mock('../src/db.js', () => database);
import { config } from '../src/config.js';
import { authPlugin } from '../src/auth.js';
import { growthRoutes } from '../src/routes/growth.js';
import { sendRoutes } from '../src/routes/sends.js';
import { submissionRoutes } from '../src/routes/submissions.js';
import { userRoutes } from '../src/routes/users.js';
import { adminRoutes } from '../src/routes/admin.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;
type Viewer = { id: string; headers: { authorization: string } };
suite('account badges with isolated local PostgreSQL', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let bootstrap: pg.Client;
  let schemaCreated = false;
  const schema = `growth_test_${randomUUID().replaceAll('-', '')}`;
  let owner: Viewer;
  let stranger: Viewer;
  let admin: Viewer;
  let gymId: string;
  let routeId: string;

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) throw new Error('Growth E2E requires a dedicated local test/e2e/CI database');
    const connection = config.DATABASE_URL ? { connectionString: config.DATABASE_URL } : {
      host: config.PGHOST, port: config.PGPORT, database: config.PGDATABASE, user: config.PGUSER, password: config.PGPASSWORD
    };
    bootstrap = new pg.Client(connection);
    await bootstrap.connect();
    await bootstrap.query(`CREATE SCHEMA "${schema}"`);
    schemaCreated = true;
    pool = new pg.Pool({ ...connection, max: 12, options: `-c search_path=${schema},public` });
    const migration = await readFile(new URL('../src/db/schema.sql', import.meta.url), 'utf8');
    await pool.query(migration);
    await pool.query(migration);
    database.query.mockImplementation((sql: string, values: unknown[] = []) => pool.query(sql, values));
    database.transaction.mockImplementation(async (callback) => {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const result = await callback(client);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally { client.release(); }
    });
    app = Fastify();
    await app.register(sensible);
    app.setErrorHandler((error, _request, reply) => {
      if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
      return reply.status(error.statusCode ?? 500).send({ code: error.code, message: error.message });
    });
    await app.register(authPlugin);
    await app.register(growthRoutes, { prefix: '/api' });
    await app.register(sendRoutes, { prefix: '/api/sends' });
    await app.register(submissionRoutes, { prefix: '/api/submissions' });
    await app.register(userRoutes, { prefix: '/api/users' });
    await app.register(adminRoutes, { prefix: '/api/admin' });
    await app.ready();
  });
  beforeEach(async () => {
    await pool.query('TRUNCATE users,gyms CASCADE');
    async function user(role = 'user'): Promise<Viewer> {
      const id = (await pool.query<{ id: string }>(
        'INSERT INTO users(openid,nickname,role) VALUES($1,$2,$3) RETURNING id', [`growth:${randomUUID()}`, '徽章测试岩友', role]
      )).rows[0]!.id;
      return { id, headers: { authorization: `Bearer ${app.jwt.sign({ sub: id, role })}` } };
    }
    owner = await user(); stranger = await user(); admin = await user('admin');
    gymId = (await pool.query<{ id: string }>("INSERT INTO gyms(name,city,address) VALUES('徽章隔离岩馆','深圳市','测试地址') RETURNING id")).rows[0]!.id;
    routeId = (await pool.query<{ id: string }>("INSERT INTO routes(gym_id,name,grade,color) VALUES($1,'测试线路','V2','珊瑚') RETURNING id", [gymId])).rows[0]!.id;
  });
  afterAll(async () => {
    if (app) await app.close();
    if (pool) await pool.end();
    if (bootstrap && schemaCreated) await bootstrap.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (bootstrap) await bootstrap.end();
  });
  const get = (path: string, viewer = owner) => app.inject({ url: `/api/${path}`, headers: viewer.headers });
  const post = (path: string, payload: Record<string, unknown> = {}, viewer = owner) => app.inject({ method: 'POST', url: `/api/${path}`, payload, headers: viewer.headers });
  const record = (payload: Record<string, unknown> = {}) => post('sends', { routeId, clientRequestId: randomUUID(), operation: 'record', ...payload });
  const consume = () => post('users/me/growth-presentations/consume');
  const remove = (sendId: string) => app.inject({ method: 'DELETE', url: `/api/sends/${sendId}`, headers: owner.headers });
  async function count(table: string) {
    return (await pool.query<{ n: number }>(`SELECT count(*)::int n FROM ${table} WHERE user_id=$1`, [owner.id])).rows[0]!.n;
  }
  async function legacy(routes: number, days: number) {
    const sends = [];
    for (let i = 0; i < routes; i++) {
      const id = (await pool.query<{ id: string }>("INSERT INTO routes(gym_id,name,grade,color) VALUES($1,$2,'V1','薄荷') RETURNING id", [gymId, `历史线路${i}`])).rows[0]!.id;
      sends.push((await pool.query<{ id: string; route_id: string }>(
        `INSERT INTO sends(user_id,route_id,attempts,visibility,moderation_status,sent_at)
         VALUES($1,$2,1,'private','approved','2025-01-01T15:59:00Z'::timestamptz+$3::int*interval '1 day') RETURNING id,route_id`,
        [owner.id, id, i % days]
      )).rows[0]!);
    }
    return sends;
  }

  it('gates private growth and consume, while config accepts guests and rejects supplied invalid tokens', async () => {
    const configResponse = await app.inject({ url: '/api/growth/config' });
    expect(configResponse.statusCode).toBe(200);
    expect(configResponse.json()).toMatchObject({ rulesVersion: 'wanpan-growth-v1', timezone: 'Asia/Shanghai' });
    expect(configResponse.json().levels).toHaveLength(11);
    for (const path of ['users/me/growth-level', 'users/me/badges']) {
      expect((await app.inject({ url: `/api/${path}` })).statusCode).toBe(401);
      expect((await app.inject({ url: `/api/${path}`, headers: { authorization: 'Bearer invalid' } })).statusCode).toBe(401);
    }
    expect((await app.inject({ method: 'POST', url: '/api/users/me/growth-presentations/consume', payload: {} })).statusCode).toBe(401);
    expect((await app.inject({ url: '/api/growth/config', headers: { authorization: 'Bearer invalid' } })).statusCode).toBe(401);
    expect((await post('users/me/growth-presentations/consume', { userId: stranger.id })).statusCode).toBe(400);
  });

  it('starts at Lv.0 without a badge and excludes moments and non-video submissions', async () => {
    const growth = await get('users/me/growth-level');
    expect(growth.json()).toMatchObject({ currentLevel: 0, levelName: '新岩友', climbingDays: 0, uniqueRoutes: 0, backfillStatus: 'complete', remainingDays: 1, remainingRoutes: 1 });
    const badges = (await get('users/me/badges')).json().badges;
    expect(badges).toHaveLength(10);
    expect(badges.every((badge: { status: string }) => badge.status === 'locked')).toBe(true);
    expect((await post('sends/moments', { caption: '日常记录' })).statusCode).toBe(200);
    expect((await post('submissions', { gymId, name: '无视频投稿', grade: 'V3', color: '紫', clientRequestId: randomUUID() })).statusCode).toBe(200);
    expect((await get('users/me/growth-level')).json().currentLevel).toBe(0);
    expect(await count('climbing_facts')).toBe(0);
    expect((await consume()).json().shouldPresent).toBe(false);
  });

  it('awards the first private check-in and ignores client date claims', async () => {
    const response = await record({ visibility: 'private', localDate: '1999-01-01' });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ moderationStatus: 'approved', milestone: { type: 'first_grade', grade: 'V2' }, growth: { currentLevel: 1, climbingDays: 1, uniqueRoutes: 1 } });
    const fact = (await pool.query("SELECT local_date::text date,(now() AT TIME ZONE 'Asia/Shanghai')::date::text today FROM climbing_facts WHERE user_id=$1", [owner.id])).rows[0]!;
    expect(fact.date).toBe(fact.today);
    expect((await get('users/me/growth-level', stranger)).json().currentLevel).toBe(0);
    expect((await app.inject({ url: '/api/sends/feed' })).json().items).toHaveLength(0);
    const awarded = await consume();
    expect(awarded.json()).toMatchObject({ shouldPresent: true, presentation: { fromLevel: 0, toLevel: 1, badgeKeys: ['account-level-01'], newBadgeCount: 1 } });
    expect((await consume()).json().shouldPresent).toBe(false);
  });

  it('backfills surviving approved sends once and merges multiple historical badges', async () => {
    const history = await legacy(25, 7);
    await pool.query("INSERT INTO sends(user_id,route_id,moderation_status,sent_at) VALUES($1,$2,'rejected','2024-01-01')", [owner.id, routeId]);
    await pool.query('UPDATE routes SET published=false WHERE id=$1', [history[0]!.route_id]);
    const before = (await get('users/me/growth-level')).json();
    expect(before).toMatchObject({ currentLevel: 3, climbingDays: 7, uniqueRoutes: 25 });
    expect(await count('climbing_facts')).toBe(25);
    expect((await get('users/me/growth-level')).json()).toEqual(before);
    await pool.query("UPDATE user_growth SET backfill_status='pending' WHERE user_id=$1", [owner.id]);
    expect((await get('users/me/growth-level')).json()).toEqual(before);
    expect(await count('climbing_facts')).toBe(25);
    const result = (await consume()).json();
    expect(result.presentation).toMatchObject({ fromLevel: 0, toLevel: 3, newBadgeCount: 3 });
    expect(result.presentation.badgeKeys).toEqual(['account-level-01', 'account-level-02', 'account-level-03']);
  });

  it('captures the old date before a new client upserts the same route', async () => {
    const [old] = await legacy(1, 1);
    const response = await record({ routeId: old!.route_id });
    expect(response.json().growth).toMatchObject({ climbingDays: 2, uniqueRoutes: 1, currentLevel: 1 });
    const facts = await pool.query('SELECT local_date::text date,source_kind FROM climbing_facts WHERE user_id=$1 ORDER BY occurred_at', [owner.id]);
    expect(facts.rows[0]).toEqual({ date: '2025-01-01', source_kind: 'legacy_backfill' });
    expect(facts.rowCount).toBe(2);
  });

  it('serializes concurrent duplicate requests and returns a saved result after simulated midnight', async () => {
    const clientRequestId = randomUUID();
    const responses = await Promise.all(Array.from({ length: 8 }, () => record({ clientRequestId })));
    expect(responses.every((result) => result.statusCode === 200)).toBe(true);
    for (const response of responses) expect(response.json()).toEqual(responses[0]!.json());
    expect(await count('climbing_facts')).toBe(1);
    expect(await count('growth_requests')).toBe(1);
    expect(await count('user_badges')).toBe(1);
    await pool.query("UPDATE climbing_facts SET occurred_at='2025-03-03T15:59:00Z',local_date='2025-03-03' WHERE user_id=$1", [owner.id]);
    const retry = await record({ clientRequestId });
    expect(retry.json()).toEqual(responses[0]!.json());
    expect((await pool.query('SELECT local_date::text date FROM climbing_facts WHERE user_id=$1', [owner.id])).rows[0]!.date).toBe('2025-03-03');
    const conflict = await record({ clientRequestId, attempts: 2 });
    expect(conflict.statusCode).toBe(409);
    expect(conflict.json().code).toBe('IDEMPOTENCY_KEY_REUSED');
    expect(await count('climbing_facts')).toBe(1);
  });

  it('counts same-day routes and same-route events correctly and consumes on only one device', async () => {
    const anotherRoute = (await pool.query<{ id: string }>("INSERT INTO routes(gym_id,name,grade,color) VALUES($1,'另一条','V1','蓝') RETURNING id", [gymId])).rows[0]!.id;
    const responses = await Promise.all([record(), record(), record({ routeId: anotherRoute })]);
    expect(responses.every((result) => result.statusCode === 200)).toBe(true);
    expect((await get('users/me/growth-level')).json()).toMatchObject({ climbingDays: 1, uniqueRoutes: 2, currentLevel: 1 });
    expect(await count('climbing_facts')).toBe(3);
    expect(await count('user_badges')).toBe(1);
    const presentations = await Promise.all(Array.from({ length: 6 }, () => consume()));
    expect(presentations.filter((response) => response.json().shouldPresent)).toHaveLength(1);
  });

  it('conservatively preserves the historical day for old-client repeated routes', async () => {
    const [old] = await legacy(1, 1);
    for (let i = 0; i < 2; i++) expect((await post('sends', { routeId: old!.route_id, caption: `重复${i}` })).statusCode).toBe(200);
    const growth = (await get('users/me/growth-level')).json();
    expect(growth).toMatchObject({ climbingDays: 1, uniqueRoutes: 1 });
    expect(await count('climbing_facts')).toBe(1);
    expect((await pool.query('SELECT local_date::text date FROM climbing_facts WHERE user_id=$1', [owner.id])).rows[0]!.date).toBe('2025-01-01');
  });

  it('edits content without adding a day or moving sent_at, and does not create missing edits', async () => {
    const [old] = await legacy(1, 1);
    const original = (await pool.query('SELECT sent_at FROM sends WHERE id=$1', [old!.id])).rows[0]!.sent_at;
    const edit = await record({ routeId: old!.route_id, operation: 'edit', caption: '只修改文案', visibility: 'friends' });
    expect(edit.statusCode).toBe(200);
    expect(edit.json().milestone).toBeNull();
    expect(edit.json().growth).toMatchObject({ climbingDays: 1, uniqueRoutes: 1 });
    expect((await pool.query('SELECT sent_at FROM sends WHERE id=$1', [old!.id])).rows[0]!.sent_at).toEqual(original);
    expect(await count('climbing_facts')).toBe(1);
    expect((await record({ operation: 'edit' })).statusCode).toBe(404);
    expect((await pool.query('SELECT id FROM sends WHERE user_id=$1', [owner.id])).rowCount).toBe(1);
  });

  it('invalidates pending upper badges after deletion and restores an earned badge without another celebration', async () => {
    const history = await legacy(8, 3);
    expect((await get('users/me/growth-level')).json().currentLevel).toBe(2);
    expect((await remove(history[7]!.id)).statusCode).toBe(200);
    const pending = (await consume()).json();
    expect(pending.presentation).toMatchObject({ toLevel: 1, newBadgeCount: 1, badgeKeys: ['account-level-01'] });
    const before = (await get('users/me/badges')).json().badges[0].earnedAt;
    for (const item of history.slice(0, 7)) expect((await remove(item.id)).statusCode).toBe(200);
    expect((await consume()).json().shouldPresent).toBe(false);
    expect((await get('users/me/growth-level')).json().currentLevel).toBe(0);
    expect((await get('users/me/badges')).json().badges[0].status).toBe('revoked');
    const restored = await record({ routeId: history[0]!.route_id });
    expect(restored.json().growth.currentLevel).toBe(1);
    const after = (await get('users/me/badges')).json().badges[0];
    expect(after).toMatchObject({ status: 'earned', earnedAt: before });
    expect((await consume()).json().shouldPresent).toBe(false);
    expect(await count('user_badges')).toBe(2);
    expect((await pool.query("SELECT action FROM growth_audit WHERE user_id=$1 AND action='restored'", [owner.id])).rowCount).toBe(1);
  });

  it('does not recreate a deleted check-in from a lost-response retry', async () => {
    const clientRequestId = randomUUID();
    const first = await record({ clientRequestId });
    expect((await remove(first.json().sendId)).statusCode).toBe(200);
    const retry = await record({ clientRequestId });
    expect(retry.statusCode).toBe(200);
    expect(retry.json().sendId).toBe(first.json().sendId);
    expect(await count('sends')).toBe(0);
    expect((await get('users/me/growth-level')).json().currentLevel).toBe(0);
    expect((await consume()).json().shouldPresent).toBe(false);
    await pool.query("UPDATE user_growth SET backfill_status='pending' WHERE user_id=$1", [owner.id]);
    expect((await get('users/me/growth-level')).json().currentLevel).toBe(0);
  });

  it('restricts administrative invalidation, audits it, and invalidates an unshown award', async () => {
    const first = await record();
    const path = `admin/growth/sends/${first.json().sendId}/invalidate`;
    expect((await post(path, { reason: '确认误记' })).statusCode).toBe(403);
    expect((await post(path, { reason: '' }, admin)).statusCode).toBe(400);
    const invalidated = await post(path, { reason: '确认误记' }, admin);
    expect(invalidated.statusCode).toBe(200);
    expect(invalidated.json()).toMatchObject({ invalidated: true, growth: { currentLevel: 0 } });
    expect((await consume()).json().shouldPresent).toBe(false);
    expect((await pool.query("SELECT actor_id,reason FROM growth_audit WHERE user_id=$1 AND action='fact_invalidated'", [owner.id])).rows)
      .toEqual([{ actor_id: admin.id, reason: '确认误记' }]);
    expect((await app.inject({ url: '/api/sends/feed' })).json().items).toHaveLength(0);
  });

  it('preserves facts when a route naturally disappears and clears all growth data on account deletion', async () => {
    await record();
    await pool.query('DELETE FROM routes WHERE id=$1', [routeId]);
    expect(await count('sends')).toBe(0);
    expect((await get('users/me/growth-level')).json()).toMatchObject({ currentLevel: 1, uniqueRoutes: 1 });
    const fact = (await pool.query('SELECT source_send_id,source_route_id,route_identity,status FROM climbing_facts WHERE user_id=$1', [owner.id])).rows[0];
    expect(fact).toEqual({ source_send_id: null, source_route_id: null, route_identity: routeId, status: 'valid' });
    const deleted = await app.inject({ method: 'DELETE', url: '/api/users/me', headers: owner.headers });
    expect(deleted.statusCode).toBe(200);
    for (const table of ['user_growth', 'climbing_facts', 'user_badges', 'growth_requests', 'growth_presentations', 'growth_audit']) expect(await count(table)).toBe(0);
    expect((await get('users/me/growth-level')).statusCode).toBe(401);
  });

  it('integrates video submissions, rejects changed payloads, and shares request IDs across write endpoints', async () => {
    const clientRequestId = randomUUID();
    const body = { gymId, name: '附视频的投稿', grade: 'V3', color: '紫色', videoUrl: 'https://example.com/climb.mp4', clientRequestId };
    const results = await Promise.all([post('submissions', body), post('submissions', body)]);
    expect(results.every((item) => item.statusCode === 200)).toBe(true);
    expect(results[1]!.json()).toEqual(results[0]!.json());
    expect(results[0]!.json()).toMatchObject({ status: 'approved', send_moderation_status: 'approved', growth: { currentLevel: 1, uniqueRoutes: 1 } });
    expect(await count('climbing_facts')).toBe(1);
    expect((await post('submissions', { ...body, name: '篡改标题' })).statusCode).toBe(409);
    expect((await record({ clientRequestId })).statusCode).toBe(409);
    const sendId = results[0]!.json().send_id;
    await remove(sendId);
    expect((await post('submissions', body)).statusCode).toBe(200);
    expect(await count('sends')).toBe(0);
    expect((await consume()).json().shouldPresent).toBe(false);
  });

  it('recovers request identity from a pre-growth submission and rejects changed legacy payloads', async () => {
    const clientRequestId = randomUUID();
    const body = { gymId, name: '兼容历史投稿', grade: 'V1', color: '薄荷', clientRequestId };
    const first = await post('submissions', body);
    expect(first.statusCode).toBe(200);
    await pool.query('DELETE FROM growth_requests WHERE user_id=$1', [owner.id]);
    await pool.query('UPDATE route_submissions SET request_hash=NULL WHERE id=$1', [first.json().id]);
    const changed = await post('submissions', { ...body, color: '红色' });
    expect(changed.statusCode).toBe(409);
    const retry = await post('submissions', { ...body, routeSetId: null, wallZone: null, coverUrl: null, videoUrl: null, caption: null });
    expect(retry.statusCode).toBe(200);
    expect(retry.json().id).toBe(first.json().id);
    expect(retry.json().published_route_id).toBe(first.json().published_route_id);
    expect((await pool.query('SELECT id FROM route_submissions WHERE submitter_id=$1', [owner.id])).rowCount).toBe(1);
    expect(await count('climbing_facts')).toBe(0);
  });

  it('adds a historical day only after pending check-in approval and includes legacy submission videos', async () => {
    await get('users/me/growth-level');
    const pending = (await pool.query<{ id: string }>(
      `INSERT INTO sends(user_id,route_id,moderation_status,sent_at) VALUES($1,$2,'pending','2025-02-01T16:01:00Z') RETURNING id`,
      [owner.id, routeId]
    )).rows[0]!;
    expect((await get('users/me/growth-level')).json().currentLevel).toBe(0);
    expect((await post(`admin/moderation/${pending.id}`, { targetType: 'send', action: 'approve' }, admin)).statusCode).toBe(200);
    expect((await get('users/me/growth-level')).json()).toMatchObject({ currentLevel: 1, climbingDays: 1, uniqueRoutes: 1 });
    expect((await pool.query('SELECT local_date::text date FROM climbing_facts WHERE source_send_id=$1', [pending.id])).rows[0]!.date).toBe('2025-02-02');
    const submission = (await pool.query<{ id: string }>(
      `INSERT INTO route_submissions(submitter_id,gym_id,name,grade,color,video_url,status,created_at)
       VALUES($1,$2,'历史视频线路','V3','金','https://example.com/old.mp4','pending','2025-02-03T15:00:00Z') RETURNING id`,
      [owner.id, gymId]
    )).rows[0]!;
    expect((await post(`submissions/${submission.id}/review`, { action: 'approve' }, admin)).statusCode).toBe(200);
    expect((await get('users/me/growth-level')).json()).toMatchObject({ currentLevel: 1, climbingDays: 2, uniqueRoutes: 2 });
    expect((await pool.query("SELECT local_date::text date FROM climbing_facts WHERE source_kind='submission_video' AND user_id=$1", [owner.id])).rows[0]!.date).toBe('2025-02-03');
  });

  it('serializes deletion against consumption and never consumes a revoked badge afterward', async () => {
    const first = await record();
    const [deleted, presented] = await Promise.all([remove(first.json().sendId), consume()]);
    expect(deleted.statusCode).toBe(200);
    expect(presented.statusCode).toBe(200);
    // Either transaction can win; any successful consumption must precede revocation.
    const state = (await pool.query('SELECT status,consumed_at,invalidated_at FROM growth_presentations WHERE user_id=$1 ORDER BY created_at', [owner.id])).rows;
    const revokedAt = (await pool.query('SELECT revoked_at FROM user_badges WHERE user_id=$1', [owner.id])).rows[0]!.revoked_at;
    for (const item of state) if (item.status === 'consumed') expect(item.consumed_at.getTime()).toBeLessThanOrEqual(revokedAt.getTime());
    expect((await consume()).json()).toMatchObject({ shouldPresent: false, growth: { currentLevel: 0 }, presentation: null });
  });

  it('rolls back business records and awards together when fact persistence fails', async () => {
    await get('users/me/growth-level');
    await pool.query(`CREATE FUNCTION fail_growth_fact() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test fact failure'; END $$`);
    await pool.query('CREATE TRIGGER fail_growth_fact BEFORE INSERT ON climbing_facts FOR EACH ROW EXECUTE FUNCTION fail_growth_fact()');
    try {
      expect((await record()).statusCode).toBe(500);
      expect(await count('sends')).toBe(0);
      expect(await count('climbing_facts')).toBe(0);
      expect(await count('growth_requests')).toBe(0);
      expect(await count('user_badges')).toBe(0);
    } finally {
      await pool.query('DROP TRIGGER fail_growth_fact ON climbing_facts');
      await pool.query('DROP FUNCTION fail_growth_fact()');
    }
  });
});
