import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import Fastify, { type FastifyInstance } from 'fastify';
import sensible from '@fastify/sensible';
import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError } from 'zod';

// Exercise the actual authorization and visibility SQL on one isolated schema.
const database = vi.hoisted(() => ({ query: vi.fn(), transaction: vi.fn() }));
vi.mock('../src/db.js', () => database);

import { authPlugin } from '../src/auth.js';
import { config } from '../src/config.js';
import { sendRoutes } from '../src/routes/sends.js';
import { routeRoutes } from '../src/routes/routes.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;
type Viewer = { id: string; token: string; nickname: string; avatar_url: string };
type CommentStatus = 'approved' | 'pending' | 'rejected';

suite('comment visibility with isolated local PostgreSQL', () => {
  let app: FastifyInstance | undefined;
  let client: pg.Client | undefined;
  let schemaCreated = false;
  const schema = `comment_visibility_test_${randomUUID().replaceAll('-', '')}`;
  const originalModerationMode = config.MODERATION_MODE;
  let owner: Viewer;
  let commenter: Viewer;
  let other: Viewer;
  let sendId: string;

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const name = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(name)) {
      throw new Error('Comment visibility E2E requires a dedicated local test/e2e/CI database');
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
    config.MODERATION_MODE = 'manual';
    app = Fastify();
    await app.register(sensible);
    app.setErrorHandler((error, _request, reply) => {
      if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
      return reply.send(error);
    });
    await app.register(authPlugin);
    await app.register(sendRoutes, { prefix: '/api/sends' });
    await app.register(routeRoutes, { prefix: '/api/routes' });
    await app.ready();
  });

  beforeEach(async () => {
    await client!.query(`TRUNCATE "${schema}".users,"${schema}".gyms CASCADE`);
    async function user(nickname: string): Promise<Viewer> {
      const result = await client!.query<{ id: string; nickname: string; avatar_url: string }>(
        'INSERT INTO users(openid,nickname,avatar_url) VALUES($1,$2,$3) RETURNING id,nickname,avatar_url',
        [`comment-test:${randomUUID()}`, nickname, 'https://example.com/comment-avatar.png']
      );
      const row = result.rows[0]!;
      return { ...row, token: app!.jwt.sign({ sub: row.id, role: 'user' }) };
    }
    owner = await user('动态作者');
    commenter = await user('评论作者');
    other = await user('其他岩友');
    const post = await client!.query<{ id: string }>(
      `INSERT INTO sends(user_id,caption,visibility,moderation_status)
       VALUES($1,'评论可见性测试','public','approved') RETURNING id`, [owner.id]
    );
    sendId = post.rows[0]!.id;
  });

  afterAll(async () => {
    config.MODERATION_MODE = originalModerationMode;
    if (app) await app.close();
    if (client && schemaCreated) await client.query(`DROP SCHEMA "${schema}" CASCADE`);
    if (client) await client.end();
  });

  const headers = (viewer?: Viewer) => viewer ? { authorization: `Bearer ${viewer.token}` } : {};
  const detail = (viewer?: Viewer) => app!.inject({ url: `/api/sends/${sendId}`, headers: headers(viewer) });
  const feed = (viewer?: Viewer, scope = 'square') => app!.inject({ url: `/api/sends/feed?scope=${scope}`, headers: headers(viewer) });
  const postComment = (viewer: Viewer, content = '刚发表的评论') => app!.inject({
    method: 'POST', url: `/api/sends/${sendId}/comments`, headers: headers(viewer), payload: { content }
  });

  async function insertComment(viewer: Viewer, status: CommentStatus) {
    const result = await client!.query<{ id: string }>(
      `INSERT INTO comments(send_id,user_id,content,moderation_status)
       VALUES($1,$2,$3,$4) RETURNING id`, [sendId, viewer.id, `${viewer.nickname} ${status}`, status]
    );
    return result.rows[0]!.id;
  }

  async function expectVisible(viewer: Viewer | undefined, ids: string[], scope = 'square') {
    const response = await detail(viewer);
    expect(response.statusCode).toBe(200);
    expect(response.json().comments.map((comment: { id: string }) => comment.id).sort()).toEqual([...ids].sort());
    expect(response.json().comment_count).toBe(ids.length);
    const listing = await feed(viewer, scope);
    expect(listing.statusCode).toBe(200);
    expect(listing.json().items.find((post: { id: string }) => post.id === sendId)?.comment_count).toBe(ids.length);
  }

  it('publishes new comments with legacy manual configuration while preserving old pending visibility', async () => {
    const approvedId = await insertComment(other, 'approved');
    const ownPendingId = await insertComment(commenter, 'pending');
    await insertComment(other, 'pending');
    await insertComment(commenter, 'rejected');
    expect(config.MODERATION_MODE).toBe('manual');
    const response = await postComment(commenter);
    expect(response.statusCode).toBe(200);
    const posted = response.json();
    expect(posted).toMatchObject({
      send_id: sendId, user_id: commenter.id, content: '刚发表的评论',
      moderation_status: 'approved', nickname: commenter.nickname, avatar_url: commenter.avatar_url
    });
    expect(posted.id).toEqual(expect.any(String));
    expect(posted.created_at).toEqual(expect.any(String));
    const saved = await client!.query('SELECT moderation_status FROM comments WHERE id=$1', [posted.id]);
    expect(saved.rows[0].moderation_status).toBe('approved');
    await expectVisible(commenter, [approvedId, posted.id, ownPendingId]);
    const ownDetail = await detail(commenter);
    expect(ownDetail.json().comments.find((comment: { id: string }) => comment.id === posted.id))
      .toMatchObject({ moderation_status: 'approved', user_id: commenter.id });
    await expectVisible(owner, [approvedId, posted.id]);
    // Existing pending comments remain private to their authors.
    await expectVisible(undefined, [approvedId, posted.id]);
  });

  it.each(['public', 'friends', 'private'])('publishes a new %s moment with legacy manual configuration and preserves its audience', async (visibility) => {
    await client!.query(
      "INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')", [owner.id, commenter.id]
    );
    const imageUrls = visibility === 'public' ? [] : ['https://example.com/new-moment.png'];
    expect(config.MODERATION_MODE).toBe('manual');
    const response = await app!.inject({
      method: 'POST', url: '/api/sends/moments', headers: headers(commenter),
      payload: { caption: '发布就展示', imageUrls, visibility }
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      moderationStatus: 'approved', moderation_status: 'approved', visibility, image_urls: imageUrls
    });
    sendId = response.json().id;
    const saved = await client!.query('SELECT moderation_status,visibility FROM sends WHERE id=$1', [sendId]);
    expect(saved.rows[0]).toEqual({ moderation_status: 'approved', visibility });
    expect((await detail(commenter)).statusCode).toBe(200);
    expect((await detail(owner)).statusCode).toBe(visibility === 'private' ? 404 : 200);
    expect((await detail(other)).statusCode).toBe(visibility === 'public' ? 200 : 404);
    expect((await detail()).statusCode).toBe(visibility === 'public' ? 200 : 404);
    const listing = await feed(owner, visibility === 'friends' ? 'friends' : 'square');
    expect(listing.statusCode).toBe(200);
    expect(listing.json().items.some((post: { id: string }) => post.id === sendId)).toBe(visibility !== 'private');

    await client!.query(
      "UPDATE friendships SET status='blocked' WHERE requester_id=$1 AND addressee_id=$2", [owner.id, commenter.id]
    );
    expect((await detail(owner)).statusCode).toBe(404);
    expect((await feed(owner)).json().items.some((post: { id: string }) => post.id === sendId)).toBe(false);
  });

  it('reflects approval and rejection without duplicate or stale visible counts', async () => {
    const id = await insertComment(commenter, 'pending');
    await expectVisible(commenter, [id]);
    await expectVisible(other, []);
    await client!.query("UPDATE comments SET moderation_status='approved' WHERE id=$1", [id]);
    await expectVisible(commenter, [id]);
    await expectVisible(other, [id]);
    await expectVisible(undefined, [id]);
    await client!.query("UPDATE comments SET moderation_status='rejected' WHERE id=$1", [id]);
    await expectVisible(commenter, []);
    await expectVisible(other, []);
    await expectVisible(undefined, []);
  });

  it.each(['outgoing', 'incoming'])('keeps %s commenter blocks outside the moderation visibility exception', async (direction) => {
    const ownId = await insertComment(commenter, 'pending');
    await insertComment(other, 'approved');
    await client!.query(
      "INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'blocked')",
      direction === 'outgoing' ? [commenter.id, other.id] : [other.id, commenter.id]
    );
    await expectVisible(commenter, [ownId]);
  });

  it.each(['outgoing', 'incoming'])('does not expose a post through an own pending comment after an %s author block', async (direction) => {
    await insertComment(commenter, 'pending');
    await client!.query(
      "INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'blocked')",
      direction === 'outgoing' ? [commenter.id, owner.id] : [owner.id, commenter.id]
    );
    expect((await detail(commenter)).statusCode).toBe(404);
    expect((await feed(commenter)).json().items).toEqual([]);
    expect((await postComment(commenter)).statusCode).toBe(404);
    expect((await client!.query('SELECT count(*)::int count FROM comments')).rows[0].count).toBe(1);
  });

  it.each([
    ['private', 'approved'], ['friends', 'approved'], ['public', 'pending'], ['public', 'rejected']
  ])('does not bypass a %s / %s post with an own pending comment', async (visibility, moderationStatus) => {
    await insertComment(commenter, 'pending');
    await client!.query('UPDATE sends SET visibility=$2,moderation_status=$3 WHERE id=$1', [sendId, visibility, moderationStatus]);
    expect((await detail(commenter)).statusCode).toBe(404);
    expect((await feed(commenter)).json().items).toEqual([]);
    expect((await postComment(commenter)).statusCode).toBe(404);
  });

  it('publishes comments within the friends audience while preserving old pending self-only visibility', async () => {
    await client!.query("UPDATE sends SET visibility='friends' WHERE id=$1", [sendId]);
    await client!.query(
      "INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')", [owner.id, commenter.id]
    );
    const ownPendingId = await insertComment(commenter, 'pending');
    const response = await postComment(commenter);
    expect(response.statusCode).toBe(200);
    expect(response.json().moderation_status).toBe('approved');
    await expectVisible(commenter, [response.json().id, ownPendingId], 'friends');
    await expectVisible(owner, [response.json().id], 'friends');
    expect((await detail(other)).statusCode).toBe(404);
    expect((await detail()).statusCode).toBe(404);
  });

  it('keeps a route featured send count aligned with detail for own pending and blocked comments', async () => {
    const gym = await client!.query<{ id: string }>(
      "INSERT INTO gyms(name,city,address) VALUES('评论测试岩馆','成都','测试地址') RETURNING id"
    );
    const route = await client!.query<{ id: string }>(
      "INSERT INTO routes(gym_id,name,grade,color) VALUES($1,'评论测试线路','V2','蓝色') RETURNING id",
      [gym.rows[0]!.id]
    );
    const routeId = route.rows[0]!.id;
    await client!.query(
      "UPDATE sends SET route_id=$2,video_url='https://example.com/comment-send.mp4' WHERE id=$1",
      [sendId, routeId]
    );
    const ownId = await insertComment(commenter, 'pending');
    const otherId = await insertComment(other, 'approved');
    await insertComment(commenter, 'rejected');
    const routeDetail = (viewer?: Viewer) => app!.inject({
      url: `/api/routes/${routeId}`, headers: headers(viewer)
    });
    const beforeBlock = await routeDetail(commenter);
    expect(beforeBlock.statusCode).toBe(200);
    expect(beforeBlock.json().featuredSend).toMatchObject({ id: sendId, comment_count: 2 });
    await expectVisible(commenter, [ownId, otherId]);

    await client!.query(
      "INSERT INTO friendships(requester_id,addressee_id,status) VALUES($1,$2,'blocked')",
      [other.id, commenter.id]
    );
    const afterBlock = await routeDetail(commenter);
    expect(afterBlock.statusCode).toBe(200);
    expect(afterBlock.json().featuredSend).toMatchObject({ id: sendId, comment_count: 1 });
    await expectVisible(commenter, [ownId]);
    const guest = await routeDetail();
    expect(guest.statusCode).toBe(200);
    expect(guest.json().featuredSend).toMatchObject({ id: sendId, comment_count: 1 });
    await expectVisible(undefined, [otherId]);
  });
});
