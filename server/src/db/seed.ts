import { readFile } from "node:fs/promises";
import type { QueryResultRow } from "pg";
import { z } from "zod";
import { config } from "../config.js";
import { pool, transaction } from "../db.js";
import {
  assertGymDirectoryImportAllowed,
  removeLegacyDemoGyms,
  seedDevelopmentSquare,
  seedGymDirectory,
  shouldSeedDevelopmentSquare,
  type PublicGymDirectory,
  type SeedQuery,
} from "./seed_support.js";

const publicGymDirectorySchema = z.object({
  gyms: z.array(
    z.object({
      name: z.string().trim().min(1).max(80),
      province: z.string().trim().min(1).max(40),
      city: z.string().trim().min(1).max(40),
      district: z.string().trim().min(1).max(40),
      address: z.string().trim().min(1).max(160),
      latitude: z.number().finite().min(-90).max(90).optional(),
      longitude: z.number().finite().min(-180).max(180).optional(),
      description: z.string().trim().min(1),
      brandName: z.string().trim().min(1).max(80).optional(),
      canonicalVenueId: z.string().trim().min(1).max(120).optional(),
      source: z.object({
        name: z.string().trim().min(1),
        url: z.string().url(),
        external_id: z.string().trim().min(1).optional(),
      }),
    }),
  ),
});

const sourceFile = new URL(
  "../../../data/gyms.public-verified.json",
  import.meta.url,
);

try {
  assertGymDirectoryImportAllowed(
    config.NODE_ENV,
    config.ALLOW_PRODUCTION_GYM_IMPORT,
  );
  const source = JSON.parse(await readFile(sourceFile, "utf8")) as unknown;
  const directory = publicGymDirectorySchema.parse(
    source,
  ) as PublicGymDirectory;
  const { gyms, developmentPosts, removedLegacyGyms } = await transaction(async (client) => {
    const runQuery: SeedQuery = async <
      T extends QueryResultRow = QueryResultRow,
    >(
      text: string,
      values: unknown[] = [],
    ) => client.query<T>(text, values);

    const removedLegacyGyms = await removeLegacyDemoGyms(runQuery);
    const gyms = await seedGymDirectory(runQuery, directory);
    const developmentPosts = shouldSeedDevelopmentSquare(config.NODE_ENV)
      ? await seedDevelopmentSquare(runQuery, config.NODE_ENV)
      : 0;
    return { gyms, developmentPosts, removedLegacyGyms };
  });

  console.log(
    `Seed complete: ${removedLegacyGyms} legacy demo gyms removed, ` +
      `${gyms.inserted} gyms inserted, ${gyms.reused} reused, ` +
      `${developmentPosts} explicit development posts upserted`,
  );
} finally {
  await pool.end();
}
