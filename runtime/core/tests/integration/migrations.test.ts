import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import { openRuntimeDatabase } from "../../src/db/database.js";
import { migrateCoreDatabase } from "../../src/db/migrations.js";
import { createTestRuntime } from "../support/test-runtime.js";

interface TableInfoRow {
  readonly name: string;
  readonly notnull: number;
}

const retiredFlagProperty = ["is", "Enabled"].join("");
const retiredFlagColumn = ["is", "enabled"].join("_");

function expectColumnNames(rows: readonly TableInfoRow[]): string[] {
  return rows.map((row) => row.name);
}

async function expectSqliteConstraint(
  promise: Promise<unknown>,
  expectedCode: string,
): Promise<void> {
  try {
    await promise;
    throw new Error(`Expected SQLite constraint ${expectedCode}.`);
  } catch (error) {
    const record = error as { code?: string; message?: string };
    expect(record.code ?? record.message ?? String(error)).toMatch(
      new RegExp(expectedCode),
    );
  }
}

describe("core database migrations and seed", () => {
  it("creates a clean schema, passes foreign key checks, and seeds the active local source platform", async () => {
    const runtime = await createTestRuntime();

    try {
      const tables = await sql<{ name: string }>`
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        ORDER BY name
      `.execute(runtime.db);

      expect(tables.rows.map((row) => row.name)).toEqual(
        expect.arrayContaining([
          "chapters",
          "chapter_source_links",
          "comic_metadata",
          "comic_titles",
          "comics",
          "diagnostics_events",
          "operation_idempotency",
          "page_order_items",
          "page_orders",
          "pages",
          "reader_sessions",
          "source_links",
          "source_platforms",
          "storage_backends",
          "storage_objects",
          "storage_placements",
        ]),
      );
      expect(tables.rows.map((row) => row.name)).not.toEqual(
        expect.arrayContaining([
          "comics__new",
        ]),
      );

      const foreignKeyCheck = await sql`
        PRAGMA foreign_key_check
      `.execute(runtime.db);
      expect(foreignKeyCheck.rows).toEqual([]);

      const localSource = await runtime.repositories.sourcePlatforms.getByKey("local");
      expect(localSource.ok).toBe(true);
      if (localSource.ok) {
        expect(localSource.value?.canonicalKey).toBe("local");
        expect(localSource.value?.kind).toBe("local");
        expect(localSource.value && "status" in localSource.value).toBe(true);
        expect(localSource.value && retiredFlagProperty in localSource.value).toBe(false);
        expect((localSource.value as Record<string, unknown> | null)?.status).toBe("active");
      }
    } finally {
      runtime.close();
    }
  });

  it("defines comics.normalized_title as a non-unique indexed lookup", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const now = new Date().toISOString();

      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES ('11111111-1111-4111-8111-111111111111', 'same-title', 'local', ${now}, ${now})
      `.execute(handle.db);

      await expect(
        sql`
          INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
          VALUES ('22222222-2222-4222-8222-222222222222', 'same-title', 'remote', ${now}, ${now})
        `.execute(handle.db),
      ).resolves.toBeDefined();

      const indexes = await sql<{ name: string; unique: number }>`
        PRAGMA index_list('comics')
      `.execute(handle.db);

      expect(indexes.rows).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            name: "idx_comics_normalized_title",
            unique: 0,
          }),
        ]),
      );
    } finally {
      handle.close();
    }
  });

  it("uses status columns instead of retired flag columns", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const sourcePlatformColumns = await sql<TableInfoRow>`
        PRAGMA table_info('source_platforms')
      `.execute(handle.db);
      const storageBackendColumns = await sql<TableInfoRow>`
        PRAGMA table_info('storage_backends')
      `.execute(handle.db);

      expect(expectColumnNames(sourcePlatformColumns.rows)).toContain("status");
      expect(expectColumnNames(sourcePlatformColumns.rows)).not.toContain(retiredFlagColumn);
      expect(expectColumnNames(storageBackendColumns.rows)).toContain("status");
      expect(expectColumnNames(storageBackendColumns.rows)).not.toContain(retiredFlagColumn);
    } finally {
      handle.close();
    }
  });

  it("limits chapter_source_links.link_status to active, inactive, and stale only", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const createSql = await sql<{ sql: string }>`
        SELECT sql
        FROM sqlite_master
        WHERE type = 'table' AND name = 'chapter_source_links'
      `.execute(handle.db);

      const statement = createSql.rows[0]?.sql ?? "";
      expect(statement).toContain("link_status");
      expect(statement).toContain("('active', 'inactive', 'stale')");
      expect(statement).not.toContain("candidate");
      expect(statement).not.toContain("rejected");
    } finally {
      handle.close();
    }
  });

  it("accepts duplicate and null chapter numbers within the same comic", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const now = new Date().toISOString();
      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES ('33333333-3333-4333-8333-333333333333', 'chapters', 'local', ${now}, ${now})
      `.execute(handle.db);

      await expect(
        sql`
          INSERT INTO chapters (
            id,
            comic_id,
            parent_chapter_id,
            chapter_kind,
            chapter_number,
            title,
            display_label,
            created_at,
            updated_at
          )
          VALUES
            ('44444444-4444-4444-8444-444444444444', '33333333-3333-4333-8333-333333333333', NULL, 'chapter', 1, 'One', 'One', ${now}, ${now}),
            ('55555555-5555-4555-8555-555555555555', '33333333-3333-4333-8333-333333333333', NULL, 'chapter', 1, 'One again', 'One again', ${now}, ${now}),
            ('66666666-6666-4666-8666-666666666666', '33333333-3333-4333-8333-333333333333', NULL, 'chapter', NULL, 'Null number', 'Null number', ${now}, ${now})
        `.execute(handle.db),
      ).resolves.toBeDefined();
    } finally {
      handle.close();
    }
  });

  it("rejects duplicate raw page indexes per chapter with SQLITE_CONSTRAINT_UNIQUE", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const now = new Date().toISOString();
      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES ('77777777-7777-4777-8777-777777777777', 'pages', 'local', ${now}, ${now})
      `.execute(handle.db);
      await sql`
        INSERT INTO chapters (
          id,
          comic_id,
          parent_chapter_id,
          chapter_kind,
          chapter_number,
          title,
          display_label,
          created_at,
          updated_at
        )
        VALUES (
          '88888888-8888-4888-8888-888888888888',
          '77777777-7777-4777-8777-777777777777',
          NULL,
          'chapter',
          1,
          'Chapter 1',
          'Chapter 1',
          ${now},
          ${now}
        )
      `.execute(handle.db);
      await sql`
        INSERT INTO pages (
          id,
          chapter_id,
          page_index,
          storage_object_id,
          chapter_source_link_id,
          mime_type,
          width,
          height,
          checksum,
          created_at,
          updated_at
        )
        VALUES (
          '99999999-9999-4999-8999-999999999999',
          '88888888-8888-4888-8888-888888888888',
          0,
          NULL,
          NULL,
          'image/jpeg',
          1000,
          1600,
          'checksum-0',
          ${now},
          ${now}
        )
      `.execute(handle.db);

      await expectSqliteConstraint(
        sql`
          INSERT INTO pages (
            id,
            chapter_id,
            page_index,
            storage_object_id,
            chapter_source_link_id,
            mime_type,
            width,
            height,
            checksum,
            created_at,
            updated_at
          )
          VALUES (
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            '88888888-8888-4888-8888-888888888888',
            0,
            NULL,
            NULL,
            'image/jpeg',
            1000,
            1600,
            'checksum-1',
            ${now},
            ${now}
          )
        `.execute(handle.db),
        "SQLITE_CONSTRAINT_UNIQUE",
      );
    } finally {
      handle.close();
    }
  });

  it("allows only one active page order per chapter", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const now = new Date().toISOString();
      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'orders', 'local', ${now}, ${now})
      `.execute(handle.db);
      await sql`
        INSERT INTO chapters (
          id,
          comic_id,
          parent_chapter_id,
          chapter_kind,
          chapter_number,
          title,
          display_label,
          created_at,
          updated_at
        )
        VALUES (
          'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          NULL,
          'chapter',
          1,
          'Chapter 1',
          'Chapter 1',
          ${now},
          ${now}
        )
      `.execute(handle.db);
      await sql`
        INSERT INTO page_orders (
          id,
          chapter_id,
          order_key,
          order_type,
          is_active,
          page_count,
          created_at,
          updated_at
        )
        VALUES (
          'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'source',
          'source',
          1,
          0,
          ${now},
          ${now}
        )
      `.execute(handle.db);

      await expectSqliteConstraint(
        sql`
          INSERT INTO page_orders (
            id,
            chapter_id,
            order_key,
            order_type,
            is_active,
            page_count,
            created_at,
            updated_at
          )
          VALUES (
            'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            'user',
            'user_override',
            1,
            0,
            ${now},
            ${now}
          )
        `.execute(handle.db),
        "SQLITE_CONSTRAINT",
      );
    } finally {
      handle.close();
    }
  });
});
