import type { FastifyPluginAsync } from 'fastify';
import { query, transaction } from '../db.js';
import { idParams, meetupBody } from '../schemas.js';

export const meetupRoutes: FastifyPluginAsync = async (app) => {
  app.get('/', { preHandler: app.authenticate }, async (request) => {
    const { gymId, mine } = request.query as { gymId?: string; mine?: string };
    const onlyMine = mine === 'true';
    const result = await query(
      `SELECT m.*,g.name gym_name,u.nickname creator_name,count(mm.user_id)::int member_count,
       bool_or(mm.user_id=$2) joined
       FROM meetups m JOIN gyms g ON g.id=m.gym_id JOIN users u ON u.id=m.creator_id
       LEFT JOIN meetup_members mm ON mm.meetup_id=m.id
       WHERE ($1::uuid IS NULL OR m.gym_id=$1)
         AND (($3::boolean=false AND m.status='open' AND m.starts_at>now())
           OR ($3::boolean=true AND EXISTS(SELECT 1 FROM meetup_members mine_mm WHERE mine_mm.meetup_id=m.id AND mine_mm.user_id=$2)))
       GROUP BY m.id,g.id,u.id
       ORDER BY CASE WHEN m.status='open' AND m.starts_at>now() THEN 0 ELSE 1 END,m.starts_at DESC`, [gymId ?? null, request.user.sub, onlyMine]
    );
    return { items: result.rows };
  });
  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const body = meetupBody.parse(request.body);
    return transaction(async (client) => {
      const result = await client.query(
        `INSERT INTO meetups(creator_id,gym_id,title,starts_at,max_people,note) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
        [request.user.sub, body.gymId, body.title, body.startsAt, body.maxPeople, body.note ?? null]
      );
      await client.query('INSERT INTO meetup_members(meetup_id,user_id) VALUES($1,$2)', [result.rows[0].id, request.user.sub]);
      return result.rows[0];
    });
  });
  app.post('/:id/join', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    return transaction(async (client) => {
      const meetup = await client.query(`SELECT max_people,status FROM meetups WHERE id=$1 FOR UPDATE`, [id]);
      if (!meetup.rowCount || meetup.rows[0].status !== 'open') throw app.httpErrors.notFound('约爬不存在或已结束');
      const existingMember = await client.query(
        'SELECT 1 FROM meetup_members WHERE meetup_id=$1 AND user_id=$2',
        [id, request.user.sub]
      );
      if (existingMember.rowCount) return { joined: true };
      const count = await client.query('SELECT count(*)::int count FROM meetup_members WHERE meetup_id=$1', [id]);
      if (count.rows[0].count >= meetup.rows[0].max_people) throw app.httpErrors.conflict('人数已满');
      await client.query('INSERT INTO meetup_members(meetup_id,user_id) VALUES($1,$2)', [id, request.user.sub]);
      await client.query(`INSERT INTO notifications(user_id,type,title,content,target_path) SELECT creator_id,'meetup_join','新的约爬成员','有岩友加入了你发起的约爬','/pages/meetups/index' FROM meetups WHERE id=$1 AND creator_id<>$2`, [id,request.user.sub]);
      return { joined: true };
    });
  });
  app.delete('/:id/join', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const meetup = await query('SELECT creator_id FROM meetups WHERE id=$1', [id]);
    if (!meetup.rowCount) throw app.httpErrors.notFound('约爬不存在');
    if (meetup.rows[0]!.creator_id === request.user.sub) throw app.httpErrors.badRequest('发起人不能退出，请取消约爬');
    await query('DELETE FROM meetup_members WHERE meetup_id=$1 AND user_id=$2', [id,request.user.sub]);
    return { joined: false };
  });
  app.delete('/:id', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(`UPDATE meetups SET status='cancelled' WHERE id=$1 AND creator_id=$2 AND status='open' RETURNING id`, [id,request.user.sub]);
    if (!result.rowCount) throw app.httpErrors.notFound('约爬不存在或无权取消');
    await query(`INSERT INTO notifications(user_id,type,title,content,target_path) SELECT user_id,'meetup_cancelled','约爬已取消','发起人取消了本次约爬','/pages/meetups/index' FROM meetup_members WHERE meetup_id=$1 AND user_id<>$2`, [id,request.user.sub]);
    return { cancelled: true };
  });
};
