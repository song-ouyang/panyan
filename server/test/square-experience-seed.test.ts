import { describe, expect, it, vi } from "vitest";
import {
  assertSquareExperienceSeedAllowed,
  runSquareExperienceSeed,
  type SquareExperienceSeedQuery,
} from "../src/db/seed_square_experience_support.js";

describe("square experience seed", () => {
  it("requires one-command authorization in production", async () => {
    expect(() =>
      assertSquareExperienceSeedAllowed("development", false),
    ).not.toThrow();
    expect(() =>
      assertSquareExperienceSeedAllowed("production", true),
    ).not.toThrow();
    expect(() =>
      assertSquareExperienceSeedAllowed("production", false),
    ).toThrow("ALLOW_PRODUCTION_SQUARE_SEED=true");

    const runQuery = vi.fn() as unknown as SquareExperienceSeedQuery;
    await expect(
      runSquareExperienceSeed(runQuery, "production", false),
    ).rejects.toThrow("ALLOW_PRODUCTION_SQUARE_SEED=true");
    expect(runQuery).not.toHaveBeenCalled();
  });

  it("writes only namespaced, route-free, public approved experience data", async () => {
    const statements: Array<{ sql: string; values: unknown[] }> = [];
    const runQuery = vi.fn(async (sql: string, values: unknown[] = []) => {
      statements.push({ sql, values });
      if (
        sql.includes("INSERT INTO users") ||
        sql.includes("INSERT INTO sends") ||
        sql.includes("INSERT INTO comments")
      ) {
        return { rows: [{ id: values[0] }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    }) as unknown as SquareExperienceSeedQuery;

    await expect(
      runSquareExperienceSeed(runQuery, "production", true),
    ).resolves.toEqual({ users: 5, posts: 12, likes: 20, comments: 8 });

    const userWrites = statements.filter(({ sql }) =>
      sql.includes("INSERT INTO users"),
    );
    expect(userWrites).toHaveLength(5);
    for (const { sql, values } of userWrites) {
      expect(values[1]).toMatch(/^fixture:wanpan:square:/u);
      expect(values[2]).toMatch(/^完攀体验·/u);
      expect(sql).toContain("ON CONFLICT(openid) DO UPDATE");
      expect(sql).toContain("users.id=EXCLUDED.id");
      expect(sql).toContain("fixture:wanpan:square:%");
    }

    const postWrites = statements.filter(({ sql }) =>
      sql.includes("INSERT INTO sends"),
    );
    expect(postWrites).toHaveLength(12);
    for (const { sql, values } of postWrites) {
      expect(values[2]).toMatch(/^【完攀体验】/u);
      expect(sql).toContain("VALUES($1,$2,NULL,1,NULL");
      expect(sql).toContain("'public','approved'");
      expect(sql).toContain("ON CONFLICT(id) DO UPDATE");
      expect(sql).toContain("sends.route_id IS NULL");
      expect(sql).not.toContain("sent_at=EXCLUDED.sent_at");
      const conflictUpdate = sql.split("ON CONFLICT(id) DO UPDATE SET")[1];
      expect(conflictUpdate).not.toContain("visibility='public'");
      expect(conflictUpdate).not.toContain("moderation_status='approved'");
    }

    expect(
      statements.filter(({ sql }) => sql.includes("INSERT INTO post_likes")),
    ).toHaveLength(20);
    const commentWrites = statements.filter(({ sql }) =>
      sql.includes("INSERT INTO comments"),
    );
    expect(commentWrites).toHaveLength(8);
    for (const { sql } of commentWrites) {
      const conflictUpdate = sql.split("ON CONFLICT(id) DO UPDATE SET")[1];
      expect(conflictUpdate).not.toContain("moderation_status='approved'");
    }
    expect(
      statements.every(({ sql }) => sql.includes("ON CONFLICT")),
    ).toBe(true);

    const allSql = statements.map(({ sql }) => sql).join("\n");
    expect(allSql).not.toMatch(/DELETE\s+FROM/iu);
    expect(allSql).not.toContain("INSERT INTO gyms");
    expect(allSql).not.toContain("INSERT INTO gym_brands");
    expect(allSql).not.toContain("INSERT INTO routes");
    expect(allSql).not.toContain("INSERT INTO route_sets");
  });

  it("fails closed instead of updating a non-fixture identity collision", async () => {
    const runQuery = vi.fn(async () => ({ rows: [], rowCount: 0 })) as unknown as
      SquareExperienceSeedQuery;

    await expect(
      runSquareExperienceSeed(runQuery, "production", true),
    ).rejects.toThrow("fixture namespace conflict");
    expect(runQuery).toHaveBeenCalledTimes(1);
  });
});
