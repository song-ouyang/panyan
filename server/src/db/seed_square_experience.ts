import type { QueryResultRow } from "pg";
import { config } from "../config.js";
import { pool, transaction } from "../db.js";
import {
  assertSquareExperienceSeedAllowed,
  runSquareExperienceSeed,
  type SquareExperienceSeedQuery,
} from "./seed_square_experience_support.js";

try {
  // Reject an unauthorized production invocation before opening a database
  // transaction. runSquareExperienceSeed repeats this check so other callers
  // cannot accidentally bypass the same safety boundary.
  assertSquareExperienceSeedAllowed(
    config.NODE_ENV,
    config.ALLOW_PRODUCTION_SQUARE_SEED,
  );
  const result = await transaction(async (client) => {
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
      ["wanpan:square-experience-seed:v1"],
    );
    const runQuery: SquareExperienceSeedQuery = async <
      T extends QueryResultRow = QueryResultRow,
    >(
      text: string,
      values: unknown[] = [],
    ) => client.query<T>(text, values);

    return runSquareExperienceSeed(
      runQuery,
      config.NODE_ENV,
      config.ALLOW_PRODUCTION_SQUARE_SEED,
    );
  });

  console.log(
    `Square experience seed complete: ${result.users} users, ` +
      `${result.posts} public posts, ${result.likes} likes, ` +
      `${result.comments} comments upserted`,
  );
} finally {
  await pool.end();
}
