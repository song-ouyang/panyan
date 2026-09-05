import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config.js';
import { pool, query } from '../src/db.js';

const suite = process.env.RUN_DB_E2E === '1' ? describe : describe.skip;

suite('share API with dedicated local PostgreSQL', () => {
  let app: FastifyInstance;
  let gymId = '';
  const userIds: string[] = [];
  const suffix = randomUUID();

  beforeAll(async () => {
    const databaseUrl = config.DATABASE_URL ? new URL(config.DATABASE_URL) : null;
    const host = databaseUrl?.hostname ?? config.PGHOST;
    const database = databaseUrl?.pathname.slice(1) ?? config.PGDATABASE;
    if (config.NODE_ENV === 'production' || !['127.0.0.1', 'localhost', '::1', 'postgres'].includes(host)
      || !/(?:test|e2e|_ci$)/i.test(database)) {
      throw new Error('Share DB E2E requires a dedicated local test/e2e/CI database');
    }
    app = await buildApp();
    await app.ready();
  });

  afterAll(async () => {
    if (gymId) await query('DELETE FROM gyms WHERE id=$1', [gymId]);
    if (userIds.length) await query('DELETE FROM users WHERE id=ANY($1::uuid[])', [userIds]);
    if (app) await app.close();
    await pool.end();
  });

  async function createUser(name: string) {
    const inserted = await query<{ id: string }>(
      'INSERT INTO users(openid,nickname,avatar_url) VALUES($1,$2,$3) RETURNING id',
      [`share:e2e:${name}:${suffix}`, name, 'https://example.com/avatar.jpg']
    );
    const id = inserted.rows[0]!.id;
    userIds.push(id);
    return { id, headers: { authorization: `Bearer ${app.jwt.sign({ sub: id, role: 'user' })}` } };
  }

  it('executes live monthly aggregation, Shanghai bounds, token retries, ownership, rotation and deletion', async () => {
    const owner = await createUser('分享测试岩友');
    const stranger = await createUser('其他岩友');
    const gym = await query<{ id: string }>("INSERT INTO gyms(name,city,address) VALUES($1,'深圳市','绝不分享的地点') RETURNING id", [`Share E2E ${suffix}`]);
    gymId = gym.rows[0]!.id;
    const routeIds: string[] = [];
    const fixtureRecords = [
      { grade: 'V17', sentAt: '2024-07-31T15:59:59.999Z', status: 'approved', visibility: 'public', attempts: 1, video: null },
      { grade: 'V3', sentAt: '2024-07-31T16:00:00.000Z', status: 'approved', visibility: 'private', attempts: 1, video: null },
      { grade: 'V10', sentAt: '2024-08-31T15:59:59.999Z', status: 'approved', visibility: 'friends', attempts: 2, video: 'https://example.com/private-video.mp4' },
      { grade: 'V16', sentAt: '2024-08-31T16:00:00.000Z', status: 'approved', visibility: 'public', attempts: 1, video: null },
      { grade: 'V15', sentAt: '2024-08-10T09:00:00.000Z', status: 'pending', visibility: 'public', attempts: 1, video: null }
    ];
    for (const fixture of fixtureRecords) {
      const route = await query<{ id: string }>(
        "INSERT INTO routes(gym_id,name,grade,color) VALUES($1,'测试路线',$2,'橙色') RETURNING id", [gymId, fixture.grade]
      );
      routeIds.push(route.rows[0]!.id);
      await query(
        'INSERT INTO sends(user_id,route_id,sent_at,moderation_status,visibility,attempts,video_url,caption) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',
        [owner.id, route.rows[0]!.id, fixture.sentAt, fixture.status, fixture.visibility, fixture.attempts, fixture.video, '绝不分享的私密正文']
      );
    }
    // Non-route moments must not count as climbing records.
    await query("INSERT INTO sends(user_id,sent_at,caption) VALUES($1,'2024-08-10T09:00:00Z','只有动态没有线路')", [owner.id]);

    const create = () => app.inject({ method: 'POST', url: '/api/shares/monthly', headers: owner.headers, payload: { month: '2024-08' } });
    const initial = await app.inject({ url: '/api/shares/monthly?month=2024-08', headers: owner.headers });
    expect(initial.json()).toEqual({ token: null, month: '2024-08' });
    const [created, retried] = await Promise.all([create(), create()]);
    expect(created.statusCode).toBe(200);
    expect(retried.json()).toEqual(created.json());
    const token = created.json().token as string;
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const active = await app.inject({ url: '/api/shares/monthly?month=2024-08', headers: owner.headers });
    expect(active.json()).toEqual({ token, month: '2024-08' });
    const otherMonth = await app.inject({ url: '/api/shares/monthly?month=2024-08', headers: stranger.headers });
    expect(otherMonth.json().token).toBeNull();

    const publicMonth = await app.inject(`/api/shares/monthly/${token}`);
    expect(publicMonth.statusCode).toBe(200);
    expect(publicMonth.headers['cache-control']).toContain('no-store');
    expect(publicMonth.json()).toMatchObject({
      kind: 'monthly', month: '2024-08',
      author: { nickname: '分享测试岩友', avatar_url: 'https://example.com/avatar.jpg' },
      summary: { climbing_days: 2, sends: 2, gyms: 1, max_grade: 10, flashes: 1, videos: 1 },
      days: [{ day: '2024-08-01', sends: 1 }, { day: '2024-08-31', sends: 1 }],
      byGrade: [{ grade: 'V10', sends: 1 }, { grade: 'V3', sends: 1 }]
    });
    for (const secret of [owner.id, gymId, '绝不分享', 'private-video.mp4', ...routeIds]) {
      expect(publicMonth.body).not.toContain(secret);
    }
    const dashboard = await app.inject({ url: '/api/users/me/month-dashboard?month=2024-08', headers: owner.headers });
    expect(publicMonth.json().summary).toEqual(dashboard.json().summary);
    expect(publicMonth.json().byGrade).toEqual(dashboard.json().byGrade);

    const routeShare = await app.inject(`/api/shares/routes/${routeIds[1]}`);
    expect(routeShare.statusCode).toBe(200);
    expect(routeShare.json().route.send_count).toBe(0);
    expect(routeShare.json().route).not.toHaveProperty('featuredSend');
    await query('UPDATE routes SET published=false WHERE id=$1', [routeIds[1]]);
    expect((await app.inject(`/api/shares/routes/${routeIds[1]}`)).statusCode).toBe(404);

    const forbidden = await app.inject({ method: 'DELETE', url: `/api/shares/monthly/${token}`, headers: stranger.headers });
    expect(forbidden.statusCode).toBe(404);
    expect((await app.inject(`/api/shares/monthly/${token}`)).statusCode).toBe(200);

    // Updates to moderation and records take effect without remaking a link.
    await query("UPDATE sends SET moderation_status='rejected' WHERE user_id=$1 AND route_id=$2", [owner.id, routeIds[2]]);
    expect((await app.inject(`/api/shares/monthly/${token}`)).json().summary.sends).toBe(1);
    await query('DELETE FROM sends WHERE user_id=$1 AND route_id=$2', [owner.id, routeIds[1]]);
    const empty = await app.inject(`/api/shares/monthly/${token}`);
    expect(empty.json()).toMatchObject({ summary: { climbing_days: 0, sends: 0, gyms: 0, max_grade: 0, flashes: 0, videos: 0 }, days: [], byGrade: [] });

    for (let index = 0; index < 2; index += 1) {
      const revoked = await app.inject({ method: 'DELETE', url: `/api/shares/monthly/${token}`, headers: owner.headers });
      expect(revoked.statusCode).toBe(200);
      expect(revoked.json()).toEqual({ revoked: true });
    }
    const gone = await app.inject(`/api/shares/monthly/${token}`);
    expect(gone.statusCode).toBe(404);
    expect(gone.headers['cache-control']).toContain('no-store');
    expect((await app.inject({ url: '/api/shares/monthly?month=2024-08', headers: owner.headers })).json().token).toBeNull();
    const reshared = await create();
    const newToken = reshared.json().token as string;
    expect(newToken).not.toBe(token);
    expect((await app.inject(`/api/shares/monthly/${token}`)).statusCode).toBe(404);
    expect((await app.inject(`/api/shares/monthly/${newToken}`)).statusCode).toBe(200);
    // Retrying an old revocation must not revoke the replacement.
    expect((await app.inject({ method: 'DELETE', url: `/api/shares/monthly/${token}`, headers: owner.headers })).statusCode).toBe(200);
    expect((await app.inject(`/api/shares/monthly/${newToken}`)).statusCode).toBe(200);
    await query('DELETE FROM users WHERE id=$1', [owner.id]);
    expect((await app.inject(`/api/shares/monthly/${newToken}`)).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: '/api/shares/monthly', headers: owner.headers, payload: { month: '2024-08' } })).statusCode).toBe(401);
    const remaining = await query<{ count: number }>('SELECT count(*)::int count FROM monthly_record_shares WHERE user_id=$1', [owner.id]);
    expect(remaining.rows[0]!.count).toBe(0);
  });
});
