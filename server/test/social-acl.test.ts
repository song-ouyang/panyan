import Fastify, { type FastifyPluginAsync } from 'fastify';
import sensible from '@fastify/sensible';
import { ZodError } from 'zod';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  clientQuery: vi.fn(),
  transaction: vi.fn(),
  initialModerationStatus: vi.fn()
}));

vi.mock('../src/db.js', () => ({
  query: mocks.query,
  transaction: mocks.transaction
}));
vi.mock('../src/moderation.js', () => ({ initialModerationStatus: mocks.initialModerationStatus }));

import { sendRoutes } from '../src/routes/sends.js';
import { gymRoutes } from '../src/routes/gyms.js';
import { meetupRoutes } from '../src/routes/meetups.js';
import { rankingRoutes } from '../src/routes/rankings.js';
import { routeRoutes } from '../src/routes/routes.js';
import { submissionRoutes } from '../src/routes/submissions.js';
import { userRoutes } from '../src/routes/users.js';

const viewerId = '00000000-0000-4000-8000-000000000001';
const otherId = '00000000-0000-4000-8000-000000000002';
const sendId = '00000000-0000-4000-8000-000000000003';
const gymId = '00000000-0000-4000-8000-000000000004';
const routeSetId = '00000000-0000-4000-8000-000000000005';
const routeId = '00000000-0000-4000-8000-000000000006';
const submissionId = '00000000-0000-4000-8000-000000000007';
const clientRequestId = '00000000-0000-4000-8000-000000000008';

function result(rows: unknown[] = []) {
  return { rows, rowCount: rows.length };
}

async function createApp(
  plugin: FastifyPluginAsync,
  prefix: string,
  role: 'user' | 'gym_admin' | 'admin' = 'user',
  authenticated = true
) {
  const app = Fastify();
  await app.register(sensible);
  app.decorate('authenticate', async (request) => {
    request.user = { sub: viewerId, role };
  });
  app.decorate('authenticateOptional', async (request) => {
    if (authenticated) request.user = { sub: viewerId, role };
  });
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) return reply.status(400).send({ code: 'VALIDATION_ERROR' });
    return reply.status(error.statusCode ?? 500).send({ message: error.message });
  });
  await app.register(plugin, { prefix });
  return app;
}

beforeEach(() => {
  mocks.query.mockReset();
  mocks.clientQuery.mockReset();
  mocks.transaction.mockReset();
  mocks.initialModerationStatus.mockReset();
  mocks.initialModerationStatus.mockReturnValue('approved');
  mocks.transaction.mockImplementation(async (callback) => callback({ query: mocks.clientQuery }));
});

describe('send visibility', () => {
  it.each(['public', 'friends', 'private'])('publishes a %s route check-in immediately in manual moderation mode', async (visibility) => {
    mocks.initialModerationStatus.mockReturnValue('pending');
    mocks.query
      .mockResolvedValueOnce(result([{ grade: 'V2', grade_number: 2 }]))
      .mockResolvedValueOnce(result([{ max_grade: 1 }]));
    mocks.clientQuery.mockResolvedValueOnce(result([{
      id: sendId,
      route_id: routeId,
      video_url: 'https://example.com/uploaded.mp4',
      visibility,
      moderation_status: 'approved'
    }]));
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({
      method: 'POST',
      url: '/api/sends',
      payload: { routeId, videoUrl: 'https://example.com/uploaded.mp4', visibility }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      sendId,
      send: { moderation_status: 'approved', visibility },
      moderationStatus: 'approved',
      pointsEarned: 25,
      pendingPoints: 0,
      milestone: { type: 'first_grade', grade: 'V2' }
    });
    expect(mocks.clientQuery.mock.calls[0]![1]).toEqual([
      viewerId, routeId, 1, 'https://example.com/uploaded.mp4', null, visibility, 'approved'
    ]);
    expect(mocks.initialModerationStatus).not.toHaveBeenCalled();
    await app.close();
  });

  it('keeps standalone moments subject to manual moderation', async () => {
    mocks.initialModerationStatus.mockReturnValue('pending');
    mocks.query.mockResolvedValueOnce(result([{ id: sendId, moderation_status: 'pending' }]));
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({
      method: 'POST',
      url: '/api/sends/moments',
      payload: { caption: '攀岩日常' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ moderationStatus: 'pending' });
    expect(mocks.query.mock.calls[0]![1]).toEqual([viewerId, '攀岩日常', [], 'public', 'pending']);
    await app.close();
  });

  it('keeps comments subject to manual moderation', async () => {
    mocks.initialModerationStatus.mockReturnValue('pending');
    mocks.query
      .mockResolvedValueOnce(result([{ id: sendId }]))
      .mockResolvedValueOnce(result([{ moderation_status: 'pending' }]));
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({
      method: 'POST',
      url: `/api/sends/${sendId}/comments`,
      payload: { content: '这条线路很棒' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ moderation_status: 'pending' });
    expect(mocks.query.mock.calls[1]![1]).toEqual([sendId, viewerId, '这条线路很棒', 'pending']);
    await app.close();
  });

  it('updates an existing check-in without deleting its likes or comments', async () => {
    mocks.initialModerationStatus.mockReturnValue('pending');
    mocks.query
      .mockResolvedValueOnce(result([{ grade: 'V3', grade_number: 3 }]))
      .mockResolvedValueOnce(result([{ max_grade: 3 }]));
    mocks.clientQuery.mockResolvedValueOnce(result([{
      id: sendId,
      route_id: routeId,
      attempts: 2,
      video_url: 'https://example.com/new.mp4',
      caption: '更新了完攀视频',
      visibility: 'friends',
      moderation_status: 'approved'
    }]));
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({
      method: 'POST',
      url: '/api/sends',
      payload: {
        routeId,
        attempts: 2,
        videoUrl: 'https://example.com/new.mp4',
        caption: '更新了完攀视频',
        visibility: 'friends'
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ sendId, moderationStatus: 'approved', pointsEarned: 25, pendingPoints: 0, milestone: null });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(1);
    const [sql, values] = mocks.clientQuery.mock.calls[0]!;
    expect(sql).toContain('ON CONFLICT(user_id,route_id) DO UPDATE');
    expect(sql).not.toContain('DELETE FROM post_likes');
    expect(sql).not.toContain('DELETE FROM comments');
    expect(values).toEqual([
      viewerId,
      routeId,
      2,
      'https://example.com/new.mp4',
      '更新了完攀视频',
      'friends',
      'approved'
    ]);
    await app.close();
  });

  it('builds a friends feed limited to approved accepted-friend content', async () => {
    mocks.query.mockResolvedValue(result([
      { id: sendId, visibility: 'friends', sent_at: '2026-08-30T00:00:00.000Z' }
    ]));
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({ method: 'GET', url: '/api/sends/feed?scope=friends' });

    expect(response.statusCode).toBe(200);
    expect(response.json().items[0].visibility).toBe('friends');
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain("s.moderation_status='approved'");
    expect(sql).toContain("s.visibility IN ('public','friends')");
    expect(sql).toContain("f.status='accepted'");
    expect(sql).toContain("c.moderation_status='approved'");
    expect(values).toEqual([viewerId, null, null, 20, 'friends']);
    await app.close();
  });

  it('lets a guest read the public square without a user identity', async () => {
    mocks.query.mockResolvedValue(result([
      { id: sendId, visibility: 'public', liked: false, sent_at: '2026-08-30T00:00:00.000Z' }
    ]));
    const app = await createApp(sendRoutes, '/api/sends', 'user', false);

    const response = await app.inject({ method: 'GET', url: '/api/sends/feed?scope=square' });

    expect(response.statusCode).toBe(200);
    expect(response.json().items[0]).toMatchObject({ visibility: 'public', liked: false });
    expect(mocks.query.mock.calls[0]![1]).toEqual([null, null, null, 20, 'square']);
    await app.close();
  });

  it('uses an opaque timestamp-and-id cursor so equal timestamps are not skipped', async () => {
    const firstId = '00000000-0000-4000-8000-000000000010';
    const secondId = '00000000-0000-4000-8000-000000000009';
    const sentAt = '2026-08-30T00:00:00.000Z';
    mocks.query
      .mockResolvedValueOnce(result([{ id: firstId, sent_at: sentAt, visibility: 'public' }]))
      .mockResolvedValueOnce(result([{ id: secondId, sent_at: sentAt, visibility: 'public' }]));
    const app = await createApp(sendRoutes, '/api/sends', 'user', false);

    const first = await app.inject({
      method: 'GET',
      url: '/api/sends/feed?scope=square&limit=1'
    });
    const cursor = first.json().nextCursor as string;
    expect(cursor).toEqual(expect.any(String));
    expect(cursor).not.toContain(sentAt);

    const second = await app.inject({
      method: 'GET',
      url: `/api/sends/feed?scope=square&limit=1&cursor=${encodeURIComponent(cursor)}`
    });

    expect(second.statusCode).toBe(200);
    expect(second.json().items[0].id).toBe(secondId);
    expect(mocks.query.mock.calls[1]![1]).toEqual([
      null,
      sentAt,
      firstId,
      1,
      'square'
    ]);
    const sql = mocks.query.mock.calls[1]![0] as string;
    expect(sql).toContain('(s.sent_at,s.id)<($2::timestamptz,$3::uuid)');
    expect(sql).toContain('WITH visible_sends AS');
    await app.close();
  });

  it('rejects a damaged opaque feed cursor before querying the database', async () => {
    const app = await createApp(sendRoutes, '/api/sends', 'user', false);

    const response = await app.inject({
      method: 'GET',
      url: '/api/sends/feed?scope=square&cursor=not-a-valid-cursor'
    });

    expect(response.statusCode).toBe(400);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('keeps the friends feed private for a guest', async () => {
    const app = await createApp(sendRoutes, '/api/sends', 'user', false);

    const response = await app.inject({ method: 'GET', url: '/api/sends/feed?scope=friends' });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 404 when a send is not visible to the viewer', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({ method: 'GET', url: `/api/sends/${sendId}` });

    expect(response.statusCode).toBe(404);
    const sql = mocks.query.mock.calls[0]![0] as string;
    expect(sql).toContain("s.visibility='friends'");
    expect(sql).toContain("f.status='accepted'");
    await app.close();
  });

  it('does not insert a like when the send fails the shared ACL', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({ method: 'POST', url: `/api/sends/${sendId}/like` });

    expect(response.statusCode).toBe(404);
    expect(mocks.query).toHaveBeenCalledTimes(1);
    await app.close();
  });

  it('lets a user remove their own stale like after visibility changes', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp(sendRoutes, '/api/sends');

    const response = await app.inject({ method: 'DELETE', url: `/api/sends/${sendId}/like` });

    expect(response.statusCode).toBe(200);
    expect(mocks.query).toHaveBeenCalledTimes(1);
    expect(mocks.query.mock.calls[0]![0]).toContain('DELETE FROM post_likes');
    await app.close();
  });
});

describe('route featured send visibility', () => {
  const routeRow = { id: routeId, name: '测试线路', send_count: 1 };
  const featuredRow = {
    id: sendId,
    route_id: routeId,
    user_id: otherId,
    video_url: 'https://example.com/send.mp4',
    visibility: 'public',
    moderation_status: 'approved'
  };

  it('lets anonymous viewers see only the first approved public video', async () => {
    mocks.query
      .mockResolvedValueOnce(result([routeRow]))
      .mockResolvedValueOnce(result([featuredRow]));
    const app = await createApp(routeRoutes, '/api/routes', 'user', false);

    const response = await app.inject({ method: 'GET', url: `/api/routes/${routeId}` });

    expect(response.statusCode).toBe(200);
    expect(response.json().featuredSend).toMatchObject(featuredRow);
    const [sql, values] = mocks.query.mock.calls[1]!;
    expect(sql).toContain("s.moderation_status='approved'");
    expect(sql).toContain("s.visibility='public'");
    expect(sql).toContain("f.status='accepted'");
    expect(values).toEqual([routeId, null]);
    await app.close();
  });

  it('uses the shared author/friend ACL when a viewer is authenticated', async () => {
    mocks.query
      .mockResolvedValueOnce(result([routeRow]))
      .mockResolvedValueOnce(result([{ ...featuredRow, user_id: viewerId, visibility: 'private', moderation_status: 'pending' }]));
    const app = await createApp(routeRoutes, '/api/routes');

    const response = await app.inject({
      method: 'GET',
      url: `/api/routes/${routeId}`,
      headers: { authorization: 'Bearer test-token' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().featuredSend).toMatchObject({
      user_id: viewerId,
      visibility: 'private',
      moderation_status: 'pending'
    });
    expect(mocks.query.mock.calls[1]![1]).toEqual([routeId, viewerId]);
    await app.close();
  });

  it('returns null rather than leaking a video that is not visible', async () => {
    mocks.query
      .mockResolvedValueOnce(result([routeRow]))
      .mockResolvedValueOnce(result());
    const app = await createApp(routeRoutes, '/api/routes', 'user', false);

    const response = await app.inject({ method: 'GET', url: `/api/routes/${routeId}` });

    expect(response.statusCode).toBe(200);
    expect(response.json().featuredSend).toBeNull();
    await app.close();
  });

  it('filters blocked authors from featured route videos', async () => {
    mocks.query
      .mockResolvedValueOnce(result([routeRow]))
      .mockResolvedValueOnce(result());
    const app = await createApp(routeRoutes, '/api/routes');

    const response = await app.inject({
      method: 'GET',
      url: `/api/routes/${routeId}`,
      headers: { authorization: 'Bearer test-token' }
    });

    expect(response.statusCode).toBe(200);
    const [sql, values] = mocks.query.mock.calls[1]!;
    expect(sql).toContain("blocked.status='blocked'");
    expect(values).toEqual([routeId, viewerId]);
    await app.close();
  });

  it('allows guests to browse the public route leaderboard', async () => {
    mocks.query.mockResolvedValueOnce(result([{ id: sendId, rank: 1, liked: false }]));
    const app = await createApp(routeRoutes, '/api/routes', 'user', false);

    const response = await app.inject({
      method: 'GET',
      url: `/api/routes/${routeId}/leaderboard`
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ completionCount: 1 });
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain("blocked.status='blocked'");
    expect(values).toEqual([routeId, null]);
    await app.close();
  });
});

describe('gym route filters', () => {
  it('rejects malformed route-set filters before they reach PostgreSQL', async () => {
    const app = await createApp(gymRoutes, '/api/gyms');

    const response = await app.inject({
      method: 'GET',
      url: `/api/gyms/${gymId}/routes?setId=not-a-uuid`
    });

    expect(response.statusCode).toBe(400);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('passes validated grade and route-set filters to the route query', async () => {
    mocks.query.mockResolvedValue(result([{ id: routeId, grade: 'V3' }]));
    const app = await createApp(gymRoutes, '/api/gyms');

    const response = await app.inject({
      method: 'GET',
      url: `/api/gyms/${gymId}/routes?grade=V3&setId=${routeSetId}`
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([gymId, 'V3', routeSetId]);
    await app.close();
  });
});

describe('public rankings', () => {
  it('scores only approved public sends in both ranking queries', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp(rankingRoutes, '/api/rankings');

    const response = await app.inject({ method: 'GET', url: '/api/rankings' });

    expect(response.statusCode).toBe(200);
    expect(mocks.query).toHaveBeenCalledTimes(2);
    for (const [sql] of mocks.query.mock.calls) {
      expect(sql).toContain("s.visibility='public'");
      expect(sql).toContain("s.moderation_status='approved'");
    }
    await app.close();
  });

  it('returns public ranking rows to a guest without calculating my rank', async () => {
    mocks.query.mockResolvedValue(result([{ user_id: otherId, points: 20 }]));
    const app = await createApp(rankingRoutes, '/api/rankings', 'user', false);

    const response = await app.inject({ method: 'GET', url: '/api/rankings' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ myRank: null });
    expect(mocks.query).toHaveBeenCalledTimes(1);
    await app.close();
  });
});

describe('friendship idempotency', () => {
  it('replaces an existing relationship with a directional block', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result([{ id: viewerId }, { id: otherId }]))
      .mockResolvedValueOnce(result([{
        requester_id: otherId,
        addressee_id: viewerId,
        status: 'accepted'
      }]))
      .mockResolvedValueOnce(result([{ requester_id: viewerId }]));
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'POST', url: `/api/users/${otherId}/block` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ blocked: true });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(3);
    expect(mocks.clientQuery.mock.calls[0]![0]).toContain('ORDER BY id');
    expect(mocks.clientQuery.mock.calls[0]![0]).toContain('FOR UPDATE');
    expect(mocks.clientQuery.mock.calls[1]![0]).toContain('FROM friendships');
    expect(mocks.clientQuery.mock.calls[1]![0]).toContain('FOR UPDATE');
    expect(mocks.clientQuery.mock.calls[2]![0]).toContain('UPDATE friendships');
    expect(mocks.clientQuery.mock.calls[2]![0]).toContain("status IN ('pending','accepted')");
    expect(mocks.clientQuery.mock.calls[2]![1]).toEqual([viewerId, otherId]);
    await app.close();
  });

  it('never takes ownership of a block created by the other user', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result([{ id: viewerId }, { id: otherId }]))
      .mockResolvedValueOnce(result([{
        requester_id: otherId,
        addressee_id: viewerId,
        status: 'blocked'
      }]));
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'POST', url: `/api/users/${otherId}/block` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ blocked: true });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(2);
    expect(mocks.clientQuery.mock.calls.some(([sql]) =>
      /(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+friendships/i.test(sql as string)
    )).toBe(false);
    await app.close();
  });

  it('does not remove either direction of a blocked relationship through friend deletion', async () => {
    mocks.query.mockResolvedValueOnce(result());
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'DELETE', url: `/api/users/${otherId}/friend` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ removed: false });
    expect(mocks.query.mock.calls[0]![0]).toContain("status IN ('pending','accepted')");
    expect(mocks.query.mock.calls[0]![1]).toEqual([viewerId, otherId]);
    await app.close();
  });

  it('still removes an accepted friendship through the friend endpoint', async () => {
    mocks.query.mockResolvedValueOnce(result([{ requester_id: viewerId }]));
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'DELETE', url: `/api/users/${otherId}/friend` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ removed: true });
    await app.close();
  });

  it('only removes a block created by the current user', async () => {
    mocks.query.mockResolvedValueOnce(result([{ requester_id: viewerId }]));
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'DELETE', url: `/api/users/${otherId}/block` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ blocked: false });
    expect(mocks.query.mock.calls[0]![0]).toContain("requester_id=$1 AND addressee_id=$2 AND status='blocked'");
    expect(mocks.query.mock.calls[0]![1]).toEqual([viewerId, otherId]);
    await app.close();
  });

  it('returns 404 without inserting when the friend target does not exist', async () => {
    mocks.clientQuery.mockResolvedValueOnce(result());
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'POST', url: `/api/users/${otherId}/friend-request` });

    expect(response.statusCode).toBe(404);
    expect(mocks.clientQuery).toHaveBeenCalledTimes(1);
    await app.close();
  });

  it('returns an existing accepted relationship without another notification', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result([{ id: otherId }]))
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ requester_id: viewerId, addressee_id: otherId, status: 'accepted' }]));
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'POST', url: `/api/users/${otherId}/friend-request` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'accepted' });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(3);
    await app.close();
  });

  it('accepts the same request repeatedly without duplicate notifications', async () => {
    mocks.clientQuery.mockResolvedValueOnce(result([{ status: 'accepted' }]));
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'POST', url: `/api/users/${otherId}/friend-accept` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'accepted' });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(1);
    await app.close();
  });
});

describe('meetup membership idempotency', () => {
  it('returns joined for an existing member without adding a duplicate notification', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result([{ max_people: 4, status: 'open' }]))
      .mockResolvedValueOnce(result([{ '?column?': 1 }]));
    const app = await createApp(meetupRoutes, '/api/meetups');

    const response = await app.inject({ method: 'POST', url: `/api/meetups/${submissionId}/join` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ joined: true });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(2);
    expect(mocks.clientQuery.mock.calls.some(([sql]) => (sql as string).includes('INSERT INTO notifications'))).toBe(false);
    await app.close();
  });
});

describe('route submission validation', () => {
  const validBody = {
    gymId,
    routeSetId,
    clientRequestId,
    name: '测试线路',
    grade: 'V3',
    color: '橙色',
    wallZone: null,
    coverUrl: 'https://example.com/route.jpg',
    points: [
      { x: 0.2, y: 0.8, type: 'start' },
      { x: 0.7, y: 0.2, type: 'finish' }
    ]
  };

  it('requires both a start and a finish point', async () => {
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      payload: { ...validBody, points: [{ x: 0.2, y: 0.8, type: 'start' }, { x: 0.4, y: 0.5, type: 'hold' }] }
    });

    expect(response.statusCode).toBe(400);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns the linked send state in the current user submission list', async () => {
    mocks.query.mockResolvedValueOnce(result([{
      id: submissionId,
      status: 'approved',
      published_route_id: routeId,
      send_id: sendId,
      send_moderation_status: 'pending'
    }]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({ method: 'GET', url: '/api/submissions/mine' });

    expect(response.statusCode).toBe(200);
    expect(response.json().items[0]).toMatchObject({
      published_route_id: routeId,
      send_id: sendId,
      send_moderation_status: 'pending'
    });
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain('LEFT JOIN sends s');
    expect(sql).toContain('s.id send_id');
    expect(sql).toContain('s.moderation_status send_moderation_status');
    expect(values).toEqual([viewerId]);
    await app.close();
  });

  it('rejects a route set that belongs to another gym', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: gymId }]))
      .mockResolvedValueOnce(result());
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({ method: 'POST', url: '/api/submissions', payload: validBody });

    expect(response.statusCode).toBe(400);
    expect(mocks.clientQuery).toHaveBeenCalledTimes(3);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('publishes the route immediately without creating a send when no video is supplied', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: gymId }]))
      .mockResolvedValueOnce(result([{ id: routeSetId }]))
      .mockResolvedValueOnce(result([{ id: submissionId, status: 'approved', video_url: null }]))
      .mockResolvedValueOnce(result([{ id: routeId }]))
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: submissionId, status: 'approved', published_route_id: routeId, video_url: null, send_id: null, send_moderation_status: null }]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({ method: 'POST', url: '/api/submissions', payload: validBody });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ status: 'approved', published_route_id: routeId, video_url: null, send_id: null, send_moderation_status: null });
    const statements = mocks.clientQuery.mock.calls.map(([sql]) => sql as string);
    expect(statements.some((sql) => sql.includes("'approved',now()"))).toBe(true);
    expect(statements.some((sql) => sql.includes('INSERT INTO routes'))).toBe(true);
    expect(statements.some((sql) => sql.includes('INSERT INTO sends'))).toBe(false);
    await app.close();
  });

  const optionalPhotoCases: { label: string; photo: Record<string, unknown>; videoUrl?: string }[] = [
    { label: 'omitted photo and markers', photo: {} },
    { label: 'null photo with omitted markers', photo: { coverUrl: null } },
    { label: 'omitted photo with empty markers', photo: { points: [] } },
    { label: 'null photo with empty markers and a video', photo: { coverUrl: null, points: [] }, videoUrl: 'https://example.com/first-send.mp4' },
    { label: 'omitted photo and markers with a video', photo: {}, videoUrl: 'https://example.com/first-send.mov' },
    { label: 'photo without markers', photo: { coverUrl: validBody.coverUrl } },
    { label: 'photo with empty markers and a video', photo: { coverUrl: validBody.coverUrl, points: [] }, videoUrl: 'https://example.com/first-send.mp4' }
  ];

  it.each(optionalPhotoCases)('publishes with $label', async ({ photo, videoUrl }) => {
    const { coverUrl: _coverUrl, points: _points, ...withoutPhoto } = validBody;
    const expectedCover = photo.coverUrl ?? null;
    const published = {
      id: submissionId,
      status: 'approved',
      cover_url: expectedCover,
      points: [],
      published_route_id: routeId,
      video_url: videoUrl ?? null,
      send_id: videoUrl ? sendId : null,
      send_moderation_status: videoUrl ? 'approved' : null
    };
    mocks.clientQuery
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: gymId }]))
      .mockResolvedValueOnce(result([{ id: routeSetId }]))
      .mockResolvedValueOnce(result([{ id: submissionId }]))
      .mockResolvedValueOnce(result([{ id: routeId }]));
    if (videoUrl) mocks.clientQuery.mockResolvedValueOnce(result([{ id: sendId }]));
    mocks.clientQuery
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([published]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      payload: { ...withoutPhoto, ...photo, videoUrl }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(published);
    const submissionCall = mocks.clientQuery.mock.calls.find(([sql]) => (sql as string).includes('INSERT INTO route_submissions'))!;
    const routeCall = mocks.clientQuery.mock.calls.find(([sql]) => (sql as string).includes('INSERT INTO routes'))!;
    expect(submissionCall[1][8]).toBe(expectedCover);
    expect(submissionCall[1][12]).toBe('[]');
    expect(routeCall[1][6]).toBe(expectedCover);
    expect(routeCall[1][7]).toBe('[]');
    const sendCalls = mocks.clientQuery.mock.calls.filter(([sql]) => (sql as string).includes('INSERT INTO sends'));
    expect(sendCalls).toHaveLength(videoUrl ? 1 : 0);
    if (videoUrl) expect(sendCalls[0]![1]).toEqual([viewerId, routeId, videoUrl, null, 'public', 'approved']);
    await app.close();
  });

  it.each([
    ['omitted photo', { coverUrl: undefined }],
    ['null photo', { coverUrl: null }],
    ['missing start', { points: [{ x: 0.5, y: 0.5, type: 'finish' }] }],
    ['missing finish', { points: [{ x: 0.5, y: 0.5, type: 'start' }] }],
    ['negative coordinate', { points: [{ x: -0.01, y: 0.5, type: 'start' }, validBody.points[1]] }],
    ['coordinate above one', { points: [validBody.points[0], { x: 0.5, y: 1.01, type: 'finish' }] }],
    ['more than eighty markers', { points: [...validBody.points, ...Array.from({ length: 79 }, () => ({ x: 0.5, y: 0.5, type: 'hold' }))] }]
  ])('rejects nonempty annotations with %s before creating records', async (_label, invalid) => {
    const app = await createApp(submissionRoutes, '/api/submissions');
    const response = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      payload: { ...validBody, ...(invalid as Record<string, unknown>) }
    });

    expect(response.statusCode).toBe(400);
    expect(mocks.transaction).not.toHaveBeenCalled();
    expect(mocks.clientQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('keeps photo-free publication idempotent when its response is retried', async () => {
    const { coverUrl: _coverUrl, points: _points, ...withoutPhoto } = validBody;
    const published = { id: submissionId, cover_url: null, points: [], status: 'approved', published_route_id: routeId };
    mocks.clientQuery.mockResolvedValueOnce(result([published]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({ method: 'POST', url: '/api/submissions', payload: withoutPhoto });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(published);
    expect(mocks.clientQuery).toHaveBeenCalledTimes(1);
    expect(mocks.clientQuery.mock.calls[0]![1]).toEqual([viewerId, clientRequestId]);
    await app.close();
  });

  it('stores an optional video and publishes its approved send with the chosen visibility', async () => {
    const videoBody = {
      ...validBody,
      videoUrl: 'https://example.com/route.mov',
      caption: '我刚标的线路',
      visibility: 'friends'
    };
    mocks.clientQuery
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: gymId }]))
      .mockResolvedValueOnce(result([{ id: routeSetId }]))
      .mockResolvedValueOnce(result([{ id: submissionId, status: 'approved', video_url: videoBody.videoUrl }]))
      .mockResolvedValueOnce(result([{ id: routeId }]))
      .mockResolvedValueOnce(result([{ id: sendId }]))
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: submissionId, status: 'approved', published_route_id: routeId, video_url: videoBody.videoUrl, send_id: sendId, send_moderation_status: 'approved' }]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({ method: 'POST', url: '/api/submissions', payload: videoBody });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      status: 'approved',
      published_route_id: routeId,
      video_url: videoBody.videoUrl,
      send_id: sendId,
      send_moderation_status: 'approved'
    });
    const sendCall = mocks.clientQuery.mock.calls.find(([sql]) => (sql as string).includes('INSERT INTO sends'))!;
    expect(sendCall[1]).toEqual([viewerId, routeId, videoBody.videoUrl, videoBody.caption, 'friends', 'approved']);
    await app.close();
  });

  it('publishes the route and its video immediately even in manual moderation mode', async () => {
    mocks.initialModerationStatus.mockReturnValue('pending');
    mocks.clientQuery
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: gymId }]))
      .mockResolvedValueOnce(result([{ id: routeSetId }]))
      .mockResolvedValueOnce(result([{ id: submissionId, status: 'approved', video_url: 'https://example.com/route.mp4' }]))
      .mockResolvedValueOnce(result([{ id: routeId }]))
      .mockResolvedValueOnce(result([{ id: sendId }]))
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{ id: submissionId, status: 'approved', published_route_id: routeId, send_id: sendId, send_moderation_status: 'approved' }]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      payload: { ...validBody, videoUrl: 'https://example.com/route.mp4' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      status: 'approved',
      published_route_id: routeId,
      send_moderation_status: 'approved'
    });
    const sendCall = mocks.clientQuery.mock.calls.find(([sql]) => (sql as string).includes('INSERT INTO sends'))!;
    expect(sendCall[1]).toEqual([viewerId, routeId, 'https://example.com/route.mp4', null, 'public', 'approved']);
    expect(mocks.initialModerationStatus).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns the first published submission for a repeated client request id', async () => {
    mocks.clientQuery.mockResolvedValueOnce(result([{
      id: submissionId,
      status: 'approved',
      published_route_id: routeId,
      video_url: 'https://example.com/route.mp4'
    }]));
    const app = await createApp(submissionRoutes, '/api/submissions');

    const response = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      payload: { ...validBody, videoUrl: 'https://example.com/route.mp4' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ id: submissionId, status: 'approved', published_route_id: routeId });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(1);
    expect(mocks.clientQuery.mock.calls[0]![0]).toContain('client_request_id=$2');
    await app.close();
  });

  it('limits pending submissions for a gym admin to assigned gyms', async () => {
    mocks.query.mockResolvedValue(result());
    const app = await createApp(submissionRoutes, '/api/submissions', 'gym_admin');

    const response = await app.inject({ method: 'GET', url: '/api/submissions/pending' });

    expect(response.statusCode).toBe(200);
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain('FROM gym_admins ga');
    expect(sql).toContain('ga.gym_id=rs.gym_id');
    expect(values).toEqual(['gym_admin', viewerId]);
    await app.close();
  });
});

describe('month dashboard contract', () => {
  it('rejects an impossible month before querying PostgreSQL', async () => {
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({
      method: 'GET',
      url: '/api/users/me/month-dashboard?month=2026-13'
    });

    expect(response.statusCode).toBe(400);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it('uses Shanghai month boundaries for every calendar query', async () => {
    mocks.query
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result([{
        climbing_days: 0,
        sends: 0,
        gyms: 0,
        max_grade: 0,
        flashes: 0,
        videos: 0
      }]))
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result());
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({
      method: 'GET',
      url: '/api/users/me/month-dashboard?month=2026-08'
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ month: '2026-08', days: [] });
    expect(mocks.query).toHaveBeenCalledTimes(4);
    for (const call of mocks.query.mock.calls) {
      expect(call[0]).toContain("AT TIME ZONE 'Asia/Shanghai'");
      expect(call[1]).toEqual([viewerId, '2026-08-01']);
    }
    await app.close();
  });
});
