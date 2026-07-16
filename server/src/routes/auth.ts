import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { query } from '../db.js';
import { config } from '../config.js';

const bodySchema = z.object({ code: z.string().min(1) });

export const authRoutes: FastifyPluginAsync = async (app) => {
  app.post('/wechat', async (request, reply) => {
    const { code } = bodySchema.parse(request.body);
    let openid: string;
    if (config.NODE_ENV !== 'production' && code.startsWith('dev:')) {
      openid = code;
    } else {
      if (!config.WECHAT_APP_ID || !config.WECHAT_APP_SECRET) throw app.httpErrors.serviceUnavailable('微信登录尚未配置');
      const url = new URL('https://api.weixin.qq.com/sns/jscode2session');
      url.searchParams.set('appid', config.WECHAT_APP_ID);
      url.searchParams.set('secret', config.WECHAT_APP_SECRET);
      url.searchParams.set('js_code', code);
      url.searchParams.set('grant_type', 'authorization_code');
      const response = await fetch(url);
      const data = await response.json() as { openid?: string; errcode?: number; errmsg?: string };
      if (!response.ok || !data.openid) throw app.httpErrors.unauthorized(data.errmsg ?? '微信登录失败');
      openid = data.openid;
    }
    const result = await query<{ id: string; nickname: string; avatar_url: string | null; role: 'user' | 'gym_admin' | 'admin' }>(
      `INSERT INTO users(openid) VALUES($1) ON CONFLICT(openid) DO UPDATE SET updated_at=now()
       RETURNING id,nickname,avatar_url,role`, [openid]
    );
    const user = result.rows[0]!;
    const token = await reply.jwtSign({ sub: user.id, role: user.role }, { sign: { expiresIn: '30d' } });
    return { token, user: { id: user.id, nickname: user.nickname, avatarUrl: user.avatar_url, role: user.role } };
  });
};
