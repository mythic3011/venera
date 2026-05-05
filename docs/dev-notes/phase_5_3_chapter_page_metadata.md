# Phase 5.3: Chapter/Page Metadata Writes

Date: 2026-05-05

## Scope

Route `upsertChapter` and `upsertPage` through `AppDbHelper` (via `runCanonicalWrite`).

### IN

- `upsertChapter`
- `upsertPage`

### OUT (do NOT touch)

- `deleteChaptersForComic` / `deletePagesForChapter` (Phase 5.1 completed)
- `comic metadata/library item` lanes
- `import/export/rebuild` lanes
- `cache/app settings/search history/implicit data/history event`
- `reader session/tab` (Phase 5.2 completed)
- `schema/migration/setup/read-only paths`

## Implementation

### 1. Wrap upsertChapter

Current:

```dart
Future<void> upsertChapter(ChapterRecord record) {
  return customStatement(
    '''
    INSERT INTO chapters (
      id,
      comic_id,
      chapter_no,
      title,
      normalized_title,
      created_at,
      updated_at
    )
    VALUES (?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
    ON CONFLICT(id) DO UPDATE SET
      comic_id = excluded.comic_id,
      chapter_no = excluded.chapter_no,
      title = excluded.title,
      normalized_title = excluded.normalized_title,
      updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
    ''',
    [
      record.id,
      record.comicId,
      record.chapterNo,
      record.title,
      record.normalizedTitle,
      record.createdAt,
      record.updatedAt,
    ],
  );
}
```

Wrap with:

```dart
Future<void> upsertChapter(ChapterRecord record) {
  return runCanonicalWrite<void>(
    domain: 'chapter_metadata',
    operation: 'upsert_chapter',
    action: () => customStatement(
      '''
      INSERT INTO chapters (
        id,
        comic_id,
        chapter_no,
        title,
        normalized_title,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        comic_id = excluded.comic_id,
        chapter_no = excluded.chapter_no,
        title = excluded.title,
        normalized_title = excluded.normalized_title,
        updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
      ''',
      [
        record.id,
        record.comicId,
        record.chapterNo,
        record.title,
        record.normalizedTitle,
        record.createdAt,
        record.updatedAt,
      ],
    ),
  );
}
```

### 2. Wrap upsertPage

Current:

```dart
Future<void> upsertPage(PageRecord record) {
  return customStatement(
    '''
    INSERT INTO pages (
      id,
      chapter_id,
      page_index,
      local_path,
      content_hash,
      width,
      height,
      bytes,
      created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
    ON CONFLICT(id) DO UPDATE SET
      chapter_id = excluded.chapter_id,
      page_index = excluded.page_index,
      local_path = excluded.local_path,
      content_hash = excluded.content_hash,
      width = excluded.width,
      height = excluded.height,
      bytes = excluded.bytes;
    ''',
    [
      record.id,
      record.chapterId,
      record.pageIndex,
      record.localPath,
      record.contentHash,
      record.width,
      record.height,
      record.bytes,
      record.createdAt,
    ],
  );
}
```

Wrap with:

```dart
Future<void> upsertPage(PageRecord record) {
  return runCanonicalWrite<void>(
    domain: 'chapter_metadata',
    operation: 'upsert_page',
    action: () => customStatement(
      '''
      INSERT INTO pages (
        id,
        chapter_id,
        page_index,
        local_path,
        content_hash,
        width,
        height,
        bytes,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        chapter_id = excluded.chapter_id,
        page_index = excluded.page_index,
        local_path = excluded.local_path,
        content_hash = excluded.content_hash,
        width = excluded.width,
        height = excluded.height,
        bytes = excluded.bytes;
      ''',
      [
        record.id,
        record.chapterId,
        record.pageIndex,
        record.localPath,
        record.contentHash,
        record.width,
        record.height,
        record.bytes,
        record.createdAt,
      ],
    ),
  );
}
```

## Acceptance Criteria

- ✅ `upsertChapter` routed via `runCanonicalWrite`
- ✅ `upsertPage` routed via `runCanonicalWrite`
- ✅ SQL text and semantics unchanged
- ✅ Chapter/page rebuild idempotency tests pass
- ✅ Ordering correctness tests pass
- ✅ grep guard updated
- ✅ audit doc moves chapter/page lane from remaining debt to routed/completed

## Warnings

- **Do NOT** touch `deleteChaptersForComic` / `deletePagesForChapter` (Phase 5.1 completed)
- **Do NOT** modify ordering SQL in `upsertPage`; only change routing
- **Do NOT** touch `page_order` or reader page list coupling

## Verification

After implementation:

1. Run chapter/page rebuild idempotency tests
2. Run ordering correctness tests
3. Update audit doc to reflect completion
4. Update grep guard to include new `runCanonicalWrite` wrappers
