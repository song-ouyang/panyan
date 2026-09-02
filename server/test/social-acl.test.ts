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
  role: 'user' | 'gym_admin' | 'admin' = 'user'
) {
  const app = Fastify();
  await app.register(sensible);
  app.decorate('authenticate', async (request) => {
    request.user = { sub: viewerId, role };
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
  it('updates an existing check-in without deleting its likes or comments', async () => {
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
    expect(response.json()).toMatchObject({ sendId, pointsEarned: 25, milestone: null });
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
    expect(values).toEqual([viewerId, null, 20, 'friends']);
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
    const app = await createApp(routeRoutes, '/api/routes');

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
    const app = await createApp(routeRoutes, '/api/routes');

    const response = await app.inject({ method: 'GET', url: `/api/routes/${routeId}` });

    expect(response.statusCode).toBe(200);
    expect(response.json().featuredSend).toBeNull();
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
});

describe('friendship idempotency', () => {
  it('replaces an existing relationship with a directional block', async () => {
    mocks.clientQuery
      .mockResolvedValueOnce(result([{ id: otherId }]))
      .mockResolvedValueOnce(result())
      .mockResolvedValueOnce(result());
    const app = await createApp(userRoutes, '/api/users');

    const response = await app.inject({ method: 'POST', url: `/api/users/${otherId}/block` });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ blocked: true });
    expect(mocks.clientQuery).toHaveBeenCalledTimes(3);
    expect(mocks.clientQuery.mock.calls[1]![0]).toContain('DELETE FROM friendships');
    expect(mocks.clientQuery.mock.calls[2]![0]).toContain("VALUES($1,$2,'blocked')");
    expect(mocks.clientQuery.mock.calls[2]![1]).toEqual([viewerId, otherId]);
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
