import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

// Exercise actual SQL, JWT validation and migrations in a disposable schema.
const database = vi.hoisted(() => ({ query: vi.fn(), transaction: vi.fn() }));
vi.mock('../src/db.js', () => database);

import { authPlugin } from '../src/auth.js';
import { config } from '../src/config.js';
import { sendRoutes } from '../src/routes/sends.js';
import { userRoutes } from '../src/routes/users.js';
import { routeRoutes } from '../src/routes/routes.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;
type Viewer = { id: string; headers: { authorization: string } };
type Kind = 'comments' | 'favorites' | 'likes';

suite('private favorites and personal activity with isolated local PostgreSQL', () => {
  let app: FastifyInstance | undefined;
  let client: pg.Client | undefined;
  let schemaCreated = false;
  const schema = `post_favorites_test_${randomUUID().replaceAll('-', '')}`;
  let owner: Viewer;
  let viewer: Viewer;
  let other: Viewer;
  let sendId: string;

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) {
      throw new Error('Favorites E2E requires a dedicated local test/e2e/CI database');
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
    await app.ready();
  });

  beforeEach(async () => {
    await client!.query(`TRUNCATE "${schema}".users,"${schema}".gyms CASCADE`);
    async function user(nickname: string): Promise<Viewer> {
      const result = await client!.query<{ id: string }>(
        'INSERT INTO users(openid,nickname) VALUES($1,$2) RETURNING id',
        [`post-favorites:${randomUUID()}`, nickname]
      );
      const id = result.rows[0]!.id;
      return { id, headers: { authorization: `Bearer ${app!.jwt.sign({ sub: id, role: 'user' })}` } };
    }
    owner = await user('动态作者');
    viewer = await user('收藏岩友');
    other = await user('其他岩友');
    sendId = await post(owner);
  });

  afterAll(async () => {
    if (app) await app.close();
    if (client && schemaCreated) await client.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (client) await client.end();
  });

  async function post(author: Viewer, visibility = 'public', status = 'approved') {
    const result = await client!.query<{ id: string }>(
      `INSERT INTO sends(user_id,caption,visibility,moderation_status)
       VALUES($1,'个人互动测试动态',$2,$3) RETURNING id`, [author.id, visibility, status]
    );
    return result.rows[0]!.id;
  }
  const get = (url: string, actor?: Viewer) => app!.inject({ url, headers: actor?.headers });
  const favorite = (actor = viewer, id = sendId) => app!.inject({ method: 'POST', url: `/api/sends/${id}/favorite`, headers: actor.headers });
  const unfavorite = (actor = viewer, id = sendId) => app!.inject({ method: 'DELETE', url: `/api/sends/${id}/favorite`, headers: actor.headers });
  const activity = (kind: Kind, actor = viewer, query = '') => get(`/api/users/me/${kind}${query}`, actor);
  async function interact(actor = viewer, id = sendId) {
    expect((await favorite(actor, id)).statusCode).toBe(200);
    expect((await app!.inject({ method: 'POST', url: `/api/sends/${id}/like`, headers: actor.headers })).statusCode).toBe(200);
    const comment = await app!.inject({ method: 'POST', url: `/api/sends/${id}/comments`, headers: actor.headers, payload: { content: '我的评论' } });
    expect(comment.statusCode).toBe(200);
    expect(comment.json().moderation_status).toBe('approved');
    return comment.json().id as string;
  }
  async function expectActivityIds(ids: string[], actor = viewer) {
    for (const kind of ['comments', 'favorites', 'likes'] as const) {
      const response = await activity(kind, actor);
      expect(response.statusCode).toBe(200);
      expect(response.json().items.map((row: { id: string; post?: { id: string } }) => kind === 'comments' ? row.post!.id : row.id).sort())
        .toEqual([...ids].sort());
    }
  }

  it('persists an idempotent private favorite and returns viewer-specific flags without public totals', async () => {
    expect((await get(`/api/sends/${sendId}`)).json().favorited).toBe(false);
    const first = await favorite();
    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ favorited: true });
    const stored = (await client!.query('SELECT * FROM post_favorites')).rows;
    expect((await favorite()).json()).toEqual({ favorited: true });
    expect((await client!.query('SELECT * FROM post_favorites')).rows).toEqual(stored);
    for (const actor of [undefined, owner, other, viewer]) {
      const expected = actor?.id === viewer.id;
      const detail = await get(`/api/sends/${sendId}`, actor);
      expect(detail.statusCode).toBe(200);
      expect(detail.json()).toMatchObject({ favorited: expected, like_count: 0, comment_count: 0 });
      const feed = await get('/api/sends/feed?scope=square', actor);
      expect(feed.json().items[0]).toMatchObject({ id: sendId, favorited: expected });
      for (const body of [detail.json(), feed.json().items[0]]) {
        expect(Object.keys(body).filter((key) => key.includes('favorit'))).toEqual(['favorited']);
        expect(body).not.toHaveProperty('created_at');
      }
    }
    const saved = await activity('favorites');
    expect(saved.json()).toMatchObject({ items: [{ id: sendId, favorited: true, liked: false }], nextCursor: null });
    expect(saved.json().items[0].activity_at).toEqual(expect.any(String));
    expect((await activity('favorites', other)).json().items).toEqual([]);
    // Replaying the migration preserves existing favorites and its timestamp.
    await client!.query(await readFile(new URL('../src/db/schema.sql', import.meta.url), 'utf8'));
    expect((await client!.query('SELECT * FROM post_favorites')).rows).toEqual(stored);
  });

  it('keeps liking and favoriting independent, and unsaves only the authenticated account', async () => {
    await interact();
    await favorite(other);
    expect((await activity('likes')).json().items[0]).toMatchObject({ id: sendId, liked: true, favorited: true });
    expect((await unfavorite()).json()).toEqual({ favorited: false });
    expect((await unfavorite()).json()).toEqual({ favorited: false });
    expect((await unfavorite(viewer, randomUUID())).json()).toEqual({ favorited: false });
    expect((await activity('favorites')).json().items).toEqual([]);
    expect((await activity('likes')).json().items[0]).toMatchObject({ id: sendId, liked: true, favorited: false });
    expect((await activity('favorites', other)).json().items).toEqual([expect.objectContaining({ id: sendId, favorited: true, liked: false })]);
    await favorite();
    expect((await app!.inject({ method: 'DELETE', url: `/api/sends/${sendId}/like`, headers: viewer.headers })).json()).toEqual({ liked: false });
    expect((await activity('likes')).json().items).toEqual([]);
    expect((await activity('favorites')).json().items[0]).toMatchObject({ liked: false, favorited: true });
  });

  it.each(['guest', 'invalid', 'expired'])('requires a valid session for every favorite write and personal list (%s)', async (session) => {
    const token = session === 'expired'
      ? app!.jwt.sign({ sub: viewer.id, role: 'user', exp: Math.floor(Date.now() / 1000) - 30 })
      : 'invalid-token';
    const headers = session === 'guest' ? {} : { authorization: `Bearer ${token}` };
    for (const method of ['POST', 'DELETE'] as const) {
      expect((await app!.inject({ method, url: `/api/sends/${sendId}/favorite`, headers })).statusCode).toBe(401);
    }
    for (const kind of ['comments', 'favorites', 'likes']) {
      expect((await app!.inject({ url: `/api/users/me/${kind}`, headers })).statusCode).toBe(401);
    }
    expect((await client!.query('SELECT * FROM post_favorites')).rows).toEqual([]);
  });

  it.each([
    ['friends', 'approved'], ['private', 'approved'], ['public', 'pending'], ['public', 'rejected']
  ])('does not allow an interaction history to expose an inaccessible %s / %s parent', async (visibility, status) => {
    await interact();
    await client!.query('UPDATE sends SET visibility=$2,moderation_status=$3 WHERE id=$1', [sendId, visibility, status]);
    expect((await favorite()).statusCode).toBe(404);
    expect((await get(`/api/sends/${sendId}`, viewer)).statusCode).toBe(404);
    await expectActivityIds([]);
    // Owners can still manage their own private and legacy moderated content.
    await interact(owner);
    await expectActivityIds([sendId], owner);
    expect((await unfavorite()).statusCode).toBe(200);
    expect((await client!.query('SELECT * FROM post_favorites WHERE user_id=$1', [viewer.id])).rows).toEqual([]);
  });

  it('shows friends-only interactions only while the friendship remains accepted', async () => {
    await client!.query("UPDATE sends SET visibility='friends' WHERE id=$1", [sendId]);
    await client!.query("INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')", [owner.id, viewer.id]);
    await interact();
    await expectActivityIds([sendId]);
    expect((await get('/api/sends/feed?scope=friends', viewer)).json().items[0]).toMatchObject({ id: sendId, favorited: true });
    expect((await get('/api/sends/feed?scope=square', viewer)).json().items).toEqual([]);
    expect((await app!.inject({ method: 'DELETE', url: `/api/users/${owner.id}/friend`, headers: viewer.headers })).statusCode).toBe(200);
    await expectActivityIds([]);
    expect((await favorite()).statusCode).toBe(404);
    expect((await unfavorite()).statusCode).toBe(200);
  });

  it.each(['outgoing', 'incoming'])('hides every old interaction after an %s block', async (direction) => {
    await interact();
    await client!.query("INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'blocked')",
      direction === 'outgoing' ? [viewer.id, owner.id] : [owner.id, viewer.id]);
    await expectActivityIds([]);
    expect((await favorite()).statusCode).toBe(404);
    expect((await get(`/api/sends/${sendId}`, viewer)).statusCode).toBe(404);
    expect((await unfavorite()).statusCode).toBe(200);
  });

  it('returns only my comments including their own pending and rejected states, with normal post counts', async () => {
    const ownApproved = await interact();
    const rows = await client!.query<{ id: string }>(
      `INSERT INTO comments(send_id,user_id,content,moderation_status)
       VALUES($1,$2,'自己待审','pending'),($1,$2,'自己未公开','rejected'),($1,$3,'他人未公开','rejected') RETURNING id`,
      [sendId, viewer.id, other.id]
    );
    const response = await activity('comments');
    expect(response.statusCode).toBe(200);
    expect(response.json().items.map((row: { id: string }) => row.id).sort()).toEqual([ownApproved, rows.rows[0]!.id, rows.rows[1]!.id].sort());
    expect(response.json().items.map((row: { moderation_status: string }) => row.moderation_status).sort()).toEqual(['approved', 'pending', 'rejected']);
    for (const row of response.json().items) {
      expect(row).toMatchObject({ post: { id: sendId, user_id: owner.id, favorited: true, liked: true, comment_count: 2 } });
      expect(Object.keys(row).sort()).toEqual(['content', 'created_at', 'id', 'moderation_status', 'post']);
    }
    expect((await activity('comments', owner)).json().items).toEqual([]);
    const detail = await get(`/api/sends/${sendId}`, viewer);
    expect(detail.json().comment_count).toBe(2);
    expect(detail.json().comments.some((row: { moderation_status: string }) => row.moderation_status === 'rejected')).toBe(false);
    await client!.query("UPDATE sends SET visibility='private' WHERE id=$1", [sendId]);
    expect((await activity('comments')).json().items).toEqual([]);
  });

  it('aligns featured video favorite flags with detail without exposing another viewer favorites', async () => {
    const gym = await client!.query<{ id: string }>("INSERT INTO gyms(name,city,address) VALUES('收藏测试岩馆','成都','测试地址') RETURNING id");
    const route = await client!.query<{ id: string }>("INSERT INTO routes(gym_id,name,grade,color) VALUES($1,'收藏测试线路','V2','蓝色') RETURNING id", [gym.rows[0]!.id]);
    await client!.query("UPDATE sends SET route_id=$2,video_url='https://example.com/favorite-video.mp4' WHERE id=$1", [sendId, route.rows[0]!.id]);
    await favorite();
    for (const actor of [undefined, viewer, other]) {
      const response = await get(`/api/routes/${route.rows[0]!.id}`, actor);
      expect(response.statusCode).toBe(200);
      expect(response.json().featuredSend).toMatchObject({ id: sendId, favorited: actor?.id === viewer.id });
      expect(Object.keys(response.json().featuredSend).filter((key) => key.includes('favorit'))).toEqual(['favorited']);
    }
  });

  it.each(['comments', 'favorites', 'likes'] as const)('paginates %s without duplicates or skipped microsecond timestamps and filters before limiting', async (kind) => {
    const expected: string[] = [];
    const times = ['2025-08-03T00:00:00.000900Z', '2025-08-03T00:00:00.000900Z', '2025-08-03T00:00:00.000800Z', '2025-08-02T00:00:00Z'];
    for (let index = 0; index < times.length; index++) {
      const id = index === 0 ? sendId : await post(owner);
      const commentId = await interact(viewer, id);
      const table = kind === 'comments' ? 'comments' : kind === 'favorites' ? 'post_favorites' : 'post_likes';
      const column = kind === 'comments' ? 'id' : 'send_id';
      const activityId = kind === 'comments' ? commentId : id;
      await client!.query(`UPDATE ${table} SET created_at=$2 WHERE ${column}=$1 AND user_id=$3`, [activityId, times[index], viewer.id]);
      expected.push(activityId);
    }
    // Two rows with identical time use UUID as the deterministic tie breaker.
    expected.splice(0, 2, ...expected.slice(0, 2).sort().reverse());
    const hidden = await post(owner);
    await interact(viewer, hidden);
    await client!.query("UPDATE sends SET visibility='private' WHERE id=$1", [hidden]);
    const seen: string[] = [];
    let cursor: string | null = null;
    for (let page = 0; page < 4; page++) {
      const response = await activity(kind, viewer, `?limit=1${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
      expect(response.statusCode).toBe(200);
      expect(response.json().items).toHaveLength(1);
      const row = response.json().items[0];
      seen.push(row.id);
      expect(Object.keys(kind === 'comments' ? row.post : row).some((key) => key.startsWith('_'))).toBe(false);
      cursor = response.json().nextCursor;
      expect(cursor === null).toBe(page === 3);
    }
    expect(seen).toEqual(expected);
  });

  it('rejects malformed and cross-list cursors and enforces page limits', async () => {
    await interact();
    await interact(viewer, await post(owner));
    const first = await activity('favorites', viewer, '?limit=1');
    const cursor = first.json().nextCursor;
    expect(cursor).toEqual(expect.any(String));
    for (const kind of ['comments', 'favorites', 'likes'] as const) {
      for (const query of ['?cursor=bad-cursor', '?limit=0', '?limit=51', '?limit=1.5']) {
        expect((await activity(kind, viewer, query)).statusCode).toBe(400);
      }
    }
    expect((await activity('likes', viewer, `?cursor=${encodeURIComponent(cursor)}`)).statusCode).toBe(400);
    expect((await favorite(viewer, 'invalid-id')).statusCode).toBe(400);
    expect((await favorite(viewer, randomUUID())).statusCode).toBe(404);
  });

  it('cascades post and account deletion through favorites without leaving personal history visible', async () => {
    await interact();
    await favorite(other);
    const retainedId = await post(other);
    await favorite(other, retainedId);
    expect((await app!.inject({ method: 'DELETE', url: `/api/sends/${sendId}`, headers: owner.headers })).json()).toEqual({ deleted: true });
    await expectActivityIds([]);
    expect((await client!.query('SELECT * FROM post_favorites WHERE send_id=$1', [sendId])).rows).toEqual([]);
    expect((await activity('favorites', other)).json().items).toEqual([expect.objectContaining({ id: retainedId })]);
    const nextId = await post(owner);
    await favorite(viewer, nextId);
    await favorite(other, nextId);
    expect((await app!.inject({ method: 'DELETE', url: '/api/users/me', headers: viewer.headers })).statusCode).toBe(200);
    expect((await client!.query('SELECT * FROM post_favorites WHERE user_id=$1', [viewer.id])).rows).toEqual([]);
    expect((await client!.query('SELECT * FROM post_favorites WHERE user_id=$1', [other.id])).rowCount).toBe(2);
    expect((await activity('favorites')).statusCode).toBe(401);
  });
});
