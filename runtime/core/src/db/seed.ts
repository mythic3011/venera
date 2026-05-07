import { sql, type Kysely } from "kysely";

import type { CoreDatabaseSchema } from "./schema.js";

export const LOCAL_SOURCE_PLATFORM_ID =
  "00000000-0000-4000-8000-000000000001";

export async function seedCoreDatabase(
  db: Kysely<CoreDatabaseSchema>,
): Promise<void> {
  const timestamp = new Date().toISOString();

  await sql`
    INSERT INTO source_platforms (
      id,
      canonical_key,
      display_name,
      kind,
      status,
      created_at,
      updated_at
    )
    VALUES (
      ${LOCAL_SOURCE_PLATFORM_ID},
      'local',
      'Local',
      'local',
      'active',
      ${timestamp},
      ${timestamp}
    )
    ON CONFLICT(canonical_key) DO UPDATE SET
      display_name = excluded.display_name,
      kind = excluded.kind,
      status = excluded.status,
      updated_at = excluded.updated_at
  `.execute(db);
}
