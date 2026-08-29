import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query, transaction } from '../db.js';
import { idParams } from '../schemas.js';

const createCard = z.object({
  gymId: z.string().uuid(),
  title: z.string().trim().min(2).max(80),
  visits: z.number().int().min(1).max(100),
  expiresOn: z.string().date().nullable().optional(),
  note: z.string().trim().max(200).nullable().optional(),
});

export const visitCardRoutes: FastifyPluginAsync = async (app) => {
  app.get('/', { preHandler: app.authenticate }, async (request) => {
    const { gymId, mine } = request.query as { gymId?: string; mine?: string };
    const result = await query(
      `SELECT c.*,g.name gym_name,g.city,g.address,u.nickname creator_name,
       (c.status='open' AND (c.expires_on IS NULL OR c.expires_on>=current_date)) AS claimable
       FROM gym_visit_cards c JOIN gyms g ON g.id=c.gym_id JOIN users u ON u.id=c.creator_id
       WHERE ($1::uuid IS NULL OR c.gym_id=$1)
         AND ($2::boolean=false OR c.creator_id=$3 OR c.claimed_by=$3)
         AND ($2::boolean=true OR (c.status='open' AND (c.expires_on IS NULL OR c.expires_on>=current_date)))
       ORDER BY c.created_at DESC`, [gymId ?? null, mine === 'true', request.user.sub]
    );
    return { items: result.rows };
  });

  app.get('/:id', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    const result = await query(
      `SELECT c.*,g.name gym_name,g.city,g.address,u.nickname creator_name,
       (c.status='open' AND (c.expires_on IS NULL OR c.expires_on>=current_date)) AS claimable
       FROM gym_visit_cards c JOIN gyms g ON g.id=c.gym_id JOIN users u ON u.id=c.creator_id WHERE c.id=$1`, [id]
    );
    if (!result.rowCount) throw app.httpErrors.notFound('次卡不存在');
    return result.rows[0];
  });

  app.post('/', { preHandler: app.authenticate }, async (request) => {
    const b = createCard.parse(request.body);
    const gym = await query('SELECT id FROM gyms WHERE id=$1', [b.gymId]);
    if (!gym.rowCount) throw app.httpErrors.notFound('岩馆不存在');
    const result = await query(
      `INSERT INTO gym_visit_cards(gym_id,creator_id,title,visits_total,visits_remaining,expires_on,note)
       VALUES($1,$2,$3,$4,$4,$5,$6) RETURNING *`,
      [b.gymId,request.user.sub,b.title,b.visits,b.expiresOn ?? null,b.note ?? null]
    );
    return result.rows[0];
  });

  app.post('/:id/claim', { preHandler: app.authenticate }, async (request) => {
    const { id } = idParams.parse(request.params);
    return transaction(async (client) => {
      const card = await client.query<{ creator_id: string; gym_name: string; status: string; expired: boolean }>(
        `SELECT c.creator_id,c.status,(c.expires_on IS NOT NULL AND c.expires_on<current_date) expired,g.name gym_name
         FROM gym_visit_cards c JOIN gyms g ON g.id=c.gym_id WHERE c.id=$1 FOR UPDATE`, [id]
      );
      const item = card.rows[0];
      if (!item || item.status !== 'open' || item.expired) throw app.httpErrors.conflict('这张次卡已不可领取');
      if (item.creator_id === request.user.sub) throw app.httpErrors.badRequest('不能领取自己的次卡');
      const claimed = await client.query(`UPDATE gym_visit_cards SET status='claimed',claimed_by=$2,claimed_at=now() WHERE id=$1 RETURNING *`, [id,request.user.sub]);
      await client.query(`INSERT INTO notifications(user_id,type,title,content,target_path) VALUES($1,'visit_card_claimed','次卡已被领取',$2,$3)`, [item.creator_id,`你的${item.gym_name}次卡已被岩友领取`,`/pages/visit-card/index?id=${id}`]);
      return claimed.rows[0];
    });
  });
};
