import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

// All application queries and schema migrations share this isolated connection.
// Replaying schema.sql here cannot publish another suite's pending fixtures.
const database = vi.hoisted(() => ({ query: vi.fn(), transaction: vi.fn() }));
vi.mock('../src/db.js', () => database);

import { config } from '../src/config.js';
import { authPlugin } from '../src/auth.js';
import { userRoutes } from '../src/routes/users.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;

suite('legacy check-in publication migration with isolated local PostgreSQL', () => {
  let app: FastifyInstance | undefined;
  let client: pg.Client | undefined;
  let schemaCreated = false;
  let schemaSql = '';
  const schema = `send_migration_test_${randomUUID().replaceAll('-', '')}`;

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) {
      throw new Error('Send migration E2E requires a dedicated local test/e2e/CI database');
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
    // Simulate upgrading a database where this data repair has never run.
    await client.query("DELETE FROM data_migrations WHERE name='route_checkins_publish_immediately_v1'");
    database.query.mockImplementation((sql: string, values: unknown[] = []) => client!.query(sql, values));
    app = Fastify();
    await app.register(sensible);
    await app.register(authPlugin);
    await app.register(userRoutes, { prefix: '/api/users' });
    await app.ready();
  });

  afterAll(async () => {
    if (app) await app.close();
    if (client && schemaCreated) await client.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (client) await client.end();
  });

  it('counts the saved V2 on its original day and preserves excluded records across reruns', async () => {
    const ownerId = randomUUID();
    const otherId = randomUUID();
    await client!.query(
      `INSERT INTO users(id,openid) VALUES($1::uuid,$1::uuid::text),($2::uuid,$2::uuid::text)`, [ownerId, otherId]
    );
    const gymId = randomUUID();
    await client!.query(
      `INSERT INTO gyms(id,name,city,address) VALUES($1,'迁移测试岩馆','上海','测试地址')`, [gymId]
    );
    // Shanghai 00:05 on this month's first day is still the previous UTC day.
    const dates = await client!.query<{ sent_at: Date; day: string; month: string }>(
      `SELECT (date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') + interval '5 minutes')
                AT TIME ZONE 'Asia/Shanghai' sent_at,
              to_char(now() AT TIME ZONE 'Asia/Shanghai','YYYY-MM-01') AS "day",
              to_char(now() AT TIME ZONE 'Asia/Shanghai','YYYY-MM') AS "month"`
    );
    const { sent_at: sentAt, day, month } = dates.rows[0]!;
    const fixtures = [
      { name: 'eligible', grade: 'V2', status: 'pending', published: true, visibility: 'friends', userId: ownerId },
      { name: 'rejected', grade: 'V9', status: 'rejected', published: true, visibility: 'public', userId: ownerId },
      { name: 'unpublished', grade: 'V10', status: 'pending', published: false, visibility: 'public', userId: ownerId },
      { name: 'pending-report', grade: 'V11', status: 'pending', published: true, visibility: 'public', userId: ownerId },
      { name: 'upheld-report', grade: 'V12', status: 'pending', published: true, visibility: 'public', userId: ownerId },
      { name: 'dismissed-report', grade: 'V3', status: 'pending', published: true, visibility: 'private', userId: otherId },
      { name: 'approved', grade: 'V4', status: 'approved', published: true, visibility: 'private', userId: otherId }
    ];
    const ids = new Map<string, string>();
    for (const fixture of fixtures) {
      const routeId = randomUUID();
      const sendId = randomUUID();
      ids.set(fixture.name, sendId);
      await client!.query(
        `INSERT INTO routes(id,gym_id,name,grade,color,published) VALUES($1,$2,$3,$4,'红色',$5)`,
        [routeId, gymId, fixture.name, fixture.grade, fixture.published]
      );
      await client!.query(
        `INSERT INTO sends(id,user_id,route_id,attempts,video_url,caption,visibility,moderation_status,sent_at,created_at)
         VALUES($1,$2,$3,2,'https://example.com/existing.mp4','原来的完攀记录',$4,$5,$6,$6)`,
        [sendId, fixture.userId, routeId, fixture.visibility, fixture.status, sentAt]
      );
    }
    await client!.query(
      `INSERT INTO sends(user_id,caption,moderation_status,sent_at)
       VALUES($1,'没有关联线路的动态','pending',$2)`, [ownerId, sentAt]
    );
    for (const [fixture, status] of [
      ['pending-report', 'pending'], ['upheld-report', 'approved'], ['dismissed-report', 'rejected']
    ]) {
      await client!.query(
        `INSERT INTO reports(reporter_id,target_type,target_id,reason,status) VALUES($1,'send',$2,'unsafe',$3)`,
        [otherId, ids.get(fixture!), status]
      );
    }
    const headers = { authorization: `Bearer ${app!.jwt.sign({ sub: ownerId, role: 'user' })}` };
    const beforeProfile = await app!.inject({ url: '/api/users/me', headers });
    expect(beforeProfile.statusCode).toBe(200);
    expect(beforeProfile.json().stats).toMatchObject({ total_sends: 0, monthly_sends: 0, gym_count: 0 });
    const before = (await client!.query('SELECT * FROM sends ORDER BY id')).rows;
    const reportsBefore = (await client!.query('SELECT * FROM reports ORDER BY id')).rows;

    await client!.query(schemaSql);

    const approvedIds = new Set([ids.get('eligible'), ids.get('dismissed-report')]);
    const after = (await client!.query('SELECT * FROM sends ORDER BY id')).rows;
    expect(after).toEqual(before.map((row) => approvedIds.has(row.id)
      ? { ...row, moderation_status: 'approved' } : row));
    expect((await client!.query('SELECT * FROM reports ORDER BY id')).rows).toEqual(reportsBefore);
    const profile = await app!.inject({ url: '/api/users/me', headers });
    expect(profile.statusCode).toBe(200);
    expect(profile.json().stats).toEqual({
      total_sends: 1, monthly_sends: 1, gym_count: 1, max_grade: 2, monthly_max_grade: 2
    });
    const calendar = await app!.inject({ url: `/api/users/me/month-dashboard?month=${month}`, headers });
    expect(calendar.statusCode).toBe(200);
    expect(calendar.json()).toMatchObject({
      days: [{ day, gym_name: '迁移测试岩馆', grade: 'V2', sends: 1 }],
      summary: { climbing_days: 1, sends: 1, gyms: 1, max_grade: 2, flashes: 0, videos: 1 }
    });

    // A later moderation action must survive future application startups.
    await client!.query("UPDATE sends SET moderation_status='pending' WHERE id=$1", [ids.get('eligible')]);
    const beforeRepeat = (await client!.query('SELECT * FROM sends ORDER BY id')).rows;
    const markers = (await client!.query('SELECT * FROM data_migrations ORDER BY name')).rows;
    await client!.query(schemaSql);
    expect((await client!.query('SELECT * FROM sends ORDER BY id')).rows).toEqual(beforeRepeat);
    expect((await client!.query('SELECT * FROM data_migrations ORDER BY name')).rows).toEqual(markers);
    expect((await client!.query('SELECT * FROM reports ORDER BY id')).rows).toEqual(reportsBefore);
  });
});
