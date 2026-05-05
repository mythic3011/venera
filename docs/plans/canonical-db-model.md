# Canonical Database Model Design

## Purpose

This document defines the canonical database schema for the restructured Venera
architecture. The schema establishes clear boundaries between:

- **DB authority**: columns, foreign keys, constraints
- **Runtime authority**: typed domain objects
- **Migration policy**: legacy data import strategy
- **Write gates**: validation before persistence

Status: **Architecture Phase** (schema-only, no UI changes)

## Current State (Reference)

The `UnifiedComicsStore` (Drift-based) currently manages:

### Source Platform Layer

```
source_platforms (canonical key, display_name, kind: local|remote|virtual)
source_platform_aliases (legacy_key, legacy_type, source_context)
```

### Comic Domain Layer

```
comics (id TEXT PRIMARY KEY, title, normalized_title)
comic_titles (comic_id, title_type: primary|alias|original|translated|...)
comic_source_links (comic_id, source_platform_id, source_comic_id, link_status)
```

### Storage Layer

```
local_library_items (comic_id, storage_type, local_root_path)
```

### Reader Session Layer

```
reader_sessions (id, comic_id, active_tab_id)
reader_tabs (session_id, comic_id, chapter_id, page_index, source_ref_json)
```

Issues in current design:

- `source_ref_json` is schema-free, stores encoded identity in JSON
- `page_order_id` lacks clear ownership (canonical source?)
- No explicit `chapters` table (chapter identity merged into `reader_tabs`)
- `local_library_items` storage_type is not normalized
- Missing explicit `pages` table with page-level identity

## Canonical Design (Phase 1)

### Core Principle

```
String refs are projections, not authority.
```

Identity must be:

1. **Typed** - runtime objects, not parsed strings
2. **Persisted** - stored as columns, not JSON
3. **Bounded** - clear ownership per feature
4. **Queryable** - support efficient reads via SQL

### Table Hierarchy

#### 1. Source Platforms (Authority)

```sql
CREATE TABLE source_platforms (
  id TEXT PRIMARY KEY,
  canonical_key TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('local', 'remote', 'virtual')),
  is_enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

**Responsibility**: Define what source platforms exist and how to load them.

**Invariants**:
- `canonical_key` is stable across app versions
- `kind` determines runtime behavior
- One entry per unique platform

---

#### 2. Comics (Domain Authority)

```sql
CREATE TABLE comics (
  id TEXT PRIMARY KEY,
  normalized_title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE comic_metadata (
  comic_id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL,
  cover_local_path TEXT,
  description TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE
);
```

**Rationale**: Separate identity (`comics`) from mutable metadata.

**Invariants**:
- One comic per `id`
- `normalized_title` is used for search/dedup only
- Metadata can be updated without affecting identity

---

#### 3. Chapters (Ordered Identity)

```sql
CREATE TABLE chapters (
  id TEXT PRIMARY KEY,
  comic_id TEXT NOT NULL,
  chapter_number REAL NOT NULL,
  title TEXT,
  source_platform_id TEXT,
  source_chapter_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
  FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL,
  UNIQUE(comic_id, source_platform_id, source_chapter_id),
  UNIQUE(comic_id, chapter_number)
);

CREATE INDEX idx_chapters_comic_number
  ON chapters(comic_id, chapter_number DESC);
```

**Rationale**: Chapters are ordered within a comic and may link to remote sources.

**Invariants**:
- `chapter_number` defines canonical order (not source order)
- One chapter per `id`
- Can have `NULL source_chapter_id` for local-only chapters
- `chapter_number` is unique per comic

---

#### 4. Pages (Ordered within Chapter)

```sql
CREATE TABLE pages (
  id TEXT PRIMARY KEY,
  chapter_id TEXT NOT NULL,
  page_index INTEGER NOT NULL,
  source_platform_id TEXT,
  source_page_id TEXT,
  local_cache_path TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE,
  FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL,
  UNIQUE(chapter_id, page_index),
  UNIQUE(chapter_id, source_platform_id, source_page_id)
);

CREATE INDEX idx_pages_chapter_index
  ON pages(chapter_id, page_index ASC);
```

**Invariants**:
- `page_index` is 0-based, defines canonical order
- One page per `id`
- `source_page_id` links to remote page (can be NULL)
- `local_cache_path` is optional cache location

---

#### 5. Page Orders (Reordering Policy)

```sql
CREATE TABLE page_orders (
  id TEXT PRIMARY KEY,
  chapter_id TEXT NOT NULL,
  page_count INTEGER NOT NULL,
  order_type TEXT NOT NULL CHECK (order_type IN ('source', 'user_override', 'import_detected')),
  user_pages_order TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE
);
```

**Rationale**: Track page reordering separately from page identity.

**Invariants**:
- One active order per chapter
- `user_pages_order` is delimited list of page IDs (or NULL if using source order)
- `order_type` documents the source of reordering

---

#### 6. Reader Sessions (Canonical Runtime State)

```sql
CREATE TABLE reader_sessions (
  id TEXT PRIMARY KEY,
  comic_id TEXT NOT NULL,
  chapter_id TEXT NOT NULL,
  page_index INTEGER NOT NULL,
  active_tab_position INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
  FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE RESTRICT
);

CREATE INDEX idx_reader_sessions_comic_updated
  ON reader_sessions(comic_id, updated_at DESC);
```

**Rationale**: Reader session state is now normalized columns, not JSON.

**Change from current**: No `source_ref_json`, no separate `reader_tabs` table.

**Invariants**:
- One session per comic
- `chapter_id` and `page_index` are canonical position
- `active_tab_position` reserved for future multi-tab support

---

#### 7. Local Library Items (Storage Authority)

```sql
CREATE TABLE local_library_items (
  id TEXT PRIMARY KEY,
  comic_id TEXT NOT NULL,
  storage_type TEXT NOT NULL CHECK (storage_type IN ('downloaded', 'user_imported', 'cache')),
  local_root_path TEXT NOT NULL UNIQUE,
  content_fingerprint TEXT,
  file_count INTEGER NOT NULL DEFAULT 0,
  total_bytes INTEGER NOT NULL DEFAULT 0,
  imported_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE
);
```

**Invariants**:
- `local_root_path` is unique (one storage item per path)
- `storage_type` determines how the item is managed
- `content_fingerprint` aids dedup on re-import

---

### Deferred (Phase 2+)

The following tables are deferred until reader/runtime contracts stabilize:

- `favorites` (depends on comic identity)
- `history_events` (depends on reader session identity)
- `user_tags` (depends on comic identity)
- `remote_match_candidates` (candidate linking UI)

---

## Repository Boundaries

### Comic Repository

**Responsibility**: Load, create, update comics and their metadata.

```dart
class ComicRepository {
  Future<Comic> getComicById(String comicId);
  Future<List<Comic>> listComics();
  Future<String> createComic(ComicCreateRequest req);
  Future<void> updateComicMetadata(String comicId, ComicMetadataUpdate req);
}
```

### Chapter Repository

**Responsibility**: Chapter ordering and sync.

```dart
class ChapterRepository {
  Future<List<Chapter>> listChapters(String comicId, {SortOrder order});
  Future<Chapter> getChapter(String chapterId);
  Future<String> createChapter(String comicId, ChapterCreateRequest req);
  Future<void> updateChapterOrder(String comicId, List<String> chapterIds);
}
```

### Page Repository

**Responsibility**: Page identity and ordering within a chapter.

```dart
class PageRepository {
  Future<List<Page>> listPages(String chapterId);
  Future<Page> getPage(String pageId);
  Future<void> updatePageIndex(String pageId, int newIndex);
  Future<void> overridePageOrder(String chapterId, List<String> pageIds);
}
```

### Reader Session Repository

**Responsibility**: Canonical reader session state.

```dart
class ReaderSessionRepository {
  Future<ReaderSession?> getSessionForComic(String comicId);
  Future<void> updateReaderPosition(
    String comicId,
    String chapterId,
    int pageIndex,
  );
  Future<void> clearReaderSession(String comicId);
}
```

---

## Migration from Legacy

### Import Sequence

1. **Identify source platform** (legacy ID → canonical key)
2. **Create comic entry** (legacy comic ID → new `comic.id`)
3. **Create chapters** with `chapter_number` from import order
4. **Create pages** with `page_index` from import order
5. **Create reader session** if resuming
6. **Skip/archive** legacy JSON files

### Safety Checks

- Validate chapter ordering before creating new chapters
- Detect duplicate comics (by normalized title + source platform)
- Preserve local library paths during local import

---

## Validation Gates

Before any write:

1. **Foreign key check**: referenced entities exist
2. **Order invariant check**: chapter_number/page_index are unique and sensible
3. **Identity check**: string IDs match expected format
4. **Source link check**: if linking to remote, platform must exist

---

## Next Steps

1. **Implement repository layer** (no UI changes)
2. **Write migration layer** (legacy → canonical)
3. **Add validation gates** (before all writes)
4. **Define runtime contracts** (`ReaderOpenTarget`, etc.)
5. **Start reader shell** (after contracts stable)
