import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

// Only the connection is redirected; authorization, SQL and foreign keys are real.
const database = vi.hoisted(() => ({ query: vi.fn(), transaction: vi.fn() }));
vi.mock('../src/db.js', () => database);

import { authPlugin } from '../src/auth.js';
import { config } from '../src/config.js';
import { sendRoutes } from '../src/routes/sends.js';
import { userRoutes } from '../src/routes/users.js';
import { routeRoutes } from '../src/routes/routes.js';
import { rankingRoutes } from '../src/routes/rankings.js';
import { shareRoutes } from '../src/routes/shares.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;
type Viewer = { id: string; headers: { authorization: string } };

suite('owner post deletion with isolated local PostgreSQL', () => {
  let app: FastifyInstance | undefined;
  let client: pg.Client | undefined;
  let schemaCreated = false;
  const schema = `send_deletion_test_${randomUUID().replaceAll('-', '')}`;
  let owner: Viewer;
  let other: Viewer;
  let sendId: string;

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) {
      throw new Error('Send deletion E2E requires a dedicated local test/e2e/CI database');
    }
    client = new pg.Client(config.DATABASE_URL ? { connectionString: config.DATABASE_URL } : {
      host: config.PGHOST, port: config.PGPORT, database: config.PGDATABASE,
      user: config.PGUSER, password: config.PGPASSWORD
    });
    await client.connect();
    await client.query(`CREATE SCHEMA "${schema}"`);
    schemaCreated = true;
    await client.query(`SET search_path TO "${schema}",public`);
    await client.query(await readFile(new URL('../src/db/schema.sql', import.meta.url), 'utf8'));
    database.query.mockImplementation((sql: string, values: unknown[] = []) => client!.query(sql, values));
    database.transaction.mockImplementation(async (callback) => {
      await client!.query('BEGIN');
      try {
        const result = await callback(client!);
        await client!.query('COMMIT');
        return result;
      } catch (error) {
        await client!.query('ROLLBACK');
        throw error;
      }
    });
    app = Fastify();
    await app.register(sensible);
    app.setErrorHandler((error, _request, reply) => {
      if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
      return reply.send(error);
    });
    await app.register(authPlugin);
    await app.register(sendRoutes, { prefix: '/api/sends' });
    await app.register(userRoutes, { prefix: '/api/users' });
    await app.register(routeRoutes, { prefix: '/api/routes' });
    await app.register(rankingRoutes, { prefix: '/api/rankings' });
    await app.register(shareRoutes, { prefix: '/api/shares' });
    await app.ready();
  });

  beforeEach(async () => {
    await client!.query(`TRUNCATE "${schema}".users,"${schema}".gyms CASCADE`);
    async function user(nickname: string): Promise<Viewer> {
      const result = await client!.query<{ id: string }>(
        'INSERT INTO users(openid,nickname) VALUES($1,$2) RETURNING id',
        [`send-deletion:${randomUUID()}`, nickname]
      );
      const id = result.rows[0]!.id;
      return { id, headers: { authorization: `Bearer ${app!.jwt.sign({ sub: id, role: 'user' })}` } };
    }
    owner = await user('动态作者');
    other = await user('其他岩友');
    const created = await app!.inject({
      method: 'POST', url: '/api/sends/moments', headers: owner.headers,
      payload: { caption: '自己可以删除的图文动态', imageUrls: ['https://example.com/deletion-photo.jpg'] }
    });
    expect(created.statusCode).toBe(200);
    expect(created.json().moderation_status).toBe('approved');
    sendId = created.json().id;
  });

  afterAll(async () => {
    if (app) await app.close();
    if (client && schemaCreated) await client.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (client) await client.end();
  });

  const get = (url: string, viewer?: Viewer) => app!.inject({ url, headers: viewer?.headers });
  const remove = (id = sendId, viewer = owner) => app!.inject({
    method: 'DELETE', url: `/api/sends/${id}`, headers: viewer.headers
  });
  const savedPost = () => client!.query('SELECT * FROM sends WHERE id=$1', [sendId]);

  it.each(['guest', 'invalid token', 'expired token'])('rejects deletion by %s without changing the post', async (session) => {
    const before = (await savedPost()).rows;
    const token = session === 'expired token'
      ? app!.jwt.sign({ sub: owner.id, role: 'user', exp: Math.floor(Date.now() / 1000) - 30 })
      : 'invalid-token';
    const result = await app!.inject({
      method: 'DELETE', url: `/api/sends/${sendId}`,
      headers: session === 'guest' ? {} : { authorization: `Bearer ${token}` }
    });
    expect(result.statusCode).toBe(401);
    expect((await savedPost()).rows).toEqual(before);
  });

  it.each(['user', 'admin'])('rejects a different %s even with a forged owner in the body', async (role) => {
    await client!.query('UPDATE users SET role=$2 WHERE id=$1', [other.id, role]);
    const before = (await savedPost()).rows;
    const result = await app!.inject({
      method: 'DELETE', url: `/api/sends/${sendId}`, headers: other.headers,
      payload: { userId: owner.id }
    });
    expect(result.statusCode).toBe(404);
    expect(result.json().message).toBe('动态不存在或无权删除');
    expect((await savedPost()).rows).toEqual(before);
  });

  it('validates the post id before executing a delete', async () => {
    expect((await remove('invalid-id')).statusCode).toBe(400);
    expect((await savedPost()).rowCount).toBe(1);
  });

  it('deletes an own moment and its interactions, hides it everywhere, and preserves other posts', async () => {
    const unrelated = await app!.inject({
      method: 'POST', url: '/api/sends/moments', headers: other.headers, payload: { caption: '保留这条动态' }
    });
    expect(unrelated.statusCode).toBe(200);
    const unrelatedId = unrelated.json().id as string;
    for (const id of [sendId, unrelatedId]) {
      expect((await app!.inject({ method: 'POST', url: `/api/sends/${id}/like`, headers: owner.headers })).statusCode).toBe(200);
      const comment = await app!.inject({
        method: 'POST', url: `/api/sends/${id}/comments`, headers: other.headers, payload: { content: '保留或随动态删除的评论' }
      });
      expect(comment.statusCode).toBe(200);
      expect(comment.json().moderation_status).toBe('approved');
    }
    // Legacy pending/rejected child rows must also be removed by the foreign key.
    await client!.query(
      `INSERT INTO comments(send_id,user_id,content,moderation_status)
       VALUES($1,$2,'旧待审评论','pending'),($1,$2,'旧拒绝评论','rejected')`, [sendId, other.id]
    );
    const keptPost = (await client!.query('SELECT * FROM sends WHERE id=$1', [unrelatedId])).rows;
    const keptLikes = (await client!.query('SELECT * FROM post_likes WHERE send_id=$1', [unrelatedId])).rows;
    const keptComments = (await client!.query('SELECT * FROM comments WHERE send_id=$1', [unrelatedId])).rows;
    expect((await get(`/api/sends/${sendId}`)).json()).toMatchObject({ like_count: 1, comment_count: 1 });
    expect((await get('/api/users/me/sends', owner)).json().items).toEqual([expect.objectContaining({ id: sendId })]);

    const deleted = await remove();
    expect(deleted.statusCode).toBe(200);
    expect(deleted.json()).toEqual({ deleted: true });
    expect((await remove()).statusCode).toBe(404);
    expect((await remove(randomUUID())).statusCode).toBe(404);
    expect((await savedPost()).rowCount).toBe(0);
    expect((await client!.query('SELECT * FROM post_likes WHERE send_id=$1', [sendId])).rows).toEqual([]);
    expect((await client!.query('SELECT * FROM comments WHERE send_id=$1', [sendId])).rows).toEqual([]);
    for (const viewer of [undefined, owner, other]) {
      expect((await get(`/api/sends/${sendId}`, viewer)).statusCode).toBe(404);
      const feed = await get('/api/sends/feed?scope=square', viewer);
      expect(feed.statusCode).toBe(200);
      expect(feed.json().items).toEqual([expect.objectContaining({ id: unrelatedId, like_count: 1, comment_count: 1 })]);
    }
    expect((await get('/api/sends/feed?scope=friends', owner)).json().items).toEqual([]);
    expect((await get('/api/users/me/sends', owner)).json().items).toEqual([]);
    expect((await app!.inject({ method: 'POST', url: `/api/sends/${sendId}/like`, headers: other.headers })).statusCode).toBe(404);
    expect((await app!.inject({
      method: 'POST', url: `/api/sends/${sendId}/comments`, headers: other.headers, payload: { content: '不能恢复已删除动态' }
    })).statusCode).toBe(404);
    expect((await client!.query('SELECT * FROM sends WHERE id=$1', [unrelatedId])).rows).toEqual(keptPost);
    expect((await client!.query('SELECT * FROM post_likes WHERE send_id=$1', [unrelatedId])).rows).toEqual(keptLikes);
    expect((await client!.query('SELECT * FROM comments WHERE send_id=$1', [unrelatedId])).rows).toEqual(keptComments);
  });

  it.each([
    ['private', 'approved'], ['friends', 'approved'], ['public', 'pending'], ['public', 'rejected']
  ])('allows the owner to delete a %s / %s post', async (visibility, status) => {
    await client!.query('UPDATE sends SET visibility=$2,moderation_status=$3 WHERE id=$1', [sendId, visibility, status]);
    await client!.query("INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'blocked')", [other.id, owner.id]);
    expect((await remove()).statusCode).toBe(200);
    expect((await savedPost()).rowCount).toBe(0);
  });

  it('recalculates personal, calendar, shared-route and ranking statistics after deleting a video check-in', async () => {
    const gym = await client!.query<{ id: string }>(
      "INSERT INTO gyms(name,city,address) VALUES('删除回归岩馆','深圳市','隔离测试地址') RETURNING id"
    );
    const routes = await client!.query<{ id: string; grade: string }>(
      "INSERT INTO routes(gym_id,name,grade,color) VALUES($1,'删掉完攀的线路','V5','红色'),($1,'保留完攀的线路','V1','蓝色') RETURNING id,grade",
      [gym.rows[0]!.id]
    );
    const removedRoute = routes.rows.find((row) => row.grade === 'V5')!.id;
    const keptRoute = routes.rows.find((row) => row.grade === 'V1')!.id;
    await client!.query("UPDATE sends SET route_id=$2,video_url='https://example.com/deletion-video.mp4' WHERE id=$1", [sendId, removedRoute]);
    const kept = await client!.query<{ id: string }>(
      "INSERT INTO sends(user_id,route_id,attempts,moderation_status) VALUES($1,$2,2,'approved') RETURNING id", [owner.id, keptRoute]
    );
    await client!.query('INSERT INTO post_likes(send_id,user_id) VALUES($1,$2),($1,$3)', [sendId, owner.id, other.id]);
    const month = (await client!.query<{ month: string }>(`SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai','YYYY-MM') AS "month"`)).rows[0]!.month;
    const dashboard = () => get(`/api/users/me/month-dashboard?month=${month}`, owner);
    const ranking = () => get('/api/rankings/', owner);
    expect((await get('/api/users/me', owner)).json().stats).toMatchObject({ total_sends: 2, monthly_sends: 2, max_grade: 5 });
    expect((await dashboard()).json().summary).toMatchObject({ sends: 2, max_grade: 5, flashes: 1, videos: 1 });
    expect((await ranking()).json().myRank).toMatchObject({ send_count: 2, total_likes: 2, points: 59, max_grade: 5 });
    expect((await get(`/api/routes/${removedRoute}`)).json()).toMatchObject({ send_count: 1, featuredSend: { id: sendId } });
    expect((await get(`/api/shares/routes/${removedRoute}`)).json().route.send_count).toBe(1);

    expect((await remove()).statusCode).toBe(200);
    expect((await get('/api/users/me', owner)).json().stats).toEqual({ total_sends: 1, monthly_sends: 1, gym_count: 1, max_grade: 1, monthly_max_grade: 1 });
    expect((await get(`/api/users/${owner.id}/public`, other)).json().stats).toEqual({ total_sends: 1, gym_count: 1, max_grade: 1 });
    const afterDashboard = await dashboard();
    expect(afterDashboard.json().summary).toEqual({ climbing_days: 1, sends: 1, gyms: 1, max_grade: 1, flashes: 0, videos: 0 });
    expect(afterDashboard.json().days).toEqual([expect.objectContaining({ grade: 'V1', sends: 1 })]);
    expect(afterDashboard.json().byGrade).toEqual([{ grade: 'V1', sends: 1 }]);
    expect((await get('/api/users/me/growth-summary', owner)).json().byGrade).toEqual([{ grade: 'V1', sends: 1 }]);
    const afterRanking = await ranking();
    expect(afterRanking.json().items).toEqual([expect.objectContaining({ user_id: owner.id, send_count: 1, total_likes: 0, points: 15, max_grade: 1 })]);
    expect(afterRanking.json().myRank).toMatchObject({ send_count: 1, total_likes: 0, points: 15 });
    expect((await get(`/api/routes/${removedRoute}`)).json()).toMatchObject({ id: removedRoute, send_count: 0, featuredSend: null, published: true });
    expect((await get(`/api/routes/${removedRoute}/leaderboard`)).json()).toEqual({ items: [], completionCount: 0 });
    expect((await get(`/api/shares/routes/${removedRoute}`)).json().route.send_count).toBe(0);
    const routeRanking = await get('/api/rankings/routes');
    expect(routeRanking.json().items.find((row: { route_id: string }) => row.route_id === removedRoute))
      .toMatchObject({ completion_count: 0, total_likes: 0, top_send_id: null, top_video_url: null });
    expect((await get('/api/users/me/sends', owner)).json().items).toEqual([expect.objectContaining({ id: kept.rows[0]!.id })]);
  });
});
