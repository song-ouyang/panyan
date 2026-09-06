import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { transaction } from '../db.js';
import { consumeGrowthPresentation, growthLevels, growthRulesVersion, growthTimezone, lockGrowth, readGrowth } from '../services/growth.js';

export const growthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/growth/config', { preHandler: app.authenticateOptional }, async (_request, reply) => {
    reply.header('cache-control', 'public, max-age=3600');
    return { rulesVersion: growthRulesVersion, timezone: growthTimezone, levels: growthLevels };
  });
  app.get('/users/me/growth-level', { preHandler: app.authenticate }, async (request) => transaction(async (client) => {
    await lockGrowth(client, request.user.sub);
    return readGrowth(client, request.user.sub);
  }));
  app.get('/users/me/badges', { preHandler: app.authenticate }, async (request) => transaction(async (client) => {
    await lockGrowth(client, request.user.sub);
    const growth = await readGrowth(client, request.user.sub);
    const records = (await client.query<{ badge_key: string; status: string; earned_at: Date }>(
      'SELECT badge_key,status,earned_at FROM user_badges WHERE user_id=$1 AND rules_version=$2', [request.user.sub, growthRulesVersion]
    )).rows;
    return { growth, badges: growthLevels.slice(1).map((level) => {
      const record = records.find((item) => item.badge_key === level.badgeKey);
      return { ...level, status: record?.status ?? 'locked', earnedAt: record?.earned_at ?? null };
    }) };
  }));
  app.post('/users/me/growth-presentations/consume', { preHandler: app.authenticate }, async (request) => {
    z.object({}).strict().parse(request.body ?? {});
    return transaction((client) => consumeGrowthPresentation(client, request.user.sub));
  });
};
