import { createHash, timingSafeEqual } from 'node:crypto';
import type { FastifyPluginAsync, FastifyReply } from 'fastify';
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';
import { z } from 'zod';
import { query } from '../db.js';
import { config } from '../config.js';

const codeBody = z.object({ code: z.string().trim().min(1).max(512) });
const appleBody = z.object({
  identityToken: z.string().min(100).max(16_384),
  rawNonce: z.string().min(16).max(512),
  givenName: z.string().trim().max(80).nullable().optional(),
  familyName: z.string().trim().max(80).nullable().optional()
});

type AuthUser = {
  id: string;
  nickname: string;
  avatar_url: string | null;
  role: 'user' | 'gym_admin' | 'admin';
  profile_completed: boolean;
};

const appleJwks = createRemoteJWKSet(
  new URL('https://appleid.apple.com/auth/keys'),
  { timeoutDuration: 10_000 }
);
const authRateLimit = { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } };

function safeNickname(value: unknown): string {
  if (typeof value !== 'string') return '岩友';
  const trimmed = value.trim();
  return trimmed ? Array.from(trimmed).slice(0, 32).join('') : '岩友';
}

function safeAvatarUrl(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value.trim().replace(/^http:\/\//, 'https://'));
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

async function upsertProviderUser(input: {
  identity: string;
  nickname?: string;
  avatarUrl?: string | null;
  profileCompleted: boolean;
  legacyIdentities?: string[];
}): Promise<AuthUser> {
  const result = await query<AuthUser>(
    `WITH existing AS (
       SELECT id FROM users
       WHERE openid=$1 OR openid=ANY($5::text[])
       ORDER BY (openid=$1) DESC
       LIMIT 1
     ), migrated AS (
       UPDATE users SET
         openid=$1,
         nickname=CASE WHEN profile_completed=false AND $2<>'岩友' THEN $2 ELSE nickname END,
         avatar_url=coalesce(avatar_url,$3),
         profile_completed=profile_completed OR $4,
         updated_at=now()
       WHERE id=(SELECT id FROM existing)
       RETURNING id,nickname,avatar_url,role,profile_completed
     ), inserted AS (
       INSERT INTO users(openid,nickname,avatar_url,profile_completed)
       SELECT $1,$2,$3,$4 WHERE NOT EXISTS (SELECT 1 FROM migrated)
       ON CONFLICT(openid) DO UPDATE SET
         nickname=CASE
           WHEN users.profile_completed=false AND EXCLUDED.nickname<>'岩友' THEN EXCLUDED.nickname
           ELSE users.nickname
         END,
         avatar_url=coalesce(users.avatar_url,EXCLUDED.avatar_url),
         profile_completed=users.profile_completed OR EXCLUDED.profile_completed,
         updated_at=now()
       RETURNING id,nickname,avatar_url,role,profile_completed
     )
     SELECT * FROM migrated UNION ALL SELECT * FROM inserted LIMIT 1`,
    [
      input.identity,
      safeNickname(input.nickname),
      safeAvatarUrl(input.avatarUrl),
      input.profileCompleted,
      input.legacyIdentities ?? []
    ]
  );
  return result.rows[0]!;
}

async function sessionResponse(reply: FastifyReply, user: AuthUser) {
  const token = await reply.jwtSign(
    { sub: user.id, role: user.role },
    { sign: { expiresIn: '30d' } }
  );
  return {
    token,
    user: {
      id: user.id,
      nickname: user.nickname,
      avatarUrl: user.avatar_url,
      role: user.role,
      profileCompleted: user.profile_completed
    },
    needsProfile: !user.profile_completed
  };
}

function verifyAppleNonce(payload: JWTPayload, rawNonce: string): void {
  const actual = typeof payload.nonce === 'string' ? payload.nonce : '';
  const expected = createHash('sha256').update(rawNonce, 'utf8').digest('hex');
  const actualBytes = Buffer.from(actual, 'utf8');
  const expectedBytes = Buffer.from(expected, 'utf8');
  if (actualBytes.length !== expectedBytes.length || !timingSafeEqual(actualBytes, expectedBytes)) {
    throw new Error('APPLE_NONCE_MISMATCH');
  }
}

async function verifiedAppleSubject(identityToken: string, rawNonce: string): Promise<string> {
  const { payload } = await jwtVerify(identityToken, appleJwks, {
    algorithms: ['RS256'],
    issuer: 'https://appleid.apple.com',
    audience: config.APPLE_CLIENT_ID,
    clockTolerance: 5
  });
  verifyAppleNonce(payload, rawNonce);

  const now = Math.floor(Date.now() / 1000);
  if (!payload.sub || typeof payload.iat !== 'number' || payload.iat > now + 60 ||
      typeof payload.exp !== 'number' || payload.exp <= now) {
    throw new Error('APPLE_CLAIMS_INVALID');
  }
  return payload.sub;
}

export const authRoutes: FastifyPluginAsync = async (app) => {
  // Mini Program login remains separate: its code is only valid for jscode2session.
  app.post('/wechat', authRateLimit, async (request, reply) => {
    const { code } = codeBody.parse(request.body);
    let openid: string;
    if (config.NODE_ENV !== 'production' && code.startsWith('dev:')) {
      openid = code;
    } else {
      if (!config.WECHAT_APP_ID || !config.WECHAT_APP_SECRET) {
        throw app.httpErrors.serviceUnavailable('微信小程序登录尚未配置');
      }
      const url = new URL('https://api.weixin.qq.com/sns/jscode2session');
      url.searchParams.set('appid', config.WECHAT_APP_ID);
      url.searchParams.set('secret', config.WECHAT_APP_SECRET);
      url.searchParams.set('js_code', code);
      url.searchParams.set('grant_type', 'authorization_code');
      const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
      const data = await response.json() as { openid?: string; unionid?: string; errmsg?: string };
      if (!response.ok || !data.openid) {
        throw app.httpErrors.unauthorized(data.errmsg ?? '微信小程序登录失败');
      }
      openid = data.unionid ? `wechat:${data.unionid}` : `wechat-mini:${data.openid}`;
      const user = await upsertProviderUser({
        identity: openid,
        legacyIdentities: [data.openid, `wechat-mini:${data.openid}`],
        profileCompleted: false
      });
      return sessionResponse(reply, user);
    }
    const user = await upsertProviderUser({ identity: openid, profileCompleted: false });
    return sessionResponse(reply, user);
  });

  // Native WeChat OpenSDK code. Never send AppSecret to the mobile app.
  app.post('/wechat-mobile', authRateLimit, async (request, reply) => {
    const { code } = codeBody.parse(request.body);
    if (!config.WECHAT_MOBILE_APP_ID || !config.WECHAT_MOBILE_APP_SECRET) {
      throw app.httpErrors.serviceUnavailable('微信移动应用登录尚未配置');
    }

    const tokenUrl = new URL('https://api.weixin.qq.com/sns/oauth2/access_token');
    tokenUrl.searchParams.set('appid', config.WECHAT_MOBILE_APP_ID);
    tokenUrl.searchParams.set('secret', config.WECHAT_MOBILE_APP_SECRET);
    tokenUrl.searchParams.set('code', code);
    tokenUrl.searchParams.set('grant_type', 'authorization_code');
    const tokenResponse = await fetch(tokenUrl, { signal: AbortSignal.timeout(10_000) });
    const tokenData = await tokenResponse.json() as {
      access_token?: string;
      openid?: string;
      unionid?: string;
      errmsg?: string;
    };
    if (!tokenResponse.ok || !tokenData.access_token || !tokenData.openid) {
      throw app.httpErrors.unauthorized(tokenData.errmsg ?? '微信授权已失效，请重试');
    }

    const userInfoUrl = new URL('https://api.weixin.qq.com/sns/userinfo');
    userInfoUrl.searchParams.set('access_token', tokenData.access_token);
    userInfoUrl.searchParams.set('openid', tokenData.openid);
    userInfoUrl.searchParams.set('lang', 'zh_CN');
    const userInfoResponse = await fetch(userInfoUrl, { signal: AbortSignal.timeout(10_000) });
    const userInfo = await userInfoResponse.json() as {
      openid?: string;
      unionid?: string;
      nickname?: string;
      headimgurl?: string;
      errmsg?: string;
    };
    if (!userInfoResponse.ok || userInfo.openid !== tokenData.openid) {
      throw app.httpErrors.unauthorized(userInfo.errmsg ?? '微信用户信息校验失败');
    }

    const unionid = userInfo.unionid ?? tokenData.unionid;
    const identity = unionid
      ? `wechat:${unionid}`
      : `wechat-mobile:${tokenData.openid}`;
    const nickname = safeNickname(userInfo.nickname);
    const avatarUrl = safeAvatarUrl(userInfo.headimgurl);
    const user = await upsertProviderUser({
      identity,
      legacyIdentities: unionid
        ? [`wechat-mobile:${tokenData.openid}`, `wechat-mobile:${unionid}`]
        : [],
      nickname,
      avatarUrl,
      profileCompleted: nickname !== '岩友' && avatarUrl !== null
    });
    return sessionResponse(reply, user);
  });

  app.post('/apple', authRateLimit, async (request, reply) => {
    const body = appleBody.parse(request.body);
    if (!config.APPLE_CLIENT_ID) {
      throw app.httpErrors.serviceUnavailable('Apple 登录尚未配置');
    }

    let subject: string;
    try {
      subject = await verifiedAppleSubject(body.identityToken, body.rawNonce);
    } catch (error) {
      request.log.warn({ error }, 'Apple identity token verification failed');
      throw app.httpErrors.unauthorized('Apple 登录凭证无效，请重试');
    }

    // Apple only supplies the name on the first authorization. It is display
    // data only; the verified JWT `sub` above is the sole account identity.
    const suggestedName = safeNickname(
      [body.givenName, body.familyName].filter((part) => part?.trim()).join(' ')
    );
    const user = await upsertProviderUser({
      identity: `apple:${subject}`,
      nickname: suggestedName,
      profileCompleted: false
    });
    return sessionResponse(reply, user);
  });
};
