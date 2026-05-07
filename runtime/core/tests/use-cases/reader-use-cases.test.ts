import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import { createTestRuntime, insertComicFixture, nextId } from "../support/test-runtime.js";

describe("reader use cases", () => {
  it("ResolveReaderTarget owns the exact fallback tuple: requested chapter, saved session, first canonical chapter", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime, {
        chapterIds: [nextId(), nextId()],
      });
      const now = new Date().toISOString();
      const savedPageId = nextId();

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
          ${savedPageId},
          ${fixture.chapterIds[1]},
          1,
          NULL,
          NULL,
          'image/jpeg',
          1000,
          1600,
          'saved-session-page',
          ${now},
          ${now}
        )
      `.execute(runtime.db);

      const savedSessionId = nextId();
      await sql`
        INSERT INTO reader_sessions (
          id,
          comic_id,
          chapter_id,
          page_id,
          page_index,
          created_at,
          updated_at
        )
        VALUES (
          ${savedSessionId},
          ${fixture.comicId},
          ${fixture.chapterIds[1]},
          ${savedPageId},
          1,
          ${now},
          ${now}
        )
      `.execute(runtime.db);

      const requested = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
        pageIndex: 0,
      });
      const saved = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
      });

      await runtime.repositories.readerSessions.clear(fixture.comicId as never);
      const fallback = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
      });

      expect([
        requested.ok
          ? [requested.value.resolutionReason, requested.value.chapterId, requested.value.pageIndex, requested.value.pageId ?? null]
          : requested.error.code,
        saved.ok
          ? [saved.value.resolutionReason, saved.value.chapterId, saved.value.pageIndex, saved.value.pageId ?? null]
          : saved.error.code,
        fallback.ok
          ? [fallback.value.resolutionReason, fallback.value.chapterId, fallback.value.pageIndex, fallback.value.pageId ?? null]
          : fallback.error.code,
      ]).toEqual([
        ["requested_chapter", fixture.chapterIds[0], 0, null],
        ["saved_session", fixture.chapterIds[1], 1, savedPageId],
        ["first_canonical_chapter", fixture.chapterIds[0], 0, null],
      ]);
    } finally {
      runtime.close();
    }
  });

  it("rejects invalid saved-session targets with READER_UNRESOLVED_LOCAL_TARGET, including mismatched page_id and page_index", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime, {
        chapterIds: [nextId(), nextId()],
      });
      const now = new Date().toISOString();

      await sql`
        INSERT INTO reader_sessions (
          id,
          comic_id,
          chapter_id,
          page_id,
          page_index,
          created_at,
          updated_at
        )
        VALUES (
          ${nextId()},
          ${fixture.comicId},
          ${fixture.chapterIds[0]},
          ${fixture.pageIds[2]},
          99,
          ${now},
          ${now}
        )
      `.execute(runtime.db);

      const mismatchedIndex = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
      });

      expect(mismatchedIndex.ok).toBe(false);
      if (!mismatchedIndex.ok) {
        expect(mismatchedIndex.error.code).toBe("READER_UNRESOLVED_LOCAL_TARGET");
      }

      await runtime.repositories.readerSessions.clear(fixture.comicId as never);
      await sql`
        INSERT INTO reader_sessions (
          id,
          comic_id,
          chapter_id,
          page_id,
          page_index,
          created_at,
          updated_at
        )
        VALUES (
          ${nextId()},
          ${fixture.comicId},
          ${fixture.chapterIds[0]},
          ${fixture.pageIds[2]},
          1,
          ${now},
          ${now}
        )
      `.execute(runtime.db);

      const mismatchedPageId = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
      });

      expect(mismatchedPageId.ok).toBe(false);
      if (!mismatchedPageId.ok) {
        expect(mismatchedPageId.error.code).toBe("READER_UNRESOLVED_LOCAL_TARGET");
      }
    } finally {
      runtime.close();
    }
  });

  it("OpenReader fails closed when no canonical chapter exists", async () => {
    const runtime = await createTestRuntime();

    try {
      const now = new Date().toISOString();
      const comicId = nextId();
      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES (${comicId}, 'empty-comic', 'local', ${now}, ${now})
      `.execute(runtime.db);

      const result = await runtime.useCases.openReader.execute({
        comicId: comicId as never,
      });

      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error.code).toBe("READER_UNRESOLVED_LOCAL_TARGET");
      }
    } finally {
      runtime.close();
    }
  });

  it("falls back to Page.pageIndex ASC when no active page order exists", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime, {
        pageCount: 4,
      });
      await sql`
        DELETE FROM page_order_items
        WHERE page_order_id IN (
          SELECT id FROM page_orders WHERE chapter_id = ${fixture.chapterIds[0]}
        )
      `.execute(runtime.db);
      await sql`
        DELETE FROM page_orders
        WHERE chapter_id = ${fixture.chapterIds[0]}
      `.execute(runtime.db);

      const opened = await runtime.useCases.openReader.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
      });

      expect(opened.ok).toBe(true);
      if (opened.ok) {
        expect(opened.value.pages.map((entry) => [entry.page.id, entry.sortIndex])).toEqual([
          [fixture.pageIds[0], 0],
          [fixture.pageIds[1], 1],
          [fixture.pageIds[2], 2],
          [fixture.pageIds[3], 3],
        ]);
      }
    } finally {
      runtime.close();
    }
  });

  it("returns VALIDATION_ERROR when the active page order is incomplete", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime, {
        pageCount: 3,
      });
      await sql`
        DELETE FROM page_order_items
        WHERE page_order_id IN (
          SELECT id FROM page_orders WHERE chapter_id = ${fixture.chapterIds[0]}
        )
          AND page_id = ${fixture.pageIds[2]}
      `.execute(runtime.db);

      const opened = await runtime.useCases.openReader.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
      });

      expect(opened.ok).toBe(false);
      if (!opened.ok) {
        expect(opened.error.code).toBe("VALIDATION_ERROR");
      }
    } finally {
      runtime.close();
    }
  });

  it("UpdateReaderPosition skips unchanged writes", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime);
      const firstWrite = await runtime.useCases.updateReaderPosition.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
        pageId: fixture.pageIds[1] as never,
        pageIndex: 1,
      });
      expect(firstWrite.ok && firstWrite.value.status).toBe("written");

      const secondWrite = await runtime.useCases.updateReaderPosition.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
        pageId: fixture.pageIds[1] as never,
        pageIndex: 1,
      });
      expect(secondWrite.ok && secondWrite.value.status).toBe("skipped_unchanged");
    } finally {
      runtime.close();
    }
  });
});
