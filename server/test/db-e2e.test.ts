import { randomUUID } from 'node:crypto';
import { rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config.js';
import { pool, query } from '../src/db.js';

const runDatabaseE2E = process.env.RUN_DB_E2E === '1';
const suite = runDatabaseE2E ? describe : describe.skip;

type Session = { token: string; user: { id: string } };

suite('real PostgreSQL API flow', () => {
  let app: FastifyInstance;
  const suffix = randomUUID();
  const createdUserIds: string[] = [];
  let gymId = '';
  let uploadedRelativePath = '';

  const authHeader = (session: Session) => ({ authorization: `Bearer ${session.token}` });

  async function devLogin(label: string): Promise<Session> {
    const response = await app.inject({
      method: 'POST',
      url: '/api/auth/wechat',
      payload: { code: `dev:e2e:${label}:${suffix}` }
    });
    expect(response.statusCode).toBe(200);
    const session = response.json() as Session;
    createdUserIds.push(session.user.id);
    return session;
  }

  beforeAll(async () => {
    if (config.NODE_ENV === 'production') {
      throw new Error('RUN_DB_E2E must never run against NODE_ENV=production');
    }
    app = await buildApp();
    await app.ready();
  });

  afterAll(async () => {
    if (gymId) await query('DELETE FROM gyms WHERE id=$1', [gymId]);
    if (createdUserIds.length) await query('DELETE FROM users WHERE id=ANY($1::uuid[])', [createdUserIds]);
    if (uploadedRelativePath) {
      await rm(resolve(config.UPLOAD_DIR, uploadedRelativePath), { force: true });
    }
    if (app) await app.close();
    await pool.end();
  });

  it('covers auth, profiles, friends, feeds, routes, direct submission, check-ins and interactions', async () => {
    const owner = await devLogin('owner');
    const friend = await devLogin('friend');
    const stranger = await devLogin('stranger');

    for (const [session, nickname] of [[owner, '线路主理人'], [friend, '岩友小林'], [stranger, '陌生岩友']] as const) {
      const profile = await app.inject({
        method: 'PATCH',
        url: '/api/users/me',
        headers: authHeader(session),
        payload: { nickname, bio: '真实数据库回归账号' }
      });
      expect(profile.statusCode).toBe(200);
      expect(profile.json()).toMatchObject({ nickname, profile_completed: true });
    }

    const gym = await query<{ id: string }>(
      `INSERT INTO gyms(name,city,province,district,address,verified)
       VALUES($1,'深圳市','广东省','南山区','E2E 测试地址',true) RETURNING id`,
      [`E2E 岩馆 ${suffix}`]
    );
    gymId = gym.rows[0]!.id;
    const routeSet = await query<{ id: string }>(
      `INSERT INTO route_sets(gym_id,name,starts_on,active) VALUES($1,'E2E 换线周期',current_date,true) RETURNING id`,
      [gymId]
    );
    const routeSetId = routeSet.rows[0]!.id;

    const directory = await app.inject({ method: 'GET', url: `/api/gyms?city=${encodeURIComponent('深圳市')}&q=E2E` });
    expect(directory.statusCode).toBe(200);
    expect(directory.json().items.some((item: { id: string }) => item.id === gymId)).toBe(true);

    const clientRequestId = randomUUID();
    const submissionPayload = {
      gymId,
      routeSetId,
      clientRequestId,
      name: 'E2E 橙色线',
      grade: 'V3',
      color: '橙色',
      wallZone: 'A 区',
      coverUrl: 'https://cdn.example.com/e2e-route.jpg',
      videoUrl: 'https://cdn.example.com/e2e-route.mp4',
      caption: '线路创建后同步到广场',
      visibility: 'public',
      points: [
        { x: 0.2, y: 0.8, type: 'start' },
        { x: 0.45, y: 0.5, type: 'hold' },
        { x: 0.7, y: 0.2, type: 'finish' }
      ]
    };
    const submitted = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      headers: authHeader(owner),
      payload: submissionPayload
    });
    expect(submitted.statusCode).toBe(200);
    expect(submitted.json()).toMatchObject({
      status: 'approved',
      video_url: submissionPayload.videoUrl,
      send_moderation_status: 'approved'
    });
    const routeId = submitted.json().published_route_id as string;
    const checkinId = submitted.json().send_id as string;
    expect(routeId).toBeTruthy();
    expect(checkinId).toBeTruthy();

    const retried = await app.inject({
      method: 'POST',
      url: '/api/submissions',
      headers: authHeader(owner),
      payload: submissionPayload
    });
    expect(retried.statusCode).toBe(200);
    expect(retried.json()).toMatchObject({ id: submitted.json().id, published_route_id: routeId, send_id: checkinId });

    const routeCount = await query<{ count: number }>(
      'SELECT count(*)::int count FROM routes WHERE gym_id=$1 AND name=$2',
      [gymId, submissionPayload.name]
    );
    expect(routeCount.rows[0]!.count).toBe(1);

    const submittedSend = await query<{ moderation_status: string }>(
      'SELECT moderation_status FROM sends WHERE id=$1',
      [checkinId]
    );
    expect(submittedSend.rows[0]!.moderation_status).toBe('approved');
    const filteredRoutes = await app.inject({
      method: 'GET',
      url: `/api/gyms/${gymId}/routes?grade=V3&setId=${routeSetId}`
    });
    expect(filteredRoutes.statusCode).toBe(200);
    expect(filteredRoutes.json().items).toHaveLength(1);
    expect(filteredRoutes.json().items[0]).toMatchObject({ id: routeId, grade: 'V3' });

    const friendRequest = await app.inject({
      method: 'POST',
      url: `/api/users/${friend.user.id}/friend-request`,
      headers: authHeader(owner)
    });
    expect(friendRequest.statusCode).toBe(200);
    expect(friendRequest.json()).toEqual({ status: 'pending' });
    const accepted = await app.inject({
      method: 'POST',
      url: `/api/users/${owner.user.id}/friend-accept`,
      headers: authHeader(friend)
    });
    expect(accepted.statusCode).toBe(200);
    expect(accepted.json()).toEqual({ status: 'accepted' });

    const friendsMoment = await app.inject({
      method: 'POST',
      url: '/api/sends/moments',
      headers: authHeader(owner),
      payload: { caption: '只给岩友看', imageUrls: ['https://cdn.example.com/friends.jpg'], visibility: 'friends' }
    });
    expect(friendsMoment.statusCode).toBe(200);
    const friendsMomentId = friendsMoment.json().id as string;
    await query("UPDATE sends SET moderation_status='approved' WHERE id=$1", [friendsMomentId]);

    const publicMoment = await app.inject({
      method: 'POST',
      url: '/api/sends/moments',
      headers: authHeader(owner),
      payload: { caption: '广场公开图文', imageUrls: ['https://cdn.example.com/square.jpg'], visibility: 'public' }
    });
    expect(publicMoment.statusCode).toBe(200);
    const publicMomentId = publicMoment.json().id as string;
    await query("UPDATE sends SET moderation_status='approved' WHERE id=$1", [publicMomentId]);

    const friendFeed = await app.inject({ method: 'GET', url: '/api/sends/feed?scope=friends', headers: authHeader(friend) });
    expect(friendFeed.statusCode).toBe(200);
    expect(friendFeed.json().items.map((item: { id: string }) => item.id)).toEqual(expect.arrayContaining([friendsMomentId, publicMomentId]));
    const strangerFeed = await app.inject({ method: 'GET', url: '/api/sends/feed?scope=friends', headers: authHeader(stranger) });
    expect(strangerFeed.statusCode).toBe(200);
    expect(strangerFeed.json().items.map((item: { id: string }) => item.id)).not.toContain(friendsMomentId);
    const square = await app.inject({ method: 'GET', url: '/api/sends/feed?scope=square', headers: authHeader(stranger) });
    expect(square.statusCode).toBe(200);
    expect(square.json().items.map((item: { id: string }) => item.id)).toContain(publicMomentId);
    expect(square.json().items.map((item: { id: string }) => item.id)).not.toContain(friendsMomentId);

    const hiddenDetail = await app.inject({ method: 'GET', url: `/api/sends/${friendsMomentId}`, headers: authHeader(stranger) });
    expect(hiddenDetail.statusCode).toBe(404);
    const visibleDetail = await app.inject({ method: 'GET', url: `/api/sends/${friendsMomentId}`, headers: authHeader(friend) });
    expect(visibleDetail.statusCode).toBe(200);

    const liked = await app.inject({ method: 'POST', url: `/api/sends/${checkinId}/like`, headers: authHeader(friend) });
    expect(liked.statusCode).toBe(200);
    const commented = await app.inject({
      method: 'POST',
      url: `/api/sends/${checkinId}/comments`,
      headers: authHeader(friend),
      payload: { content: '这条线很棒' }
    });
    expect(commented.statusCode).toBe(200);
    await query("UPDATE comments SET moderation_status='approved' WHERE id=$1", [commented.json().id]);

    const updatedCheckin = await app.inject({
      method: 'POST',
      url: '/api/sends',
      headers: authHeader(owner),
      payload: {
        routeId,
        attempts: 2,
        videoUrl: 'https://cdn.example.com/e2e-route-updated.mp4',
        caption: '更新视频但保留互动',
        visibility: 'public'
      }
    });
    expect(updatedCheckin.statusCode).toBe(200);
    expect(updatedCheckin.json().sendId).toBe(checkinId);
    await query("UPDATE sends SET moderation_status='approved' WHERE id=$1", [checkinId]);

    const preserved = await app.inject({ method: 'GET', url: `/api/sends/${checkinId}`, headers: authHeader(friend) });
    expect(preserved.statusCode).toBe(200);
    expect(preserved.json()).toMatchObject({ like_count: 1, comment_count: 1, liked: true });
    expect(preserved.json().comments).toHaveLength(1);

    const routeDetail = await app.inject({ method: 'GET', url: `/api/routes/${routeId}` });
    expect(routeDetail.statusCode).toBe(200);
    expect(routeDetail.json().featuredSend).toMatchObject({ id: checkinId, video_url: 'https://cdn.example.com/e2e-route-updated.mp4' });

    const publicProfile = await app.inject({
      method: 'GET',
      url: `/api/users/${owner.user.id}/public`,
      headers: authHeader(friend)
    });
    expect(publicProfile.statusCode).toBe(200);
    expect(publicProfile.json()).toMatchObject({ nickname: '线路主理人', friendship: 'accepted' });

    // A pending video remains visible in "my sends", but it must not alter
    // growth cards, calendars or rankings until moderation approves it.
    const pendingRoute = await query<{ id: string }>(
      `INSERT INTO routes(gym_id,route_set_id,name,grade,color,cover_url,points)
       VALUES($1,$2,'E2E 待审线路','V7','紫色','https://cdn.example.com/pending.jpg',$3) RETURNING id`,
      [gymId, routeSetId, JSON.stringify([
        { x: 0.2, y: 0.8, type: 'start' },
        { x: 0.7, y: 0.2, type: 'finish' }
      ])]
    );
    const pendingSend = await query<{ id: string }>(
      `INSERT INTO sends(user_id,route_id,attempts,video_url,visibility,moderation_status)
       VALUES($1,$2,1,'https://cdn.example.com/pending.mp4','public','pending') RETURNING id`,
      [owner.user.id, pendingRoute.rows[0]!.id]
    );

    const regions = await app.inject({ method: 'GET', url: '/api/rankings/regions' });
    expect(regions.statusCode).toBe(200);
    expect(regions.json().items).toContainEqual({ province: '广东省', city: '深圳市' });
    for (const queryString of [
      'scope=national',
      `scope=province&province=${encodeURIComponent('广东省')}`,
      `scope=city&province=${encodeURIComponent('广东省')}&city=${encodeURIComponent('深圳市')}`
    ]) {
      const ranking = await app.inject({
        method: 'GET',
        url: `/api/rankings?${queryString}`,
        headers: authHeader(owner)
      });
      expect(ranking.statusCode).toBe(200);
      const ownerRow = ranking.json().items.find((item: { user_id: string }) => item.user_id === owner.user.id);
      expect(ownerRow).toMatchObject({ max_grade: 3, send_count: 1 });
      expect(ownerRow.points).toBeGreaterThanOrEqual(27);
      expect(ranking.json().myRank).toMatchObject({ user_id: owner.user.id });
      expect(ranking.json().scoring).toEqual({ completion: 10, gradeStep: 5, flash: 5, like: 2 });
    }
    const routeRanking = await app.inject({
      method: 'GET',
      url: `/api/rankings/routes?gymId=${gymId}&setId=${routeSetId}`
    });
    expect(routeRanking.statusCode).toBe(200);
    expect(routeRanking.json().items).toContainEqual(expect.objectContaining({
      route_id: routeId,
      completion_count: 1,
      top_send_id: checkinId
    }));

    const me = await app.inject({ method: 'GET', url: '/api/users/me', headers: authHeader(owner) });
    expect(me.statusCode).toBe(200);
    expect(me.json().stats).toMatchObject({ total_sends: 1, gym_count: 1, max_grade: 3 });
    const growth = await app.inject({ method: 'GET', url: '/api/users/me/growth?months=6', headers: authHeader(owner) });
    expect(growth.statusCode).toBe(200);
    expect(growth.json().items).toContainEqual(expect.objectContaining({ grade: 'V3', sends: 1 }));
    const monthDashboard = await app.inject({ method: 'GET', url: '/api/users/me/month-dashboard', headers: authHeader(owner) });
    expect(monthDashboard.statusCode).toBe(200);
    expect(monthDashboard.json().summary).toMatchObject({ sends: 1, gyms: 1, max_grade: 3 });

    const boundaryRoutes: string[] = [];
    for (const [name, grade] of [['月界内', 'V1'], ['月界前', 'V2'], ['月界后', 'V4']] as const) {
      const created = await query<{ id: string }>(
        `INSERT INTO routes(gym_id,route_set_id,name,grade,color,cover_url,points)
         VALUES($1,$2,$3,$4,'白色','https://cdn.example.com/month-boundary.jpg',$5) RETURNING id`,
        [gymId, routeSetId, `E2E ${name}`, grade, JSON.stringify([
          { x: 0.2, y: 0.8, type: 'start' },
          { x: 0.7, y: 0.2, type: 'finish' }
        ])]
      );
      boundaryRoutes.push(created.rows[0]!.id);
    }
    await query(
      `INSERT INTO sends(user_id,route_id,attempts,visibility,moderation_status,sent_at)
       VALUES($1,$2,1,'private','approved','2024-07-31T16:30:00Z'),
             ($1,$3,1,'private','approved','2024-07-31T15:30:00Z'),
             ($1,$4,1,'private','approved','2024-08-31T16:30:00Z')`,
      [owner.user.id, ...boundaryRoutes]
    );
    const boundaryCalendar = await app.inject({
      method: 'GET',
      url: '/api/users/me/month-dashboard?month=2024-08',
      headers: authHeader(owner)
    });
    expect(boundaryCalendar.statusCode).toBe(200);
    expect(boundaryCalendar.json().days).toEqual([
      expect.objectContaining({ day: '2024-08-01', grade: 'V1', sends: 1 })
    ]);
    expect(boundaryCalendar.json().summary).toMatchObject({ climbing_days: 1, sends: 1, max_grade: 1 });

    const growthSummary = await app.inject({
      method: 'GET',
      url: `/api/users/me/growth-summary?gymId=${gymId}&setId=${routeSetId}`,
      headers: authHeader(owner)
    });
    expect(growthSummary.statusCode).toBe(200);
    expect(growthSummary.json().byGrade).toContainEqual({ grade: 'V3', sends: 1 });
    const cycleSummary = await app.inject({ method: 'GET', url: '/api/users/me/cycle-summary', headers: authHeader(owner) });
    expect(cycleSummary.statusCode).toBe(200);
    expect(cycleSummary.json().items).toContainEqual(expect.objectContaining({ route_set_id: routeSetId, grade: 'V3', sends: 1 }));
    const mySends = await app.inject({ method: 'GET', url: '/api/users/me/sends', headers: authHeader(owner) });
    expect(mySends.statusCode).toBe(200);
    expect(mySends.json().items.map((item: { id: string }) => item.id)).toEqual(
      expect.arrayContaining([checkinId, friendsMomentId, publicMomentId, pendingSend.rows[0]!.id])
    );

    const meetup = await app.inject({
      method: 'POST',
      url: '/api/meetups',
      headers: authHeader(owner),
      payload: {
        gymId,
        title: 'E2E 周末约爬',
        startsAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        maxPeople: 3,
        note: '带好岩鞋'
      }
    });
    expect(meetup.statusCode).toBe(200);
    const meetupId = meetup.json().id as string;
    const openMeetups = await app.inject({
      method: 'GET',
      url: `/api/meetups?gymId=${gymId}`,
      headers: authHeader(friend)
    });
    expect(openMeetups.statusCode).toBe(200);
    expect(openMeetups.json().items).toContainEqual(expect.objectContaining({ id: meetupId, joined: false, member_count: 1 }));

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const joined = await app.inject({ method: 'POST', url: `/api/meetups/${meetupId}/join`, headers: authHeader(friend) });
      expect(joined.statusCode).toBe(200);
      expect(joined.json()).toEqual({ joined: true });
    }
    const firstJoinNotificationCount = await query<{ count: number }>(
      "SELECT count(*)::int count FROM notifications WHERE user_id=$1 AND type='meetup_join'",
      [owner.user.id]
    );
    expect(firstJoinNotificationCount.rows[0]!.count).toBe(1);
    const joinedMine = await app.inject({ method: 'GET', url: '/api/meetups?mine=true', headers: authHeader(friend) });
    expect(joinedMine.statusCode).toBe(200);
    expect(joinedMine.json().items).toContainEqual(expect.objectContaining({ id: meetupId, joined: true }));

    const left = await app.inject({ method: 'DELETE', url: `/api/meetups/${meetupId}/join`, headers: authHeader(friend) });
    expect(left.statusCode).toBe(200);
    expect(left.json()).toEqual({ joined: false });
    const afterLeaving = await app.inject({ method: 'GET', url: '/api/meetups?mine=true', headers: authHeader(friend) });
    expect(afterLeaving.statusCode).toBe(200);
    expect(afterLeaving.json().items.map((item: { id: string }) => item.id)).not.toContain(meetupId);
    const rejoined = await app.inject({ method: 'POST', url: `/api/meetups/${meetupId}/join`, headers: authHeader(friend) });
    expect(rejoined.statusCode).toBe(200);
    const cancelled = await app.inject({ method: 'DELETE', url: `/api/meetups/${meetupId}`, headers: authHeader(owner) });
    expect(cancelled.statusCode).toBe(200);
    expect(cancelled.json()).toEqual({ cancelled: true });
    const cancelledMine = await app.inject({ method: 'GET', url: '/api/meetups?mine=true', headers: authHeader(friend) });
    expect(cancelledMine.statusCode).toBe(200);
    expect(cancelledMine.json().items).toContainEqual(expect.objectContaining({ id: meetupId, status: 'cancelled' }));

    const friendNotifications = await app.inject({ method: 'GET', url: '/api/notifications', headers: authHeader(friend) });
    expect(friendNotifications.statusCode).toBe(200);
    expect(friendNotifications.json().items).toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'friend_request' }),
      expect.objectContaining({ type: 'meetup_cancelled' })
    ]));
    const unreadBefore = friendNotifications.json().unread as number;
    const notificationId = friendNotifications.json().items[0].id as string;
    const readOne = await app.inject({
      method: 'POST',
      url: `/api/notifications/${notificationId}/read`,
      headers: authHeader(friend)
    });
    expect(readOne.statusCode).toBe(200);
    const afterReadOne = await app.inject({ method: 'GET', url: '/api/notifications', headers: authHeader(friend) });
    expect(afterReadOne.json().unread).toBe(unreadBefore - 1);
    expect(afterReadOne.json().items.find((item: { id: string }) => item.id === notificationId).read_at).toBeTruthy();
    const readAll = await app.inject({ method: 'POST', url: '/api/notifications/read-all', headers: authHeader(friend) });
    expect(readAll.statusCode).toBe(200);
    const afterReadAll = await app.inject({ method: 'GET', url: '/api/notifications', headers: authHeader(friend) });
    expect(afterReadAll.json().unread).toBe(0);

    for (const [reason, detail] of [['spam', '首次举报'], ['false_info', '更新举报原因']] as const) {
      const reported = await app.inject({
        method: 'POST',
        url: '/api/reports',
        headers: authHeader(stranger),
        payload: { targetType: 'send', targetId: publicMomentId, reason, detail }
      });
      expect(reported.statusCode).toBe(200);
      expect(reported.json()).toEqual({ reported: true });
    }
    const reportState = await query<{ count: number; reason: string; detail: string }>(
      `SELECT count(*)::int count,max(reason) reason,max(detail) detail
       FROM reports WHERE reporter_id=$1 AND target_type='send' AND target_id=$2`,
      [stranger.user.id, publicMomentId]
    );
    expect(reportState.rows[0]).toMatchObject({ count: 1, reason: 'false_info', detail: '更新举报原因' });

    if (config.UPLOAD_MODE === 'local') {
      const boundary = `----wanpan-e2e-${suffix}`;
      const payload = Buffer.from(
        `--${boundary}\r\n` +
        'Content-Disposition: form-data; name="file"; filename="avatar.html"\r\n' +
        'Content-Type: image/jpeg\r\n\r\n' +
        'e2e-image-bytes\r\n' +
        `--${boundary}--\r\n`
      );
      const upload = await app.inject({
        method: 'POST',
        url: '/api/uploads',
        headers: { ...authHeader(owner), 'content-type': `multipart/form-data; boundary=${boundary}` },
        payload
      });
      expect(upload.statusCode).toBe(200);
      expect(upload.json().url).toMatch(/\.jpg$/);
      uploadedRelativePath = new URL(upload.json().url).pathname.replace(/^\/uploads\//, '');
    }

    const disposable = await devLogin('disposable-account');
    const deleted = await app.inject({ method: 'DELETE', url: '/api/users/me', headers: authHeader(disposable) });
    expect(deleted.statusCode).toBe(200);
    expect(deleted.json()).toEqual({ deleted: true });
    const deletedSession = await app.inject({ method: 'GET', url: '/api/users/me', headers: authHeader(disposable) });
    expect(deletedSession.statusCode).toBe(401);
    const deletedCount = await query<{ count: number }>('SELECT count(*)::int count FROM users WHERE id=$1', [disposable.user.id]);
    expect(deletedCount.rows[0]!.count).toBe(0);
  }, 30_000);
});
