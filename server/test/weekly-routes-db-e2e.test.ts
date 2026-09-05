import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

// Keep the actual route/auth SQL on one PostgreSQL connection in an isolated
// schema, so nationwide queries cannot see another test suite's fixtures.
const database = vi.hoisted(() => ({ query: vi.fn() }));
vi.mock('../src/db.js', () => ({ query: database.query }));

import { config } from '../src/config.js';
import { authPlugin } from '../src/auth.js';
import { routeRoutes } from '../src/routes/routes.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;
const now = '2026-09-07T04:00:00.000Z';
const weekStart = '2026-09-06T16:00:00.000Z';

suite('weekly routes with isolated local PostgreSQL', () => {
  let app: FastifyInstance | undefined;
  let client: pg.Client | undefined;
  let schemaCreated = false;
  const schema = `weekly_routes_test_${randomUUID().replaceAll('-', '')}`;
  let shanghaiGym = '';
  let beijingGym = '';

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) {
      throw new Error('Weekly routes E2E requires a dedicated local test/e2e/CI database');
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
    await client.query(await readFile(new URL('../src/db/schema.sql', import.meta.url), 'utf8'));
    database.query.mockImplementation((sql: string, values: unknown[] = []) => client!.query(sql, values));

    app = Fastify();
    await app.register(sensible);
    app.setErrorHandler((error, _request, reply) => {
      if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
      return reply.send(error);
    });
    await app.register(authPlugin);
    await app.register(routeRoutes, { prefix: '/api/routes' });
    await app.ready();
  });

  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(now));
    await client!.query(`TRUNCATE "${schema}".gyms CASCADE`);
    const gyms = await client!.query<{ id: string; city: string }>(
      `INSERT INTO gyms(name,city,address) VALUES
         ('上海测试岩馆','上海','上海测试地址'),('北京测试岩馆','北京','北京测试地址')
       RETURNING id,city`
    );
    shanghaiGym = gyms.rows.find((gym) => gym.city === '上海')!.id;
    beijingGym = gyms.rows.find((gym) => gym.city === '北京')!.id;
  });

  afterEach(() => vi.useRealTimers());

  afterAll(async () => {
    if (app) await app.close();
    if (client && schemaCreated) await client.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (client) await client.end();
  });

  async function route(
    name: string, createdAt: string,
    { gymId = shanghaiGym, published = true, routeSetId = null as string | null, id = randomUUID() } = {}
  ) {
    await client!.query(
      `INSERT INTO routes(id,gym_id,route_set_id,name,grade,color,cover_url,created_at,published)
       VALUES($1,$2,$3,$4,'V3','蓝色','https://example.com/route-cover.jpg',$5,$6)`,
      [id, gymId, routeSetId, name, createdAt, published]
    );
    return id;
  }

  it('uses route creation, includes both boundaries, and excludes old/future/unpublished routes', async () => {
    const sets = await client!.query<{ id: string; name: string }>(
      `INSERT INTO route_sets(gym_id,name,starts_on) VALUES
         ($1,'新换线周期','2026-09-07'),($1,'旧换线周期','2026-01-01') RETURNING id,name`,
      [shanghaiGym]
    );
    const oldRoute = await route('旧线路的新视频不算新线', '2026-09-06T15:59:59.999999Z', {
      routeSetId: sets.rows.find((set) => set.name === '新换线周期')!.id
    });
    const first = await route('周一零点首条', weekStart);
    const recent = await route('旧周期中刚录入的新线', '2026-09-07T03:00:00Z', {
      routeSetId: sets.rows.find((set) => set.name === '旧换线周期')!.id
    });
    const last = await route('当前时刻新线', now);
    await route('未来线路', '2026-09-07T04:00:00.000001Z');
    await route('已下架线路', now, { published: false });
    const user = await client!.query<{ id: string }>(
      'INSERT INTO users(openid) VALUES($1) RETURNING id', [`weekly-test:${randomUUID()}`]
    );
    await client!.query(
      `INSERT INTO sends(user_id,route_id,video_url,sent_at)
       VALUES($1,$2,'https://example.com/new-send.mp4',$3)`,
      [user.rows[0]!.id, oldRoute, now]
    );

    const response = await app!.inject('/api/routes/weekly');
    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body).toMatchObject({ weekStart, weekEnd: now });
    expect(body.items.map((item: { id: string }) => item.id)).toEqual([last, recent, first]);
    expect(body.items[0]).toMatchObject({
      gym_id: shanghaiGym, name: '当前时刻新线', grade: 'V3', color: '蓝色',
      points: [], published: true, cover_url: 'https://example.com/route-cover.jpg',
      gym_name: '上海测试岩馆', gym_address: '上海测试地址', gym_city: '上海'
    });
    expect(new Date(body.items[0].created_at).toISOString()).toBe(now);
  });

  it('filters city before limiting and deterministically orders equal timestamps by UUID', async () => {
    const ids: string[] = [];
    const shanghaiIds: string[] = [];
    for (let index = 1; index <= 24; index += 1) {
      const id = `00000000-0000-4000-8000-${index.toString(16).padStart(12, '0')}`;
      const gymId = index % 2 === 0 ? shanghaiGym : beijingGym;
      ids.push(await route(`本周新线${index}`, '2026-09-07T01:00:00Z', { gymId, id }));
      if (gymId === shanghaiGym) shanghaiIds.push(id);
    }
    const itemIds = (body: { items: { id: string }[] }) => body.items.map((item) => item.id);

    const national = await app!.inject('/api/routes/weekly');
    expect(national.statusCode).toBe(200);
    expect(itemIds(national.json())).toEqual([...ids].reverse().slice(0, 10));
    const maximum = await app!.inject('/api/routes/weekly?limit=20');
    expect(itemIds(maximum.json())).toEqual([...ids].reverse().slice(0, 20));
    const city = await app!.inject(`/api/routes/weekly?city=${encodeURIComponent(' 上海 ')}&limit=20`);
    expect(itemIds(city.json())).toEqual([...shanghaiIds].reverse());
    expect(city.json().items.every((item: { gym_city: string }) => item.gym_city === '上海')).toBe(true);
    const first = await app!.inject('/api/routes/weekly?limit=1');
    expect(itemIds(first.json())).toEqual([ids.at(-1)]);
    const blank = await app!.inject('/api/routes/weekly?city=%20%20&limit=20');
    expect(itemIds(blank.json())).toEqual(itemIds(maximum.json()));
  });

  it('switches weeks at Shanghai Monday midnight regardless of the PostgreSQL session timezone', async () => {
    const prior = await route('上周一线路', '2026-08-30T16:00:00Z');
    const current = await route('新周一线路', weekStart);
    vi.setSystemTime(new Date('2026-09-06T15:59:59.999Z'));
    const sunday = await app!.inject('/api/routes/weekly');
    expect(sunday.statusCode).toBe(200);
    expect(sunday.json()).toMatchObject({ weekStart: '2026-08-30T16:00:00.000Z', weekEnd: '2026-09-06T15:59:59.999Z' });
    expect(sunday.json().items.map((item: { id: string }) => item.id)).toEqual([prior]);

    vi.setSystemTime(new Date(weekStart));
    const monday = await app!.inject('/api/routes/weekly');
    expect(monday.statusCode).toBe(200);
    expect(monday.json()).toMatchObject({ weekStart, weekEnd: weekStart });
    expect(monday.json().items.map((item: { id: string }) => item.id)).toEqual([current]);
  });

  it('keeps bounds in an empty result, including the year boundary', async () => {
    const empty = await app!.inject(`/api/routes/weekly?city=${encodeURIComponent('没有岩馆的城市')}`);
    expect(empty.statusCode).toBe(200);
    expect(empty.json()).toEqual({ items: [], weekStart, weekEnd: now });

    vi.setSystemTime(new Date('2027-01-01T02:00:00.000Z'));
    const newYear = await app!.inject('/api/routes/weekly');
    expect(newYear.statusCode).toBe(200);
    expect(newYear.json()).toEqual({ items: [], weekStart: '2026-12-27T16:00:00.000Z', weekEnd: '2027-01-01T02:00:00.000Z' });
  });

  it('rejects an invalid JWT without reading weekly data', async () => {
    database.query.mockClear();
    const response = await app!.inject({
      url: '/api/routes/weekly', headers: { authorization: 'Bearer invalid-session' }
    });
    expect(response.statusCode).toBe(401);
    expect(database.query).not.toHaveBeenCalled();
  });
});
