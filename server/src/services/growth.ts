import { createHash } from 'node:crypto';
import type pg from 'pg';

export const growthRulesVersion = 'wanpan-growth-v1';
export const growthTimezone = 'Asia/Shanghai';
export const growthLevels = [
  [0, '新岩友', 0, 0], [1, '初次上墙', 1, 1], [2, '渐入佳境', 3, 8],
  [3, '岩馆常客', 7, 25], [4, '稳步向上', 15, 60], [5, '攀爬成习', 30, 120],
  [6, '心有岩点', 60, 250], [7, '百日攀友', 100, 500], [8, '千线旅人', 180, 1000],
  [9, '攀行不止', 300, 1800], [10, '热爱成章', 500, 3000]
].map(([level, name, days, routes]) => ({
  level: level as number, name: name as string, days: days as number, routes: routes as number,
  badgeKey: level === 0 ? null : `account-level-${String(level).padStart(2, '0')}`
}));

type Db = Pick<pg.PoolClient, 'query'>;
type GrowthRow = { climbing_days: number; unique_routes: number; current_level: number; revision: number; backfill_status: string };
export function levelFor(climbingDays: number, uniqueRoutes: number) {
  return [...growthLevels].reverse().find((level) => climbingDays >= level.days && uniqueRoutes >= level.routes)!;
}
export function growthSnapshot(row: GrowthRow) {
  const current = growthLevels[row.current_level]!;
  const nextLevel = growthLevels[row.current_level + 1] ?? null;
  return {
    rulesVersion: growthRulesVersion, revision: row.revision, currentLevel: row.current_level,
    levelName: current.name, climbingDays: row.climbing_days, uniqueRoutes: row.unique_routes,
    nextLevel, remainingDays: nextLevel ? Math.max(0, nextLevel.days - row.climbing_days) : 0,
    remainingRoutes: nextLevel ? Math.max(0, nextLevel.routes - row.unique_routes) : 0,
    backfillStatus: row.backfill_status
  };
}

// Hash normalized, validated payloads; object key order cannot change retry identity.
export function requestHash(value: unknown): string {
  function canonical(v: unknown): unknown {
    if (Array.isArray(v)) return v.map(canonical);
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v)
      .filter(([, item]) => item !== undefined).sort(([a], [b]) => a.localeCompare(b))
      .map(([key, item]) => [key, canonical(item)]));
    return v;
  }
  return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}
export function idempotencyConflict(): Error & { statusCode: number; code: string } {
  return Object.assign(new Error('同一请求编号已用于不同内容，请重新发起操作'), {
    statusCode: 409, code: 'IDEMPOTENCY_KEY_REUSED'
  });
}
export async function retryResponse(db: Db, userId: string, requestId: string | undefined, kind: string, hash: string) {
  if (!requestId) return null;
  const found = await db.query('SELECT request_kind,request_hash,response FROM growth_requests WHERE user_id=$1 AND client_request_id=$2', [userId, requestId]);
  if (!found.rowCount) return null;
  const row = found.rows[0]!;
  if (row.request_kind !== kind || row.request_hash !== hash) throw idempotencyConflict();
  return row.response as Record<string, unknown>;
}
export async function saveResponse(db: Db, userId: string, requestId: string | undefined, kind: string, hash: string, response: unknown) {
  if (requestId) await db.query(
    'INSERT INTO growth_requests(user_id,client_request_id,request_kind,request_hash,response) VALUES($1,$2,$3,$4,$5)',
    [userId, requestId, kind, hash, JSON.stringify(response)]
  );
}

// Call before touching business rows. Every write/consume/backfill uses this lock order.
export async function lockGrowth(db: Db, userId: string) {
  await db.query('INSERT INTO user_growth(user_id,rules_version) VALUES($1,$2) ON CONFLICT DO NOTHING', [userId, growthRulesVersion]);
  const result = await db.query<GrowthRow>('SELECT * FROM user_growth WHERE user_id=$1 FOR UPDATE', [userId]);
  if (result.rows[0]!.backfill_status !== 'complete') {
    await db.query(
      `INSERT INTO climbing_facts(user_id,source_send_id,source_route_id,route_identity,occurred_at,local_date,source_kind,source_key)
       SELECT s.user_id,s.id,s.route_id,s.route_id,s.sent_at,(s.sent_at AT TIME ZONE 'Asia/Shanghai')::date,'legacy_backfill','legacy:send:'||s.id
       FROM sends s JOIN routes r ON r.id=s.route_id
       WHERE s.user_id=$1 AND s.moderation_status='approved'
         AND NOT EXISTS(SELECT 1 FROM climbing_facts f WHERE f.user_id=s.user_id AND f.source_send_id=s.id)
       ON CONFLICT(user_id,source_key) DO NOTHING`, [userId]
    );
    await db.query("UPDATE user_growth SET backfill_status='complete' WHERE user_id=$1", [userId]);
    await recomputeGrowth(db, userId);
  }
}

export async function recordClimbingFact(db: Db, args: {
  userId: string; sendId: string; routeId: string; sourceKind: 'checkin' | 'submission_video';
  clientRequestId?: string; hash?: string; occurredAt?: Date | string;
}) {
  if (!args.clientRequestId) {
    // An old client cannot distinguish yesterday's retry from today's new ascent.
    const existing = await db.query('SELECT 1 FROM climbing_facts WHERE user_id=$1 AND source_send_id=$2 LIMIT 1', [args.userId, args.sendId]);
    if (existing.rowCount) return;
  }
  await db.query(
    `WITH event_time AS (SELECT coalesce($4::timestamptz,statement_timestamp()) occurred_at)
     INSERT INTO climbing_facts(user_id,source_send_id,source_route_id,route_identity,occurred_at,local_date,source_kind,source_key,client_request_id,request_hash)
     SELECT $1,$2,$3,$3,occurred_at,(occurred_at AT TIME ZONE 'Asia/Shanghai')::date,$5,$6,$7,$8 FROM event_time
     ON CONFLICT(user_id,source_key) DO NOTHING`,
    [args.userId, args.sendId, args.routeId, args.occurredAt ?? null, args.sourceKind,
      args.clientRequestId ? `request:${args.clientRequestId}` : `legacy:send:${args.sendId}`,
      args.clientRequestId ?? null, args.hash ?? null]
  );
}

export async function readGrowth(db: Db, userId: string) {
  const result = await db.query<GrowthRow>('SELECT * FROM user_growth WHERE user_id=$1', [userId]);
  return growthSnapshot(result.rows[0]!);
}

export async function recomputeGrowth(db: Db, userId: string) {
  const before = (await db.query<GrowthRow>('SELECT * FROM user_growth WHERE user_id=$1', [userId])).rows[0]!;
  const counts = (await db.query<{ days: number; routes: number }>(
    "SELECT count(DISTINCT local_date)::int days,count(DISTINCT route_identity)::int routes FROM climbing_facts WHERE user_id=$1 AND status='valid'", [userId]
  )).rows[0]!;
  const level = levelFor(counts.days, counts.routes).level;
  const revisionChanged = before.revision === 0 || before.climbing_days !== counts.days || before.unique_routes !== counts.routes || before.current_level !== level;
  if (!revisionChanged) return growthSnapshot(before);
  const next = (await db.query<GrowthRow>(
    `UPDATE user_growth SET climbing_days=$2,unique_routes=$3,current_level=$4,rules_version=$5,revision=revision+1,updated_at=now()
     WHERE user_id=$1 RETURNING *`, [userId, counts.days, counts.routes, level, growthRulesVersion]
  )).rows[0]!;
  const pending = (await db.query<{ badge_keys: string[]; from_level: number }>(
    "SELECT badge_keys,from_level FROM growth_presentations WHERE user_id=$1 AND status='pending'", [userId]
  )).rows;
  const pendingKeys = new Set(pending.flatMap((item) => item.badge_keys));
  const newlyEarned: string[] = [];
  for (const config of growthLevels.slice(1, level + 1)) {
    const award = await db.query(
      "INSERT INTO user_badges(user_id,badge_key,level,rules_version) VALUES($1,$2,$3,$4) ON CONFLICT(user_id,badge_key,rules_version) DO NOTHING RETURNING id",
      [userId, config.badgeKey, config.level, growthRulesVersion]
    );
    if (award.rowCount) newlyEarned.push(config.badgeKey!);
  }
  const restored = await db.query<{ id: string }>(
    "UPDATE user_badges SET status='earned',revoked_at=NULL,revocation_reason=NULL WHERE user_id=$1 AND rules_version=$2 AND level<=$3 AND status='revoked' RETURNING id",
    [userId, growthRulesVersion, level]
  );
  const revoked = await db.query<{ id: string }>(
    "UPDATE user_badges SET status='revoked',revoked_at=now(),revocation_reason='valid_records_changed' WHERE user_id=$1 AND rules_version=$2 AND level>$3 AND status='earned' RETURNING id",
    [userId, growthRulesVersion, level]
  );
  for (const [rows, action] of [[restored.rows, 'restored'], [revoked.rows, 'revoked']] as const) {
    for (const badge of rows) await db.query(
      'INSERT INTO growth_audit(user_id,badge_id,action,reason) VALUES($1,$2,$3,$4)',
      [userId, badge.id, action, 'valid_records_changed']
    );
  }
  await db.query(
    "UPDATE growth_presentations SET status=$2,invalidated_at=CASE WHEN $2='invalidated' THEN now() ELSE NULL END WHERE user_id=$1 AND status='pending'",
    [userId, level < before.current_level ? 'invalidated' : 'superseded']
  );
  const validKeys = growthLevels.slice(1, level + 1).map((item) => item.badgeKey!);
  const badgeKeys = validKeys.filter((key) => pendingKeys.has(key) || newlyEarned.includes(key));
  if (badgeKeys.length) {
    await db.query(
      `INSERT INTO growth_presentations(user_id,from_level,to_level,badge_keys,growth_revision)
       VALUES($1,$2,$3,$4,$5)`,
      [userId, Math.min(before.current_level, ...pending.map((item) => item.from_level), level), level, JSON.stringify(badgeKeys), next.revision]
    );
  }
  return growthSnapshot(next);
}

export async function invalidateSendFacts(db: Db, userId: string, sendId: string, reason: string, actorId?: string) {
  const facts = await db.query<{ id: string }>(
    "UPDATE climbing_facts SET status='invalidated',invalidated_at=now(),invalidation_reason=$3 WHERE user_id=$1 AND source_send_id=$2 AND status='valid' RETURNING id",
    [userId, sendId, reason]
  );
  for (const fact of facts.rows) await db.query(
    "INSERT INTO growth_audit(user_id,fact_id,actor_id,action,reason) VALUES($1,$2,$3,'fact_invalidated',$4)",
    [userId, fact.id, actorId ?? userId, reason]
  );
  return recomputeGrowth(db, userId);
}

export async function consumeGrowthPresentation(db: Db, userId: string) {
  await lockGrowth(db, userId);
  const growth = await recomputeGrowth(db, userId);
  const pending = (await db.query<{ id: string; from_level: number; to_level: number; badge_keys: string[]; growth_revision: number }>(
    "SELECT * FROM growth_presentations WHERE user_id=$1 AND status='pending' ORDER BY growth_revision DESC LIMIT 1", [userId]
  )).rows[0];
  if (!pending) return { shouldPresent: false, growth, presentation: null };
  const earned = (await db.query<{ badge_key: string }>(
    "SELECT badge_key FROM user_badges WHERE user_id=$1 AND rules_version=$2 AND status='earned' AND badge_key=ANY($3::text[])",
    [userId, growthRulesVersion, pending.badge_keys]
  )).rows.map((row) => row.badge_key);
  if (!earned.length || pending.growth_revision !== growth.revision || pending.to_level !== growth.currentLevel) {
    await db.query("UPDATE growth_presentations SET status='invalidated',invalidated_at=now() WHERE id=$1", [pending.id]);
    return { shouldPresent: false, growth, presentation: null };
  }
  await db.query("UPDATE growth_presentations SET status='consumed',consumed_at=now() WHERE id=$1", [pending.id]);
  return {
    shouldPresent: true, growth,
    presentation: { id: pending.id, fromLevel: pending.from_level, toLevel: growth.currentLevel,
      badgeKeys: pending.badge_keys.filter((key) => earned.includes(key)), newBadgeCount: earned.length,
      levelName: growth.levelName, growthRevision: growth.revision }
  };
}
