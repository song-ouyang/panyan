import { readFile } from "node:fs/promises";
import { describe, expect, it, vi } from "vitest";
import {
  assertGymDirectoryImportAllowed,
  deriveBrandName,
  deriveCanonicalVenueId,
  removeLegacyDemoGyms,
  seedDevelopmentSquare,
  seedGymDirectory,
  shouldSeedDevelopmentSquare,
  type PublicGymDirectory,
  type SeedQuery,
} from "../src/db/seed_support.js";

const directory: PublicGymDirectory = {
  gyms: [
    {
      name: "香蕉攀岩 南山店",
      province: "广东省",
      city: "深圳",
      district: "南山区",
      address: "南山区示例路1号",
      description: "公开来源初核",
      source: {
        name: "测试公开目录",
        url: "https://example.com/gyms/nanshan",
        external_id: "public-gym-1",
      },
    },
  ],
};

describe("gym seed helpers", () => {
  it("removes only the three exact source-less legacy demo venues", async () => {
    const runQuery = vi.fn(async () => ({
      rows: [{ id: "legacy-gym" }],
      rowCount: 1,
    })) as unknown as SeedQuery;

    await expect(removeLegacyDemoGyms(runQuery)).resolves.toBe(1);

    const [sql, values] = vi.mocked(runQuery).mock.calls[0]!;
    expect(sql).toContain("g.source_name IS NULL");
    expect(sql).toContain("g.name=legacy.name");
    expect(sql).toContain("g.address=legacy.address");
    expect(sql).not.toContain("ILIKE");
    expect(sql).not.toContain("position(");
    expect(values).toEqual([
      "香蕉攀岩·南山店",
      "南山区示例路1号",
      "香蕉攀岩·宝安店",
      "宝安区示例路3号",
      "香蕉攀岩·福田店",
      "福田区示例路2号",
    ]);
  });

  it("normalizes common brand spellings while preserving store names separately", () => {
    expect(deriveBrandName("BANANA+ COSMO店")).toBe("香蕉攀岩");
    expect(deriveBrandName("香蕉抱石BANANA+(嘉乐道店)")).toBe("香蕉攀岩");
    expect(deriveBrandName("丘山攀岩(CyPARK店)")).toBe("丘山攀岩");
    expect(deriveBrandName("5+Rock 攀岩馆·云间粮仓店")).toBe("5+Rock 攀岩馆");
    expect(deriveBrandName("任意门店", "明确品牌")).toBe("明确品牌");
  });

  it("gives cross-source Banana store aliases one conservative venue identity", () => {
    const venue = (name: string, city = "成都") =>
      deriveCanonicalVenueId({ name, city });

    expect(venue("香蕉攀岩 凯德天府店")).toBe(
      venue("香蕉攀岩(凯德天府店)"),
    );
    expect(venue("香蕉攀岩 环贸ICD店")).toBe(
      venue("香蕉攀岩(环贸ICD店)"),
    );
    expect(venue("BANANA+ COSMO店")).toBe(
      venue("BANANA+香蕉攀岩(COSMO店)"),
    );
    expect(venue("BANANA+ 华发中城商都店", "武汉")).toBe(
      venue("BANANA+香蕉攀岩(华发中城店)", "武汉"),
    );
    expect(venue("香蕉攀岩 后海汇店", "深圳")).toBe(
      venue("香蕉攀岩(深圳湾后海汇店)", "深圳"),
    );
    expect(venue("香蕉攀岩 卓悦汇店", "深圳")).toBe(
      venue("香蕉攀岩(卓悦汇购物中心店)", "深圳"),
    );
    expect(venue("香蕉攀岩 悠方店")).not.toBe(
      venue("香蕉攀岩 凯德天府店"),
    );
    expect(venue("香蕉攀岩 凯德天府店", "成都")).not.toBe(
      venue("香蕉攀岩 凯德天府店", "上海"),
    );
    expect(deriveCanonicalVenueId({ name: "香蕉攀岩", city: "成都" })).toBe(
      undefined,
    );
    expect(
      deriveCanonicalVenueId({ name: "别的品牌 凯德天府店", city: "成都" }),
    ).toBeUndefined();
  });

  it("inserts once and reuses the same gym on a repeated seed run", async () => {
    let gymExists = false;
    const statements: string[] = [];
    const runQuery = vi.fn(async (sql: string) => {
      statements.push(sql);
      if (sql.includes("INSERT INTO gym_brands")) {
        return { rows: [{ id: "brand-id" }], rowCount: 1 };
      }
      if (sql.includes("SELECT id,source_name")) {
        return gymExists
          ? {
              rows: [
                {
                  id: "gym-id",
                  source_name: "测试公开目录",
                  source_match: true,
                },
              ],
              rowCount: 1,
            }
          : { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO gyms")) gymExists = true;
      return { rows: [], rowCount: 0 };
    }) as unknown as SeedQuery;

    await expect(seedGymDirectory(runQuery, directory)).resolves.toEqual({
      inserted: 1,
      reused: 0,
    });
    await expect(seedGymDirectory(runQuery, directory)).resolves.toEqual({
      inserted: 0,
      reused: 1,
    });

    expect(
      statements.filter((sql) => sql.includes("INSERT INTO gyms(")),
    ).toHaveLength(1);
    expect(
      statements.some((sql) => sql.includes("source_external_id=$2")),
    ).toBe(true);
    expect(statements.some((sql) => sql.includes("UPDATE gyms SET"))).toBe(
      true,
    );
    const update =
      statements.find((sql) => sql.includes("UPDATE gyms SET")) ?? "";
    expect(update).toContain("name=CASE WHEN $15 THEN $2 ELSE name END");
    expect(update).toContain("brand_id=$10");
    expect(update).not.toContain("brand_id=coalesce");
  });

  it("conservatively reuses an explicitly shared canonical venue across sources", async () => {
    const aliases: PublicGymDirectory = {
      gyms: [
        {
          ...directory.gyms[0]!,
          canonicalVenueId: "cn:shenzhen:banana-nanshan",
          source: {
            name: "公开地图",
            url: "https://example.com/map/banana-nanshan",
          },
        },
        {
          ...directory.gyms[0]!,
          canonicalVenueId: "cn:shenzhen:banana-nanshan",
          source: {
            name: "公开岩馆目录",
            url: "https://example.com/directory/banana-nanshan",
            external_id: "directory-banana-nanshan",
          },
        },
      ],
    };
    let insertedCanonical = false;
    let selectCount = 0;
    const statements: Array<{ sql: string; values: unknown[] }> = [];
    const runQuery = vi.fn(async (sql: string, values: unknown[] = []) => {
      statements.push({ sql, values });
      if (sql.includes("INSERT INTO gym_brands")) {
        return { rows: [{ id: "brand-id" }], rowCount: 1 };
      }
      if (sql.includes("SELECT id,source_name")) {
        selectCount += 1;
        if (selectCount === 2) {
          return {
            rows: [
              {
                id: "canonical-gym-id",
                source_name: "公开地图",
                source_match: false,
              },
              {
                id: "preexisting-alias-gym-id",
                source_name: "公开岩馆目录",
                source_match: true,
              },
            ],
            rowCount: 2,
          };
        }
        return insertedCanonical
          ? {
              rows: [
                {
                  id: "canonical-gym-id",
                  source_name: "公开地图",
                  source_match: true,
                },
              ],
              rowCount: 1,
            }
          : { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO gyms")) insertedCanonical = true;
      return { rows: [], rowCount: 0 };
    }) as unknown as SeedQuery;

    await expect(seedGymDirectory(runQuery, aliases)).resolves.toEqual({
      inserted: 1,
      reused: 1,
    });
    expect(
      statements.filter(({ sql }) => sql.includes("INSERT INTO gyms(")),
    ).toHaveLength(1);
    const selects = statements.filter(({ sql }) =>
      sql.includes("SELECT id,source_name"),
    );
    expect(selects).toHaveLength(2);
    expect(
      selects.every(({ sql }) => sql.includes("canonical_venue_id=$1")),
    ).toBe(true);
    expect(
      selects.every(({ values }) => values[0] === "cn:shenzhen:banana-nanshan"),
    ).toBe(true);
    expect(
      statements.some(({ sql }) =>
        sql.includes("UPDATE route_sets SET gym_id=$1 WHERE gym_id=$2"),
      ),
    ).toBe(true);
    expect(
      statements.some(
        ({ sql }) =>
          sql.includes("verified=canonical.verified OR alias.verified") &&
          sql.includes(
            "cover_url=coalesce(canonical.cover_url,alias.cover_url)",
          ),
      ),
    ).toBe(true);
    expect(
      statements.some(
        ({ sql, values }) =>
          sql === "DELETE FROM gyms WHERE id=$1" &&
          values[0] === "preexisting-alias-gym-id",
      ),
    ).toBe(true);
  });

  it("merges Banana aliases while keeping the official venue label and address", async () => {
    const aliases: PublicGymDirectory = {
      gyms: [
        {
          ...directory.gyms[0]!,
          name: "香蕉攀岩 凯德天府店",
          city: "成都",
          address: "成都市武侯区天仁路388号凯德天府L5-15铺",
          source: {
            name: "香蕉攀岩公开门店服务（climbing-go）",
            url: "https://example.com/official/kaide",
            external_id: "official-kaide",
          },
        },
        {
          ...directory.gyms[0]!,
          name: "香蕉攀岩(凯德天府店)",
          city: "成都",
          address: "天和西三街凯德天府",
          source: {
            name: "攀岩么公开岩馆接口",
            url: "https://example.com/directory/kaide",
            external_id: "directory-kaide",
          },
        },
      ],
    };
    let selectCount = 0;
    const statements: Array<{ sql: string; values: unknown[] }> = [];
    const runQuery = vi.fn(async (sql: string, values: unknown[] = []) => {
      statements.push({ sql, values });
      if (sql.includes("INSERT INTO gym_brands")) {
        return { rows: [{ id: "brand-id" }], rowCount: 1 };
      }
      if (sql.includes("SELECT id,source_name")) {
        selectCount += 1;
        if (selectCount === 1) {
          return {
            rows: [
              {
                id: "official-gym-id",
                source_name: "香蕉攀岩公开门店服务（climbing-go）",
                source_match: true,
              },
            ],
            rowCount: 1,
          };
        }
        return {
          rows: [
            {
              id: "official-gym-id",
              source_name: "香蕉攀岩公开门店服务（climbing-go）",
              source_match: false,
            },
            {
              id: "directory-alias-id",
              source_name: "攀岩么公开岩馆接口",
              source_match: true,
            },
          ],
          rowCount: 2,
        };
      }
      return { rows: [], rowCount: 0 };
    }) as unknown as SeedQuery;

    await expect(seedGymDirectory(runQuery, aliases)).resolves.toEqual({
      inserted: 0,
      reused: 2,
    });

    const venueIds = statements
      .filter(({ sql }) => sql.includes("SELECT id,source_name"))
      .map(({ values }) => values[0]);
    expect(new Set(venueIds)).toEqual(
      new Set(["directory:banana:成都:凯德天府"]),
    );
    const venueUpdates = statements.filter(({ sql }) =>
      sql.includes("UPDATE gyms SET"),
    );
    expect(venueUpdates[0]?.values.at(-1)).toBe(true);
    expect(venueUpdates[1]?.values.at(-1)).toBe(false);
    expect(
      statements.some(
        ({ sql, values }) =>
          sql === "DELETE FROM gyms WHERE id=$1" &&
          values[0] === "directory-alias-id",
      ),
    ).toBe(true);
  });

  it("requires an explicit one-command opt-in for production directory imports", () => {
    expect(() =>
      assertGymDirectoryImportAllowed("development", false),
    ).not.toThrow();
    expect(() => assertGymDirectoryImportAllowed("test", false)).not.toThrow();
    expect(() =>
      assertGymDirectoryImportAllowed("production", true),
    ).not.toThrow();
    expect(() => assertGymDirectoryImportAllowed("production", false)).toThrow(
      "ALLOW_PRODUCTION_GYM_IMPORT=true",
    );
  });

  it("keeps only the two reviewed cross-source aliases canonicalized", async () => {
    const source = JSON.parse(
      await readFile(
        new URL("../../data/gyms.public-verified.json", import.meta.url),
        "utf8",
      ),
    ) as PublicGymDirectory;
    const canonical = source.gyms.filter((gym) => gym.canonicalVenueId);
    const groups = new Map<string, PublicGymDirectory["gyms"]>();
    for (const gym of canonical) {
      const key = gym.canonicalVenueId!;
      groups.set(key, [...(groups.get(key) ?? []), gym]);
    }

    expect([...groups.keys()].sort()).toEqual([
      "cn:chengdu:qiushan-cypark",
      "cn:guangzhou:unfollow-haizhu-shixi",
    ]);
    for (const aliases of groups.values()) {
      expect(aliases).toHaveLength(2);
      expect(new Set(aliases.map((gym) => gym.name)).size).toBe(1);
      expect(new Set(aliases.map((gym) => gym.address)).size).toBe(1);
      expect(new Set(aliases.map((gym) => gym.brandName)).size).toBe(1);
      expect(new Set(aliases.map((gym) => gym.source.name)).size).toBe(2);
    }
  });

  it("collapses every reviewed Banana alias pair without identity collisions", async () => {
    const source = JSON.parse(
      await readFile(
        new URL("../../data/gyms.public-verified.json", import.meta.url),
        "utf8",
      ),
    ) as PublicGymDirectory;
    const banana = source.gyms.filter(
      (gym) => deriveBrandName(gym.name, gym.brandName) === "香蕉攀岩",
    );
    const venueIds = banana.map((gym) => deriveCanonicalVenueId(gym));
    const counts = new Map<string, number>();
    for (const venueId of venueIds) {
      expect(venueId).toBeTruthy();
      counts.set(venueId!, (counts.get(venueId!) ?? 0) + 1);
    }

    expect(banana).toHaveLength(57);
    expect(counts.size).toBe(34);
    expect([...counts.values()].filter((count) => count === 2)).toHaveLength(
      23,
    );
    expect(Math.max(...counts.values())).toBe(2);
  });

  it("keeps varied mock posts development-only and makes every write idempotent", async () => {
    const statements: Array<{ sql: string; values: unknown[] }> = [];
    const runQuery = vi.fn(async (sql: string, values: unknown[] = []) => {
      statements.push({ sql, values });
      if (sql.includes("INSERT INTO gym_brands")) {
        return { rows: [{ id: values[0] }], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO users")) {
        return { rows: [{ id: values[0] }], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO sends")) {
        return { rows: [{ id: values[0] }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    }) as unknown as SeedQuery;

    expect(shouldSeedDevelopmentSquare("development")).toBe(true);
    expect(shouldSeedDevelopmentSquare("test")).toBe(false);
    expect(shouldSeedDevelopmentSquare("production")).toBe(false);
    await expect(seedDevelopmentSquare(runQuery, "production")).rejects.toThrow(
      "disabled outside NODE_ENV=development",
    );
    expect(runQuery).not.toHaveBeenCalled();

    await expect(seedDevelopmentSquare(runQuery, "development")).resolves.toBe(
      10,
    );

    const sendCalls = statements.filter(({ sql }) =>
      sql.includes("INSERT INTO sends"),
    );
    expect(sendCalls).toHaveLength(10);
    expect(
      sendCalls.filter(({ values }) => values[5] === "public"),
    ).toHaveLength(8);
    expect(sendCalls.map(({ values }) => values[5])).toEqual(
      expect.arrayContaining(["friends", "private"]),
    );
    expect(sendCalls.map(({ values }) => values[3])).toEqual(
      expect.arrayContaining([1, 2, 4, 7, 9, 12]),
    );
    for (const call of sendCalls) {
      expect(call.sql).toContain("ON CONFLICT(user_id,route_id) DO UPDATE");
      expect(call.values[4]).toMatch(/^【开发示例】/u);
    }
    expect(
      statements.filter(({ sql }) => sql.includes("INSERT INTO post_likes")),
    ).toHaveLength(14);
    expect(
      statements.filter(({ sql }) => sql.includes("INSERT INTO comments")),
    ).toHaveLength(5);
    for (const table of [
      "gym_brands",
      "gyms",
      "route_sets",
      "routes",
      "users",
      "sends",
      "post_likes",
      "comments",
    ]) {
      const writes = statements.filter(({ sql }) =>
        sql.includes(`INSERT INTO ${table}`),
      );
      expect(writes.length).toBeGreaterThan(0);
      expect(writes.every(({ sql }) => sql.includes("ON CONFLICT"))).toBe(true);
    }
    const remoteMediaValues = statements
      .flatMap(({ values }) => values)
      .filter((value): value is string => typeof value === "string")
      .filter((value) => /^https?:\/\//u.test(value));
    expect(remoteMediaValues).toEqual([]);
  });
});
