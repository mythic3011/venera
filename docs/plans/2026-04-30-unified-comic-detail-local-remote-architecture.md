# Unified Comic Detail + Local/Remote Library Architecture

## Status

- Approved target architecture for Venera local/remote comic management.
- This supersedes the older local-only management direction in
  `docs/plans/2026-04-28-local-comic-management-design.md` whenever the two
  conflict.
- The old local manager work remains useful as a UI sub-surface, but it is no
  longer the domain boundary.

## Decision

Do **Unified Comic Detail + Unified Local Library Management**.

Do not treat local comics as thin file items with a separate detail UX.
Do not treat remote comics as a separate UI object.

Use one domain identity:

- `ComicDetailPage(comicId)`

`local`, `remote`, `downloaded`, `imported`, `matched`, and `unavailable` are
state/provenance around the comic. They are not separate detail-page products.

## Problem

Current behavior is split incorrectly:

- Remote comic has full detail UX, source metadata, tags, chapters, reader
  session behavior.
- Local comic is treated like a weak file/folder item with partial metadata and
  weak management.

This is the wrong abstraction. A local comic is still a comic. A remote comic
is still a comic. Storage, provenance, and reader state must be modeled
separately from the unified comic identity.

## Core Rules

Common identity:

- `comics`

Storage and provenance:

- `local_library_items`
- `comic_sources`
- `remote_match_candidates`

Metadata:

- `tags` / `comic_tags` for user-owned tags
- `source_tags` / `comic_source_tags` for source-provided tags
- `comic_titles` for alias/original/import/source titles

Reading structure and overlays:

- `chapters`
- `pages`
- `page_orders`
- `page_order_items`

Reader state:

- `reader_sessions`
- `reader_tabs`

Hard rules:

- Local comics can have full functionality.
- Local metadata must not overwrite source provenance.
- Source metadata can enrich a comic.
- Source metadata must not silently overwrite user-owned local metadata.
- Pending remote matches are not source citation.
- Page reorder is an overlay and must not mutate `pages.page_index`.
- Widgets stay render/composition only.
- Repositories/services own source resolution, local import, page-order
  validation, and session mutation.

## Unified UX

### Local Library

Upgrade local library into a real manager:

- Search
- Filter
- Sort
- Import
- Source/provenance badges
- User tags
- Chapter/page counts
- Last read
- Imported/downloaded date
- Status badges

Target sort/filter surface:

- Title
- Last read
- Imported date
- Updated date
- Source/platform
- Tag
- Chapter count
- Page count
- File size
- Matched/unmatched state
- Favorite
- Has custom page order

### Unified Detail Page

Replace separate local/remote detail assumptions with:

- `ComicDetailPage(comicId)`

Capability-gated tabs/actions:

- Chapters
- Tags
- Source
- Sessions
- Page Order
- Related Remote

Library state examples:

- `localOnly`
- `remoteOnly`
- `localWithRemoteSource`
- `downloaded`
- `unavailable`

## Database Direction

Use SQLite as the local complex-data authority. Existing Venera already uses
`sqlite3` and Drift-backed stores, so the new schema should stay SQLite-first.

Mandatory DB rules:

- Enable `PRAGMA foreign_keys = ON`
- Use `UNIQUE` and partial unique indexes where ownership rules require it
- Keep source citation, user tags, and page-order overlays in separate tables

Foundation tables:

- `source_platforms`
- `source_platform_aliases`
- `comics`
- `comic_titles`
- `comic_sources`
- `local_library_items`
- `import_batches`
- `tags`
- `comic_tags`
- `source_tags`
- `comic_source_tags`
- `chapters`
- `pages`
- `chapter_sources`
- `page_sources`
- `chapter_collections`
- `chapter_collection_items`
- `page_orders`
- `page_order_items`
- `reader_sessions`
- `reader_tabs`
- `remote_match_candidates`

## Source Platform Resolver

The current app still carries too many ad hoc source-key mappings. The unified
resolver should become the single authority:

- resolve by canonical key
- resolve by legacy key
- resolve by legacy integer type
- resolve by context (`favorite`, `history`, `reader`, `download`, `import`)

Required outcome:

- favorite/history do not own separate hard-coded source mappings
- source aliases live in one resolver-backed source platform layer

## View Models

Primary detail VM:

- `ComicDetailViewModel`

Required fields:

- `comicId`
- title / cover
- library state
- primary source citation
- user tags
- source tags
- chapters
- reader tabs
- page-order summary
- capability-gated actions

Primary source platform VM:

- `SourcePlatformRef`

Required fields:

- `platformId`
- `canonicalKey`
- `displayName`
- `kind`
- matched alias
- matched alias type
- optional legacy integer type

## Repositories and Services

Required boundaries:

- `ComicDetailRepository`
- `SourcePlatformResolver`
- `LocalImportService`
- `ComicSourceRepository`
- `TagRepository`
- `ChapterRepository`
- `PageOrderRepository`
- `ReaderSessionRepository`
- `RemoteMatchRepository`

Widgets must not directly implement:

- local vs remote resolution
- source/platform mutation
- page reorder validation
- candidate promotion rules

## Main Flows

### Remote Download -> Local

- resolve platform
- upsert comic
- insert source citation
- insert local library item
- generate chapters/pages
- create default page order

### User Local Import

- create comic
- record imported filename/title aliases
- insert local library item
- generate chapters/pages
- create default page order
- no confirmed source unless metadata exists

### Link Local Import -> Remote

- search candidates
- keep candidates pending until explicit acceptance
- promote accepted candidate into `comic_sources`

### Page Reorder

- validate page set
- clone active order
- write user overlay
- switch active order in one transaction

### Open Local Comic in New Tab

- create reader tab
- choose active page order
- choose local/remote load mode through repository logic

## Debug Snapshot

Add a structured reader/debug snapshot rather than relying on generic logs.

Minimum target fields:

- reader session ID
- reader tab ID
- comic ID
- load mode
- platform ID / kind
- local library item ID
- comic source ID
- current chapter/page
- page order ID / type
- page count / visible page count
- controller attached/disposed
- last error type/message

## Migration Slices

### PR1: Database Foundation

- add source platform tables
- add unified comic tables
- enable foreign keys
- add resolver tests for canonical and legacy mapping

### PR2: Unified Comic Detail Repository

- add repository and VM only
- no broad UI rewrite yet

### PR3: Local Import Chapter/Page Generation

- generate chapters/pages
- create source-default page order

### PR4: Source Citation + Source Tags

- add source citation chain tables
- show original source on downloaded local comics

### PR5: User Tags + Local Management

- add user tag model
- keep source tags read-only

### PR6: Page Order Overlay

- implement custom order without mutating source page index

### PR7: Reader Sessions/Tabs

- unify local and remote tab/session behavior

### PR8: Unified Comic Detail UI

- route both local and remote to `ComicDetailPage(comicId)`

### PR9: Remote Match Flow

- pending/accepted/rejected candidate lifecycle

### PR10: Debug Snapshot + Smoke

- prove source resolution, page order, and controller lifecycle

## Immediate Executable Slice

The first repo-grounded implementation slice should be:

1. Add `source_platforms` and `source_platform_aliases`
2. Add a `SourcePlatformResolver`
3. Move favorite/history/source-key compatibility into that resolver
4. Add unified `comics`, `comic_titles`, and `local_library_items`
5. Expose a read-only `ComicDetailRepository.getComicDetail(comicId)` before
   changing the UI

This keeps the first patch narrow, testable, and aligned with the current
SQLite/Drift mix already present in Venera.

## Non-goals

- Do not merge broad black-screen branches.
- Do not add a new state-management framework.
- Do not mutate `pages.page_index` for custom order.
- Do not store provenance only in logs.
- Do not use display name as identity.
- Do not auto-accept remote title matches.
- Do not mix user tags with source tags.
