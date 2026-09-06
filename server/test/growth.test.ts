import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { growthLevels, growthRulesVersion, growthSnapshot, levelFor, requestHash } from '../src/services/growth.js';
import { sendBody } from '../src/schemas.js';

describe('account growth rules', () => {
  it('keeps the frozen account configuration consistent with the approved design', async () => {
    const approved = JSON.parse(await readFile(new URL('../../design/wanpan-levels/v1/levels.json', import.meta.url), 'utf8'));
    expect(growthRulesVersion).toBe(approved.version);
    expect(growthLevels.map(({ level, name, days, routes }) => ({ level, name, days, routes })))
      .toEqual(approved.levels.map(({ level, name, days, routes }: Record<string, unknown>) => ({ level, name, days, routes })));
    expect(growthLevels[0]!.badgeKey).toBeNull();
    expect(new Set(growthLevels.slice(1).map((level) => level.badgeKey)).size).toBe(10);
  });
  it.each(growthLevels.slice(1))('requires both counters for Lv.$level', (config) => {
    expect(levelFor(config.days, config.routes).level).toBe(config.level);
    expect(levelFor(config.days - 1, config.routes).level).toBeLessThan(config.level);
    expect(levelFor(config.days, config.routes - 1).level).toBeLessThan(config.level);
  });
  it('keeps progress counters independent and caps the maximum level', () => {
    expect(growthSnapshot({ climbing_days: 10, unique_routes: 1, current_level: 1, revision: 4, backfill_status: 'complete' }))
      .toMatchObject({ remainingDays: 0, remainingRoutes: 7, nextLevel: { level: 2 }, revision: 4 });
    expect(growthSnapshot({ climbing_days: 1000, unique_routes: 9999, current_level: 10, revision: 11, backfill_status: 'complete' }))
      .toMatchObject({ nextLevel: null, remainingDays: 0, remainingRoutes: 0 });
  });
  it('canonicalizes object order but preserves values and arrays in request identity', () => {
    expect(requestHash({ a: 1, b: { c: 2, d: 3 } })).toBe(requestHash({ b: { d: 3, c: 2 }, a: 1 }));
    expect(requestHash({ a: undefined, b: 2 })).toBe(requestHash({ b: 2 }));
    expect(requestHash({ a: 1 })).not.toBe(requestHash({ a: 2 }));
    expect(requestHash([1, 2])).not.toBe(requestHash([2, 1]));
  });
  it('validates event intent and request keys without accepting client dates', () => {
    const routeId = '00000000-0000-4000-8000-000000000001';
    expect(sendBody.parse({ routeId, localDate: '1999-01-01' })).toEqual({ routeId, attempts: 1, visibility: 'public', operation: 'record' });
    expect(sendBody.safeParse({ routeId, operation: 'backdate' }).success).toBe(false);
    expect(sendBody.safeParse({ routeId, clientRequestId: 'not-uuid' }).success).toBe(false);
  });
});
