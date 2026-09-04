import type { QueryResultRow } from "pg";

export type PublicGym = {
  name: string;
  province: string;
  city: string;
  district: string;
  address: string;
  latitude?: number;
  longitude?: number;
  description: string;
  brandName?: string;
  canonicalVenueId?: string;
  source: {
    name: string;
    url: string;
    external_id?: string;
  };
};

export type PublicGymDirectory = { gyms: PublicGym[] };

export type SeedQuery = <T extends QueryResultRow = QueryResultRow>(
  text: string,
  values?: unknown[],
) => Promise<{ rows: T[]; rowCount: number | null }>;

const canonicalBrands: Array<[RegExp, string]> = [
  [/(?:banana\+|\u9999\u8549(?:\u6500\u5ca9|\u62b1\u77f3))/iu, "香蕉攀岩"],
  [/bloc\s*1/iu, "BLOC1 Climbing"],
  [/\u4e18\u5c71\u6500\u5ca9/u, "丘山攀岩"],
  [/tnt\s*\u6500\u5ca9/iu, "TNT攀岩"],
  [/dome\s*\u6500\u5ca9/iu, "DOME攀岩"],
];

/**
 * Derives a conservative brand label while keeping the original venue name as
 * the store label. Explicit seed data always wins; aliases only unify common
 * spelling variants, and the generic fallback strips an obvious store suffix.
 */
export function deriveBrandName(storeName: string, explicit?: string): string {
  const normalized = (explicit ?? storeName).replace(/\s+/gu, " ").trim();
  if (!normalized) return storeName.trim();
  if (explicit) return normalized;

  for (const [pattern, brand] of canonicalBrands) {
    if (pattern.test(normalized)) return brand;
  }

  const withoutParenthesizedStore = normalized.replace(
    /\s*[\uff08(][^\uff08\uff09()]+(?:\u5e97|\u6821\u533a|\u9986)[\uff09)]\s*$/u,
    "",
  );
  const middleDot = withoutParenthesizedStore.match(
    /^(.+?)[\u00b7\u30fb](.+)$/u,
  );
  if (
    middleDot?.[1] &&
    /(?:\u5e97|\u6821\u533a|\u9986)$/u.test(middleDot[2] ?? "")
  ) {
    return middleDot[1].trim();
  }
  return withoutParenthesizedStore || normalized;
}

function compactVenueIdentity(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase("zh-CN")
    .replace(/[^\p{L}\p{N}]/gu, "");
}

const bananaVenueAliases = new Map([
  ["深圳:深圳湾后海汇", "后海汇"],
]);

/**
 * Assigns one stable identity to reviewed cross-source aliases of the same
 * Banana venue. Other brands remain explicit-only so similarly named stores
 * are never merged by a broad fuzzy rule.
 */
export function deriveCanonicalVenueId(
  item: Pick<
    PublicGym,
    "name" | "city" | "brandName" | "canonicalVenueId"
  >,
  resolvedBrandName = deriveBrandName(item.name, item.brandName),
): string | undefined {
  const explicit = item.canonicalVenueId?.trim();
  if (explicit) return explicit;
  if (resolvedBrandName !== "香蕉攀岩") return undefined;

  let venue = compactVenueIdentity(item.name);
  for (const brandToken of ["banana", "香蕉攀岩", "香蕉抱石"]) {
    venue = venue.split(brandToken).join("");
  }
  venue = venue
    .replace(/(?:攀岩馆|抱石馆|攀岩|抱石|店|馆)$/u, "")
    .replace(/(?:购物中心|商都)$/u, "");

  const city = compactVenueIdentity(item.city).replace(/市$/u, "");
  venue = bananaVenueAliases.get(`${city}:${venue}`) ?? venue;
  if (venue.length < 2) return undefined;
  return `directory:banana:${city}:${venue}`;
}

function gymSourcePriority(sourceName: string | null | undefined): number {
  if (sourceName === "香蕉攀岩公开门店服务（climbing-go）") return 100;
  if (sourceName === "高德地图") return 80;
  if (sourceName === "攀岩么公开岩馆接口") return 60;
  return sourceName ? 40 : 0;
}

export function assertGymDirectoryImportAllowed(
  nodeEnv: string,
  allowProductionGymImport: boolean,
): void {
  if (nodeEnv === "production" && !allowProductionGymImport) {
    throw new Error(
      "Production gym import is disabled. Back up the database and set " +
        "ALLOW_PRODUCTION_GYM_IMPORT=true only for the explicit seed command.",
    );
  }
}

const legacyDemoGyms = [
  ["香蕉攀岩·南山店", "南山区示例路1号"],
  ["香蕉攀岩·宝安店", "宝安区示例路3号"],
  ["香蕉攀岩·福田店", "福田区示例路2号"],
] as const;

/**
 * Removes only the three source-less demo venues shipped by an early local
 * seed. The exact name + address + NULL provenance guard makes the
 * cleanup safe to rerun without touching imported or user-managed venues.
 */
export async function removeLegacyDemoGyms(
  runQuery: SeedQuery,
): Promise<number> {
  const removed = await runQuery<{ id: string }>(
    `DELETE FROM gyms AS g
     USING (VALUES
       ($1::text,$2::text),
       ($3::text,$4::text),
       ($5::text,$6::text)
     ) AS legacy(name,address)
     WHERE g.source_name IS NULL
       AND g.name=legacy.name
       AND g.address=legacy.address
     RETURNING g.id`,
    legacyDemoGyms.flat(),
  );
  return removed.rowCount ?? removed.rows.length;
}

async function mergeCanonicalGymAlias(
  runQuery: SeedQuery,
  canonicalGymId: string,
  aliasGymId: string
): Promise<void> {
  await runQuery(
    `UPDATE gyms AS canonical SET
       verified=canonical.verified OR alias.verified,
       cover_url=coalesce(canonical.cover_url,alias.cover_url),
       description=coalesce(canonical.description,alias.description),
       latitude=coalesce(canonical.latitude,alias.latitude),
       longitude=coalesce(canonical.longitude,alias.longitude),
       created_at=least(canonical.created_at,alias.created_at)
     FROM gyms AS alias
     WHERE canonical.id=$1 AND alias.id=$2`,
    [canonicalGymId, aliasGymId],
  );
  await runQuery(
    `INSERT INTO gym_admins(user_id,gym_id,created_at)
     SELECT user_id,$1,created_at FROM gym_admins WHERE gym_id=$2
     ON CONFLICT(user_id,gym_id) DO NOTHING`,
    [canonicalGymId, aliasGymId]
  );
  await runQuery('DELETE FROM gym_admins WHERE gym_id=$1', [aliasGymId]);
  for (const table of [
    'gym_visit_cards',
    'route_sets',
    'routes',
    'meetups',
    'route_submissions'
  ]) {
    await runQuery(`UPDATE ${table} SET gym_id=$1 WHERE gym_id=$2`, [
      canonicalGymId,
      aliasGymId
    ]);
  }
  await runQuery('DELETE FROM gyms WHERE id=$1', [aliasGymId]);
}

export async function seedGymDirectory(
  runQuery: SeedQuery,
  directory: PublicGymDirectory,
): Promise<{ inserted: number; reused: number }> {
  let inserted = 0;
  let reused = 0;

  for (const item of directory.gyms) {
    const brandName = deriveBrandName(item.name, item.brandName);
    const brand = await runQuery<{ id: string }>(
      `INSERT INTO gym_brands(name)
       VALUES($1)
       ON CONFLICT(name) DO UPDATE SET name=EXCLUDED.name
       RETURNING id`,
      [brandName],
    );
    const brandId = brand.rows[0]?.id;
    if (!brandId) throw new Error(`Unable to seed gym brand: ${brandName}`);

    const sourceExternalId = item.source.external_id?.trim() || null;
    const canonicalVenueId = deriveCanonicalVenueId(item, brandName) ?? null;
    const existing = await runQuery<{
      id: string;
      source_name: string | null;
      source_match: boolean;
    }>(
      `SELECT id,source_name,
         ($2::text IS NOT NULL AND source_name=$3 AND source_external_id=$2) source_match
       FROM gyms
       WHERE (
         $1::text IS NOT NULL
         AND canonical_venue_id=$1
       ) OR (
         $2::text IS NOT NULL
         AND source_name=$3
         AND source_external_id=$2
       ) OR (
         lower(btrim(name))=lower(btrim($4))
         AND city=$5
         AND lower(btrim(address))=lower(btrim($6))
       )
       ORDER BY
         (canonical_venue_id=$1) DESC NULLS LAST,
         (source_name=$3 AND source_external_id=$2) DESC NULLS LAST`,
      [
        canonicalVenueId,
        sourceExternalId,
        item.source.name,
        item.name,
        item.city,
        item.address,
      ],
    );

    const existingGym = existing.rows[0];
    const existingId = existingGym?.id;
    if (existingId) {
      if (canonicalVenueId) {
        for (const alias of existing.rows.slice(1)) {
          if (alias.id !== existingId) {
            await mergeCanonicalGymAlias(runQuery, existingId, alias.id);
          }
        }
      }
      const replaceVenueDetails =
        canonicalVenueId === null ||
        existingGym.source_match ||
        gymSourcePriority(item.source.name) >
          gymSourcePriority(existingGym.source_name);
      await runQuery(
        `UPDATE gyms SET
           name=CASE WHEN $15 THEN $2 ELSE name END,
           province=CASE WHEN $15 THEN $3 ELSE province END,
           city=CASE WHEN $15 THEN $4 ELSE city END,
           district=CASE WHEN $15 THEN $5 ELSE district END,
           address=CASE WHEN $15 THEN $6 ELSE address END,
           latitude=CASE WHEN $15 THEN coalesce($7,latitude) ELSE latitude END,
           longitude=CASE WHEN $15 THEN coalesce($8,longitude) ELSE longitude END,
           description=CASE WHEN $15 THEN $9 ELSE description END,
           brand_id=$10,
           canonical_venue_id=coalesce($11,canonical_venue_id),
           source_name=CASE WHEN $15 THEN coalesce($12,source_name) ELSE source_name END,
           source_url=CASE WHEN $15 THEN coalesce($13,source_url) ELSE source_url END,
           source_external_id=CASE WHEN $15 THEN coalesce($14,source_external_id) ELSE source_external_id END
         WHERE id=$1`,
        [
          existingId,
          item.name,
          item.province,
          item.city,
          item.district,
          item.address,
          item.latitude ?? null,
          item.longitude ?? null,
          item.description,
          brandId,
          canonicalVenueId,
          item.source.name,
          item.source.url,
          sourceExternalId,
          replaceVenueDetails,
        ],
      );
      reused += 1;
      continue;
    }

    await runQuery(
      `INSERT INTO gyms(
         name,province,city,district,address,latitude,longitude,description,
         verified,brand_id,canonical_venue_id,source_name,source_url,source_external_id
       ) VALUES($1,$2,$3,$4,$5,$6,$7,$8,false,$9,$10,$11,$12,$13)`,
      [
        item.name,
        item.province,
        item.city,
        item.district,
        item.address,
        item.latitude ?? null,
        item.longitude ?? null,
        item.description,
        brandId,
        canonicalVenueId,
        item.source.name,
        item.source.url,
        sourceExternalId,
      ],
    );
    inserted += 1;
  }

  return { inserted, reused };
}

const developmentProfiles = [
  {
    id: "00000000-0000-4000-8000-00000000d101",
    openid: "dev:seed:square:ayan",
    nickname: "开发示例·阿岩",
    bio: "本地开发环境的明确模拟账号",
  },
  {
    id: "00000000-0000-4000-8000-00000000d102",
    openid: "dev:seed:square:xiaolin",
    nickname: "开发示例·小林",
    bio: "本地开发环境的明确模拟账号",
  },
  {
    id: "00000000-0000-4000-8000-00000000d103",
    openid: "dev:seed:square:maomao",
    nickname: "开发示例·猫猫",
    bio: "本地开发环境的明确模拟账号",
  },
  {
    id: "00000000-0000-4000-8000-00000000d104",
    openid: "dev:seed:square:chengzi",
    nickname: "开发示例·橙子",
    bio: "本地开发环境的明确模拟账号",
  },
  {
    id: "00000000-0000-4000-8000-00000000d105",
    openid: "dev:seed:square:xiaoyu",
    nickname: "开发示例·小屿",
    bio: "本地开发环境的明确模拟账号",
  },
] as const;

const developmentBrand = {
  id: "00000000-0000-4000-8000-00000000d301",
  name: "开发示例·完攀岩馆",
} as const;

const developmentGym = {
  id: "00000000-0000-4000-8000-00000000d302",
  name: "开发示例·完攀岩馆南山店",
} as const;

const developmentRouteSet = {
  id: "00000000-0000-4000-8000-00000000d303",
  name: "开发示例·九月换线",
} as const;

const developmentRoutes = [
  {
    id: "00000000-0000-4000-8000-00000000d310",
    name: "薄荷热身线",
    grade: "V0",
    color: "绿色",
    wallZone: "A 区",
  },
  {
    id: "00000000-0000-4000-8000-00000000d311",
    name: "柠檬平衡线",
    grade: "V1",
    color: "黄色",
    wallZone: "B 区",
  },
  {
    id: "00000000-0000-4000-8000-00000000d312",
    name: "橙子小跳线",
    grade: "V2",
    color: "橙色",
    wallZone: "C 区",
  },
  {
    id: "00000000-0000-4000-8000-00000000d313",
    name: "葡萄联动线",
    grade: "V3",
    color: "紫色",
    wallZone: "D 区",
  },
  {
    id: "00000000-0000-4000-8000-00000000d314",
    name: "海盐核心线",
    grade: "V4",
    color: "蓝色",
    wallZone: "E 区",
  },
  {
    id: "00000000-0000-4000-8000-00000000d315",
    name: "黑猫挑战线",
    grade: "V5",
    color: "黑色",
    wallZone: "F 区",
  },
] as const;

const developmentPosts = [
  {
    id: "00000000-0000-4000-8000-00000000d201",
    profileIndex: 0,
    routeIndex: 2,
    attempts: 2,
    visibility: "public",
    caption: "【开发示例】V2 橙子小跳线，今天终于把落脚踩稳了！",
    hoursAgo: 1,
  },
  {
    id: "00000000-0000-4000-8000-00000000d202",
    profileIndex: 1,
    routeIndex: 3,
    attempts: 4,
    visibility: "public",
    caption: "【开发示例】V3 葡萄线的重心切换很有趣，欢迎一起交流动作。",
    hoursAgo: 3,
  },
  {
    id: "00000000-0000-4000-8000-00000000d203",
    profileIndex: 2,
    routeIndex: 0,
    attempts: 1,
    visibility: "public",
    caption: "【开发示例】V0 热身一次完攀，今天也要轻松开爬。",
    hoursAgo: 6,
  },
  {
    id: "00000000-0000-4000-8000-00000000d204",
    profileIndex: 3,
    routeIndex: 4,
    attempts: 7,
    visibility: "public",
    caption: "【开发示例】V4 核心线卡了七次，最后一把没有松手！",
    hoursAgo: 10,
  },
  {
    id: "00000000-0000-4000-8000-00000000d205",
    profileIndex: 4,
    routeIndex: 1,
    attempts: 2,
    visibility: "public",
    caption: "【开发示例】V1 平衡线比想象中细腻，慢一点反而更稳。",
    hoursAgo: 18,
  },
  {
    id: "00000000-0000-4000-8000-00000000d206",
    profileIndex: 0,
    routeIndex: 5,
    attempts: 12,
    visibility: "public",
    caption: "【开发示例】第一次摸到 V5 顶点，十二次尝试都值得。",
    hoursAgo: 26,
  },
  {
    id: "00000000-0000-4000-8000-00000000d207",
    profileIndex: 1,
    routeIndex: 0,
    attempts: 1,
    visibility: "public",
    caption: "【开发示例】下班十分钟速攀，V0 也能收获好心情。",
    hoursAgo: 35,
  },
  {
    id: "00000000-0000-4000-8000-00000000d208",
    profileIndex: 2,
    routeIndex: 4,
    attempts: 9,
    visibility: "public",
    caption: "【开发示例】V4 的最后一个动态点，换了 beta 终于成功。",
    hoursAgo: 49,
  },
  {
    id: "00000000-0000-4000-8000-00000000d209",
    profileIndex: 3,
    routeIndex: 1,
    attempts: 3,
    visibility: "friends",
    caption: "【开发示例】仅岩友可见：周末一起刷 V1 吧。",
    hoursAgo: 58,
  },
  {
    id: "00000000-0000-4000-8000-00000000d210",
    profileIndex: 4,
    routeIndex: 3,
    attempts: 5,
    visibility: "private",
    caption: "【开发示例】仅自己可见：记一下 V3 的个人 beta。",
    hoursAgo: 72,
  },
] as const;

const developmentLikes = [
  [0, 1],
  [0, 2],
  [0, 3],
  [1, 0],
  [1, 2],
  [3, 0],
  [3, 1],
  [3, 4],
  [5, 1],
  [5, 2],
  [5, 3],
  [7, 0],
  [7, 3],
  [7, 4],
] as const;

const developmentComments = [
  {
    id: "00000000-0000-4000-8000-00000000d401",
    postIndex: 0,
    profileIndex: 1,
    content: "【开发示例】这个落脚提示很有用！",
  },
  {
    id: "00000000-0000-4000-8000-00000000d402",
    postIndex: 1,
    profileIndex: 3,
    content: "【开发示例】下次一起试试这个 beta。",
  },
  {
    id: "00000000-0000-4000-8000-00000000d403",
    postIndex: 3,
    profileIndex: 4,
    content: "【开发示例】坚持到最后太棒啦。",
  },
  {
    id: "00000000-0000-4000-8000-00000000d404",
    postIndex: 5,
    profileIndex: 2,
    content: "【开发示例】恭喜解锁 V5！",
  },
  {
    id: "00000000-0000-4000-8000-00000000d405",
    postIndex: 7,
    profileIndex: 0,
    content: "【开发示例】换 beta 的思路记下了。",
  },
] as const;

export function shouldSeedDevelopmentSquare(nodeEnv: string): boolean {
  return nodeEnv === "development";
}

export async function seedDevelopmentSquare(
  runQuery: SeedQuery,
  nodeEnv: string,
): Promise<number> {
  if (!shouldSeedDevelopmentSquare(nodeEnv)) {
    throw new Error(
      "Development square seed is disabled outside NODE_ENV=development",
    );
  }

  const brand = await runQuery<{ id: string }>(
    `INSERT INTO gym_brands(id,name)
     VALUES($1,$2)
     ON CONFLICT(name) DO UPDATE SET name=EXCLUDED.name
     RETURNING id`,
    [developmentBrand.id, developmentBrand.name],
  );
  const brandId = brand.rows[0]?.id;
  if (!brandId) throw new Error("Unable to seed development gym brand");

  await runQuery(
    `INSERT INTO gyms(
       id,name,province,city,district,address,description,verified,brand_id,
       source_name,source_external_id
     ) VALUES($1,$2,'广东省','深圳','南山区','开发示例地址（非真实岩馆）',
       '仅供本地开发和界面联调使用',false,$3,'development-seed','wanpan-dev-gym')
     ON CONFLICT(id) DO UPDATE SET
       name=EXCLUDED.name,
       description=EXCLUDED.description,
       verified=false,
       brand_id=EXCLUDED.brand_id,
       source_name=EXCLUDED.source_name,
       source_external_id=EXCLUDED.source_external_id`,
    [developmentGym.id, developmentGym.name, brandId],
  );
  await runQuery(
    `INSERT INTO route_sets(id,gym_id,name,starts_on,active)
     VALUES($1,$2,$3,current_date,true)
     ON CONFLICT(id) DO UPDATE SET
       gym_id=EXCLUDED.gym_id,
       name=EXCLUDED.name,
       active=true`,
    [developmentRouteSet.id, developmentGym.id, developmentRouteSet.name],
  );
  for (const route of developmentRoutes) {
    await runQuery(
      `INSERT INTO routes(
         id,gym_id,route_set_id,name,grade,color,wall_zone,published
       ) VALUES($1,$2,$3,$4,$5,$6,$7,true)
       ON CONFLICT(id) DO UPDATE SET
         gym_id=EXCLUDED.gym_id,
         route_set_id=EXCLUDED.route_set_id,
         name=EXCLUDED.name,
         grade=EXCLUDED.grade,
         color=EXCLUDED.color,
         wall_zone=EXCLUDED.wall_zone,
         published=true`,
      [
        route.id,
        developmentGym.id,
        developmentRouteSet.id,
        route.name,
        route.grade,
        route.color,
        route.wallZone,
      ],
    );
  }

  const userIds: string[] = [];
  for (const profile of developmentProfiles) {
    const user = await runQuery<{ id: string }>(
      `INSERT INTO users(id,openid,nickname,bio,profile_completed)
       VALUES($1,$2,$3,$4,true)
       ON CONFLICT(openid) DO UPDATE SET
         nickname=EXCLUDED.nickname,
         bio=EXCLUDED.bio,
         profile_completed=true,
         updated_at=now()
       RETURNING id`,
      [profile.id, profile.openid, profile.nickname, profile.bio],
    );
    const userId = user.rows[0]?.id;
    if (!userId)
      throw new Error(`Unable to seed development user: ${profile.openid}`);
    userIds.push(userId);
  }

  const postIds: string[] = [];
  for (const post of developmentPosts) {
    const userId = userIds[post.profileIndex];
    if (!userId)
      throw new Error(`Missing development profile for post: ${post.id}`);
    const route = developmentRoutes[post.routeIndex];
    if (!route)
      throw new Error(`Missing development route for post: ${post.id}`);
    const result = await runQuery<{ id: string }>(
      `INSERT INTO sends(
         id,user_id,route_id,attempts,caption,image_urls,visibility,
         moderation_status,sent_at
       ) VALUES($1,$2,$3,$4,$5,'{}'::text[],$6,'approved',
         date_trunc('hour',now())-($7::int * interval '1 hour'))
       ON CONFLICT(user_id,route_id) DO UPDATE SET
         attempts=EXCLUDED.attempts,
         caption=EXCLUDED.caption,
         image_urls='{}'::text[],
         visibility=EXCLUDED.visibility,
         moderation_status='approved',
         sent_at=EXCLUDED.sent_at
       RETURNING id`,
      [
        post.id,
        userId,
        route.id,
        post.attempts,
        post.caption,
        post.visibility,
        post.hoursAgo,
      ],
    );
    const postId = result.rows[0]?.id;
    if (!postId) throw new Error(`Unable to seed development post: ${post.id}`);
    postIds.push(postId);
  }

  for (const [postIndex, profileIndex] of developmentLikes) {
    const postId = postIds[postIndex];
    const userId = userIds[profileIndex];
    if (!postId || !userId) throw new Error("Invalid development like fixture");
    await runQuery(
      `INSERT INTO post_likes(send_id,user_id)
       VALUES($1,$2)
       ON CONFLICT(send_id,user_id) DO NOTHING`,
      [postId, userId],
    );
  }

  for (const comment of developmentComments) {
    const postId = postIds[comment.postIndex];
    const userId = userIds[comment.profileIndex];
    if (!postId || !userId)
      throw new Error(`Invalid development comment: ${comment.id}`);
    await runQuery(
      `INSERT INTO comments(id,send_id,user_id,content,moderation_status)
       VALUES($1,$2,$3,$4,'approved')
       ON CONFLICT(id) DO UPDATE SET
         send_id=EXCLUDED.send_id,
         user_id=EXCLUDED.user_id,
         content=EXCLUDED.content,
         moderation_status='approved'`,
      [comment.id, postId, userId, comment.content],
    );
  }

  return developmentPosts.length;
}
