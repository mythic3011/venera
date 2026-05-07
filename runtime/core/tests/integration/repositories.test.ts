import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import {
  CREATE_CANONICAL_COMIC_OPERATION_NAME,
  CREATED_CANONICAL_COMIC_RESULT_TYPE,
  IDEMPOTENCY_RESULT_SCHEMA_VERSION,
  parseIdempotencyKey,
  parseInputHash,
} from "../../src/domain/idempotency.js";
import type { IdempotencyKey, InputHash } from "../../src/domain/idempotency.js";
import type { JsonObject } from "../../src/shared/json.js";
import { createTestRuntime, insertComicFixture } from "../support/test-runtime.js";

function expectIdempotencyKey(value: string): IdempotencyKey {
  const parsed = parseIdempotencyKey(value);
  expect(parsed.ok).toBe(true);
  if (!parsed.ok) {
    throw parsed.error;
  }

  return parsed.value;
}

function expectInputHash(value: string): InputHash {
  const parsed = parseInputHash(value);
  expect(parsed.ok).toBe(true);
  if (!parsed.ok) {
    throw parsed.error;
  }

  return parsed.value;
}

interface DynamicResult {
  readonly ok: boolean;
  readonly value?: unknown;
  readonly error?: {
    readonly code?: string;
  };
}

const retiredFlagProperty = ["is", "Enabled"].join("");
const retiredFlagColumn = ["is", "enabled"].join("_");

function expectRecord(value: unknown): Record<string, unknown> {
  expect(value).not.toBeNull();
  expect(typeof value).toBe("object");
  return value as Record<string, unknown>;
}

describe("sqlite repositories", () => {
  it("returns domain-shaped objects without db snake_case fields or retired flag fields", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime);

      const comic = await runtime.repositories.comics.getById(fixture.comicId as never);
      const chapter = await runtime.repositories.chapters.getById(fixture.chapterIds[0] as never);
      const page = await runtime.repositories.pages.getById(fixture.pageIds[0] as never);
      const sourcePlatform = await runtime.repositories.sourcePlatforms.getByKey("local");

      expect(comic.ok).toBe(true);
      expect(chapter.ok).toBe(true);
      expect(page.ok).toBe(true);
      expect(sourcePlatform.ok).toBe(true);

      if (comic.ok && comic.value) {
        expect("normalized_title" in comic.value).toBe(false);
        expect(comic.value.normalizedTitle).toBeTypeOf("string");
      }

      if (chapter.ok && chapter.value) {
        expect("chapter_kind" in chapter.value).toBe(false);
        expect(chapter.value.chapterKind).toBe("chapter");
      }

      if (page.ok && page.value) {
        expect("page_index" in page.value).toBe(false);
        expect(page.value.pageIndex).toBe(0);
      }

      if (sourcePlatform.ok && sourcePlatform.value) {
        const record = expectRecord(sourcePlatform.value);
        expect(record).not.toHaveProperty(retiredFlagProperty);
        expect(record).toHaveProperty("status", "active");
      }
    } finally {
      runtime.close();
    }
  });

  it("lists all comics sharing the same normalized title", async () => {
    const runtime = await createTestRuntime();

    try {
      const first = await insertComicFixture(runtime, {
        comicId: "11111111-1111-4111-8111-111111111111",
        title: "Shared Title",
      });
      const second = await insertComicFixture(runtime, {
        comicId: "22222222-2222-4222-8222-222222222222",
        title: "Shared Title",
      });

      const comics = await runtime.repositories.comics.listByNormalizedTitle("shared title" as never);

      expect(comics.ok).toBe(true);
      if (comics.ok) {
        expect(comics.value.map((comic) => comic.id)).toEqual([
          first.comicId,
          second.comicId,
        ]);
        expect(comics.value.every((comic) => "normalized_title" in comic)).toBe(false);
      }
    } finally {
      runtime.close();
    }
  });

  it("filters source platforms by active status only and orders them by display name", async () => {
    const runtime = await createTestRuntime();

    try {
      const columns = await sql<{ name: string }>`
        PRAGMA table_info('source_platforms')
      `.execute(runtime.db);
      expect(columns.rows.map((row) => row.name)).toContain("status");
      expect(columns.rows.map((row) => row.name)).not.toContain(retiredFlagColumn);

      const now = new Date().toISOString();
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
        VALUES
          ('11111111-aaaa-4111-8111-111111111111', 'zeta', 'Zeta', 'remote', 'active', ${now}, ${now}),
          ('22222222-bbbb-4222-8222-222222222222', 'beta', 'Beta', 'remote', 'disabled', ${now}, ${now}),
          ('33333333-cccc-4333-8333-333333333333', 'alpha', 'Alpha', 'remote', 'active', ${now}, ${now}),
          ('44444444-dddd-4444-8444-444444444444', 'omega', 'Omega', 'remote', 'deprecated', ${now}, ${now})
      `.execute(runtime.db);

      const listed = await runtime.repositories.sourcePlatforms.listByStatus("active");

      expect(listed.ok).toBe(true);
      if (listed.ok) {
        expect(listed.value.map((platform) => platform.canonicalKey)).toEqual([
          "alpha",
          "local",
          "zeta",
        ]);
        expect(listed.value.every((platform) => retiredFlagProperty in platform)).toBe(false);
        expect(
          listed.value.every(
            (platform) => expectRecord(platform).status === "active",
          ),
        ).toBe(true);
      }
    } finally {
      runtime.close();
    }
  });

  it("owns the full source platform 3x3 status transition matrix", async () => {
    const runtime = await createTestRuntime();

    try {
      const repositorySurface = runtime.repositories.sourcePlatforms as unknown as {
        updateStatus?: (input: {
          id: string;
          status: string;
        }) => Promise<DynamicResult>;
      };
      expect(typeof repositorySurface.updateStatus).toBe("function");
      if (repositorySurface.updateStatus === undefined) {
        return;
      }

      const now = new Date().toISOString();
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
        VALUES
          ('55555555-eeee-4555-8555-555555555555', 'matrix-active', 'Matrix Active', 'remote', 'active', ${now}, ${now}),
          ('66666666-ffff-4666-8666-666666666666', 'matrix-disabled', 'Matrix Disabled', 'remote', 'disabled', ${now}, ${now}),
          ('77777777-aaaa-4777-8777-777777777777', 'matrix-deprecated', 'Matrix Deprecated', 'remote', 'deprecated', ${now}, ${now})
      `.execute(runtime.db);

      const matrix = [
        ["55555555-eeee-4555-8555-555555555555", "active", "active", true],
        ["55555555-eeee-4555-8555-555555555555", "active", "disabled", true],
        ["55555555-eeee-4555-8555-555555555555", "active", "deprecated", true],
        ["66666666-ffff-4666-8666-666666666666", "disabled", "active", true],
        ["66666666-ffff-4666-8666-666666666666", "disabled", "disabled", true],
        ["66666666-ffff-4666-8666-666666666666", "disabled", "deprecated", true],
        ["77777777-aaaa-4777-8777-777777777777", "deprecated", "deprecated", true],
        ["77777777-aaaa-4777-8777-777777777777", "deprecated", "active", false],
        ["77777777-aaaa-4777-8777-777777777777", "deprecated", "disabled", false],
      ] as const;

      for (const [platformId, fromStatus, toStatus, shouldSucceed] of matrix) {
        const result = await repositorySurface.updateStatus({
          id: platformId,
          status: toStatus,
        });

        expect(result.ok, `${fromStatus} -> ${toStatus}`).toBe(shouldSucceed);
        if (!shouldSucceed) {
          expect(result.error?.code).toBe("VALIDATION_ERROR");
        }
      }
    } finally {
      runtime.close();
    }
  });

  it("orders chapters by MIN(source_order) from active non-null chapter links on active platforms only", async () => {
    const runtime = await createTestRuntime();

    try {
      const platformColumns = await sql<{ name: string }>`
        PRAGMA table_info('source_platforms')
      `.execute(runtime.db);
      expect(platformColumns.rows.map((row) => row.name)).toContain("status");

      const chapterLinkColumns = await sql<{ name: string }>`
        PRAGMA table_info('chapter_source_links')
      `.execute(runtime.db);
      expect(chapterLinkColumns.rows.map((row) => row.name)).toEqual(
        expect.arrayContaining([
          "source_order",
          "link_status",
        ]),
      );

      const now = new Date().toISOString();
      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES ('88888888-bbbb-4888-8888-888888888888', 'ordered-comic', 'local', ${now}, ${now})
      `.execute(runtime.db);

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
        VALUES
          ('99999999-cccc-4999-8999-999999999999', '88888888-bbbb-4888-8888-888888888888', NULL, 'chapter', 100, 'A', 'A', ${now}, ${now}),
          ('aaaaaaaa-dddd-4aaa-8aaa-aaaaaaaaaaaa', '88888888-bbbb-4888-8888-888888888888', NULL, 'chapter', 200, 'B', 'B', ${now}, ${now}),
          ('bbbbbbbb-eeee-4bbb-8bbb-bbbbbbbbbbbb', '88888888-bbbb-4888-8888-888888888888', NULL, 'chapter', 300, 'C', 'C', ${now}, ${now})
      `.execute(runtime.db);

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
        VALUES
          ('cccccccc-ffff-4ccc-8ccc-cccccccccccc', 'active-platform', 'Active Platform', 'remote', 'active', ${now}, ${now}),
          ('dddddddd-aaaa-4ddd-8ddd-dddddddddddd', 'disabled-platform', 'Disabled Platform', 'remote', 'disabled', ${now}, ${now}),
          ('eeeeeeee-bbbb-4eee-8eee-eeeeeeeeeeee', 'deprecated-platform', 'Deprecated Platform', 'remote', 'deprecated', ${now}, ${now})
      `.execute(runtime.db);

      await sql`
        INSERT INTO source_links (
          id,
          comic_id,
          source_platform_id,
          remote_work_id,
          remote_url,
          display_title,
          link_status,
          confidence,
          created_at,
          updated_at
        )
        VALUES
          ('ffffffff-cccc-4fff-8fff-ffffffffffff', '88888888-bbbb-4888-8888-888888888888', 'cccccccc-ffff-4ccc-8ccc-cccccccccccc', 'active-work', NULL, NULL, 'active', 'manual', ${now}, ${now}),
          ('12121212-dddd-4212-8212-121212121212', '88888888-bbbb-4888-8888-888888888888', 'dddddddd-aaaa-4ddd-8ddd-dddddddddddd', 'disabled-work', NULL, NULL, 'active', 'manual', ${now}, ${now}),
          ('34343434-eeee-4434-8434-343434343434', '88888888-bbbb-4888-8888-888888888888', 'eeeeeeee-bbbb-4eee-8eee-eeeeeeeeeeee', 'deprecated-work', NULL, NULL, 'active', 'manual', ${now}, ${now})
      `.execute(runtime.db);

      await sql`
        INSERT INTO chapter_source_links (
          id,
          chapter_id,
          source_link_id,
          remote_chapter_id,
          remote_url,
          remote_label,
          source_order,
          link_status,
          created_at,
          updated_at
        )
        VALUES
          ('56565656-ffff-4565-8565-565656565656', '99999999-cccc-4999-8999-999999999999', 'ffffffff-cccc-4fff-8fff-ffffffffffff', 'chapter-a-active', NULL, NULL, 30, 'active', ${now}, ${now}),
          ('78787878-aaaa-4787-8787-787878787878', '99999999-cccc-4999-8999-999999999999', 'ffffffff-cccc-4fff-8fff-ffffffffffff', 'chapter-a-stale', NULL, NULL, 1, 'stale', ${now}, ${now}),
          ('90909090-bbbb-4909-8909-909090909090', 'aaaaaaaa-dddd-4aaa-8aaa-aaaaaaaaaaaa', 'ffffffff-cccc-4fff-8fff-ffffffffffff', 'chapter-b-active', NULL, NULL, 10, 'active', ${now}, ${now}),
          ('abababab-cccc-4aba-8aba-abababababab', 'aaaaaaaa-dddd-4aaa-8aaa-aaaaaaaaaaaa', '12121212-dddd-4212-8212-121212121212', 'chapter-b-disabled-platform', NULL, NULL, 2, 'active', ${now}, ${now}),
          ('cdcdcdcd-dddd-4cdc-8cdc-cdcdcdcdcdcd', 'bbbbbbbb-eeee-4bbb-8bbb-bbbbbbbbbbbb', '34343434-eeee-4434-8434-343434343434', 'chapter-c-deprecated-platform', NULL, NULL, 5, 'active', ${now}, ${now}),
          ('efefefef-eeee-4efe-8efe-efefefefefef', 'bbbbbbbb-eeee-4bbb-8bbb-bbbbbbbbbbbb', 'ffffffff-cccc-4fff-8fff-ffffffffffff', 'chapter-c-null-order', NULL, NULL, NULL, 'active', ${now}, ${now})
      `.execute(runtime.db);

      const listed = await runtime.repositories.chapters.listByComic("88888888-bbbb-4888-8888-888888888888" as never);

      expect(listed.ok).toBe(true);
      if (listed.ok) {
        expect(listed.value.map((chapter) => chapter.id)).toEqual([
          "99999999-cccc-4999-8999-999999999999",
          "aaaaaaaa-dddd-4aaa-8aaa-aaaaaaaaaaaa",
          "bbbbbbbb-eeee-4bbb-8bbb-bbbbbbbbbbbb",
        ]);
      }
    } finally {
      runtime.close();
    }
  });

  it("persists diagnostics schemaVersion as 1.0.0", async () => {
    const runtime = await createTestRuntime();

    try {
      const recorded = await runtime.repositories.diagnosticsEvents.record({
        id: "33333333-3333-4333-8333-333333333333" as never,
        timestamp: new Date("2026-05-05T00:00:00.000Z"),
        level: "warn",
        channel: "reader.route",
        eventName: "reader.route.unresolved_target",
        payload: {
          reason: "test",
        },
      });

      expect(recorded.ok).toBe(true);
      if (recorded.ok) {
        expect(recorded.value.schemaVersion).toBe("1.0.0");
      }

      const queried = await runtime.repositories.diagnosticsEvents.query({
        channel: "reader.route",
      });

      expect(queried.ok).toBe(true);
      if (queried.ok) {
        expect(queried.value[0]?.schemaVersion).toBe("1.0.0");
      }

      const rows = await sql<{ schema_version: string }>`
        SELECT schema_version
        FROM diagnostics_events
        WHERE id = '33333333-3333-4333-8333-333333333333'
      `.execute(runtime.db);

      expect(rows.rows[0]?.schema_version).toBe("1.0.0");
    } finally {
      runtime.close();
    }
  });

  it("round-trips completed operation idempotency with a strict public DTO result", async () => {
    const runtime = await createTestRuntime();

    try {
      const reserved = await runtime.repositories.operationIdempotency.createInProgress({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-key-1"),
        inputHash: expectInputHash("hash-1"),
        createdAt: new Date("2026-05-05T00:00:00.000Z"),
        updatedAt: new Date("2026-05-05T00:00:00.000Z"),
      });

      expect(reserved.ok).toBe(true);
      if (!reserved.ok) {
        return;
      }
      expect(reserved.value.status).toBe("in_progress");

      const completed = await runtime.repositories.operationIdempotency.markCompleted({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-key-1"),
        inputHash: expectInputHash("hash-1"),
        resultType: CREATED_CANONICAL_COMIC_RESULT_TYPE,
        resultResourceId: "44444444-4444-4444-8444-444444444444" as never,
        resultSchemaVersion: IDEMPOTENCY_RESULT_SCHEMA_VERSION,
        updatedAt: new Date("2026-05-05T00:01:00.000Z"),
        resultJson: {
          comic: {
            id: "44444444-4444-4444-8444-444444444444" as never,
            normalizedTitle: "shared title",
            originHint: "local",
            createdAt: "2026-05-05T00:00:00.000Z",
            updatedAt: "2026-05-05T00:00:00.000Z",
          },
          metadata: {
            comicId: "44444444-4444-4444-8444-444444444444" as never,
            title: "Shared Title",
            createdAt: "2026-05-05T00:00:00.000Z",
            updatedAt: "2026-05-05T00:00:00.000Z",
          },
          primaryTitle: {
            id: "55555555-5555-4555-8555-555555555555",
            comicId: "44444444-4444-4444-8444-444444444444" as never,
            title: "Shared Title",
            normalizedTitle: "shared title",
            titleKind: "primary",
            createdAt: "2026-05-05T00:00:00.000Z",
          },
        },
      });

      expect(completed.ok).toBe(true);
      if (!completed.ok) {
        return;
      }
      expect(completed.value.status).toBe("completed");
      if (completed.value.status === "completed") {
        expect(completed.value.resultSchemaVersion).toBe("1.0.0");
      }

      const replay = await runtime.repositories.operationIdempotency.get({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-key-1"),
      });

      expect(replay.ok).toBe(true);
      if (replay.ok && replay.value !== null && replay.value.status === "completed") {
        const resultJson = replay.value.resultJson as JsonObject;
        const comic = resultJson.comic as JsonObject;
        expect(comic.normalizedTitle).toBe("shared title");
        expect("normalized_title" in comic).toBe(false);
      }
    } finally {
      runtime.close();
    }
  });

  it("scopes idempotency conflicts by operation_name plus idempotency_key", async () => {
    const runtime = await createTestRuntime();

    try {
      const now = new Date("2026-05-05T00:00:00.000Z");
      const createKey = expectIdempotencyKey("shared-key");
      const createHash = expectInputHash("hash-create");
      const otherHash = expectInputHash("hash-other");

      const first = await runtime.repositories.operationIdempotency.createInProgress({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: createKey,
        inputHash: createHash,
        createdAt: now,
        updatedAt: now,
      });
      expect(first.ok).toBe(true);

      const second = await runtime.repositories.operationIdempotency.createInProgress({
        operationName: "ImportComicSnapshot",
        idempotencyKey: createKey,
        inputHash: otherHash,
        createdAt: now,
        updatedAt: now,
      });

      expect(second.ok).toBe(true);
    } finally {
      runtime.close();
    }
  });
});
