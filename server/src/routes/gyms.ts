import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query } from '../db.js';
import { idParams } from '../schemas.js';

export const gymRoutes: FastifyPluginAsync = async (app) => {
  app.get('/directory', async (request) => {
    const { city, q } = request.query as { city?: string; q?: string };
    const result = await query(
      `SELECT g.city,coalesce(b.id,g.id) brand_id,
       coalesce(b.name,g.name) brand_name,b.logo_url,count(DISTINCT g.id)::int store_count,
       count(DISTINCT r.id)::int route_count,bool_or(g.verified) verified
       FROM gyms g LEFT JOIN gym_brands b ON b.id=g.brand_id LEFT JOIN routes r ON r.gym_id=g.id AND r.published=true
       WHERE ($1::text IS NULL OR g.city=$1) AND ($2::text IS NULL OR coalesce(b.name,g.name) ILIKE '%'||$2||'%')
       GROUP BY g.city,coalesce(b.id,g.id),coalesce(b.name,g.name),b.logo_url
       ORDER BY brand_name`, [city ?? null,q ?? null]
    );
    return { items: result.rows };
  });

  app.get('/brands/:id/stores', async (request) => {
    const { id } = idParams.parse(request.params);
    const brand = await query('SELECT * FROM gym_brands WHERE id=$1', [id]);
    const stores = await query(
      `SELECT g.*,count(DISTINCT r.id)::int route_count FROM gyms g LEFT JOIN routes r ON r.gym_id=g.id AND r.published=true
       WHERE g.brand_id=$1 GROUP BY g.id ORDER BY g.district,g.name`, [id]
    );
    if (!brand.rowCount) {
      const gym = await query(`SELECT g.*,g.cover_url logo_url,count(DISTINCT r.id)::int route_count FROM gyms g LEFT JOIN routes r ON r.gym_id=g.id AND r.published=true WHERE g.id=$1 GROUP BY g.id`, [id]);
      if (!gym.rowCount) throw app.httpErrors.notFound('岩馆品牌不存在');
      return { ...gym.rows[0], stores: [gym.rows[0]] };
    }
    return { ...brand.rows[0], stores: stores.rows };
  });

  app.get('/', async (request) => {
    const { city, q } = request.query as { city?: string; q?: string };
    const result = await query(
      `SELECT g.*, count(DISTINCT r.id)::int route_count
       FROM gyms g LEFT JOIN routes r ON r.gym_id=g.id AND r.published=true
       WHERE ($1::text IS NULL OR g.city=$1) AND ($2::text IS NULL OR g.name ILIKE '%'||$2||'%')
       GROUP BY g.id ORDER BY g.verified DESC,g.name`, [city ?? null, q ?? null]
    );
    return { items: result.rows };
  });

  app.get('/:id', async (request) => {
    const { id } = idParams.parse(request.params);
    const gym = await query('SELECT * FROM gyms WHERE id=$1', [id]);
    if (!gym.rowCount) throw app.httpErrors.notFound('岩馆不存在');
    const sets = await query('SELECT * FROM route_sets WHERE gym_id=$1 ORDER BY starts_on DESC', [id]);
    return { ...gym.rows[0], routeSets: sets.rows };
  });

  app.get('/:id/routes', async (request) => {
    const { id } = idParams.parse(request.params);
    const { grade, setId } = z.object({
      grade: z.string().regex(/^V([0-9]|1[0-7])$/).optional(),
      setId: z.string().uuid().optional()
    }).parse(request.query);
    const result = await query(
      `SELECT r.*, count(s.id)::int send_count
       FROM routes r LEFT JOIN sends s ON s.route_id=r.id
         AND s.moderation_status='approved' AND s.visibility='public' AND s.video_url IS NOT NULL
       WHERE r.gym_id=$1 AND r.published=true
         AND ($2::text IS NULL OR r.grade=$2) AND ($3::uuid IS NULL OR r.route_set_id=$3)
       GROUP BY r.id ORDER BY substring(r.grade from 2)::int,r.name`, [id, grade ?? null, setId ?? null]
    );
    return { items: result.rows };
  });
};
