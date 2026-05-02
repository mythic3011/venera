# M25.1 Disposable Cache Index Replacement

## Goal

- Replace standalone `cache.db` sidecar URL index.
- Move cache metadata into canonical app DB.
- Treat old `cache.db` as disposable and non-authoritative.
- Keep actual cached image bytes on filesystem.

## Scope

- cache metadata only
- no cookie migration
- no history migration
- no settings migration
- no image/blob storage in DB
- no ReaderNext route semantics change
- no raw URL cache-key preservation
- no legacy `cache.db` migration by default

## Hard Rules

1. Legacy `cache.db` is disposable.
2. Missing legacy `cache.db` must not crash startup.
3. Corrupt legacy `cache.db` must not crash startup.
4. Legacy `cache.db` must not be migrated by default in M25.1.
5. Cache miss must recover by regenerating/downloading cache content.
6. New cache key must not store raw URL as primary key.
7. New cache metadata must store hash-derived source identity, not raw URL identity.
8. Raw URLs must not appear in diagnostics by default.
9. Cache image bytes remain filesystem files.
10. Export app data must exclude cache metadata by default.
11. Cleanup must delete only cache metadata and cache files.
12. Cleanup must not touch history/favorites/settings/cookies.
13. Cache metadata corruption must not block app startup.
14. Cache metadata must not become route or identity authority.

## Data Model Direction

Legacy cache index behavior is classified as runtime-disposable sidecar metadata.
It must not be treated as authoritative domain data.

The old `cache.db` schema is a URL-to-file sidecar index:

```sql
cache(
  key TEXT PRIMARY KEY,
  dir TEXT,
  name TEXT,
  expires INTEGER,
  type TEXT
)
```

That legacy table must not be preserved as the canonical cache model.
M25.1 replaces it with explicit cache metadata in the canonical app DB.

Proposed canonical metadata table:

```sql
CREATE TABLE cache_entries (
  cache_key TEXT PRIMARY KEY NOT NULL,
  namespace TEXT NOT NULL,
  source_key_hash TEXT NOT NULL,
  source_platform_id TEXT,
  owner_ref TEXT,
  storage_dir TEXT NOT NULL,
  file_name TEXT NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  content_type TEXT,
  size_bytes INTEGER,
  created_at_ms INTEGER NOT NULL,
  last_accessed_at_ms INTEGER,
  UNIQUE(storage_dir, file_name),
  CHECK (namespace IN (
    'cover_image',
    'reader_page_image',
    'thumbnail',
    'source_asset',
    'other'
  )),
  CHECK (expires_at_ms > 0),
  CHECK (created_at_ms > 0)
);
```

Field semantics:

| Field                 | Meaning                                                                        |
| --------------------- | ------------------------------------------------------------------------------ |
| `cache_key`           | stable hash-derived cache entry id                                             |
| `namespace`           | cache class such as cover image, reader page image, thumbnail, or source asset |
| `source_key_hash`     | hash of the normalized source material, such as URL plus owner context         |
| `source_platform_id`  | optional source platform identifier, such as `copy_manga`                      |
| `owner_ref`           | optional owner reference, such as comic slug or canonical owner id             |
| `storage_dir`         | filesystem cache bucket or directory                                           |
| `file_name`           | filesystem cache filename                                                      |
| `expires_at_ms`       | expiry timestamp in milliseconds                                               |
| `content_type`        | optional content type                                                          |
| `size_bytes`          | optional file size for cleanup accounting                                      |
| `created_at_ms`       | creation timestamp in milliseconds                                             |
| `last_accessed_at_ms` | optional access timestamp for LRU cleanup                                      |

Key derivation direction:

- Do not use raw URL as primary key.
- Derive `cache_key` from a stable hash.
- Derive `source_key_hash` from normalized source material.
- Prefer a stable hash input such as:
  `sha256(namespace + "\\0" + normalized_url + "\\0" + sourceKey + "\\0" + ownerRef)`.
- Raw URL may be optional/redacted debug material only, not a default dump surface.
- Diagnostics must expose hash/redacted values only by default.

Namespace direction:

- `cover_image`
- `reader_page_image`
- `thumbnail`
- `source_asset`
- `other`

Do not add free-form namespaces in M25.1 unless the schema/test contract is updated.

## Legacy Cache DB Policy

M25.1 does not migrate old `cache.db` by default.

Expected behavior:

- missing old `cache.db` is ignored
- corrupt old `cache.db` is ignored
- old raw URL keys are not copied into `cache_entries`
- cache lookup can miss and regenerate metadata
- old cache files may be lazily cleaned by normal cache cleanup
- old `cache.db` may be removed only by explicit cache cleanup, not startup migration

## Acceptance Tests

```dart
test('missing legacy cache db does not crash startup', () async {});

test('corrupt legacy cache db does not crash startup', () async {});

test('legacy cache db is ignored instead of migrated', () async {
  // seed old cache.db with raw URL key
  // initialize new cache metadata store
  // expect no cache_entries copied from old DB
  // expect cache miss path works
});

test('legacy cache db is not required for cache lookup', () async {
  // no cache.db
  // request cover image
  // expect cache miss and regenerated metadata
});

test('new cache entry does not use raw url as primary key', () async {
  // insert URL cache entry
  // expect cache_key is hash-like
  // expect raw URL not used as PK
});

test('new cache entry stores source hash instead of raw URL identity', () async {
  // insert URL cache entry
  // expect source_key_hash is hash-like
  // expect raw URL absent from canonical metadata fields
});

test('two cache entries cannot point to the same storage file', () async {
  // insert two different cache_key values with the same storage_dir/file_name
  // expect constraint failure or typed conflict
});

test('cache diagnostics do not expose raw url', () async {
  // cache lookup by URL
  // expect diagnostics include hash/redacted material only
  // expect raw URL absent
});

test('cache cleanup removes only cache files and cache metadata', () async {
  // seed history/favorites/settings/cookies
  // cleanup cache
  // expect user data unchanged
});

```

## Implementation Order

- M25.1-A: add canonical app DB `cache_entries` table
- M25.1-B: write new `CacheMetadataStore` adapter
- M25.1-C: switch `CacheManager` metadata read/write to new adapter
- M25.1-D: ignore old `cache.db` by default
- M25.1-E: make old cache miss regenerate metadata in `cache_entries`
- M25.1-F: exclude cache metadata from export/default backup
- M25.1-G: optionally remove old `cache.db` via explicit cache cleanup only

## Verification Commands

```bash
rg -n "cache\.db|CacheManager|cache_entries|cache_key|remote_url_hash|source_key_hash" lib test
flutter test test/foundation/cache_metadata_store_test.dart
flutter test test/utils/data_export_cache_exclusion_test.dart
dart analyze lib/foundation lib/utils test/foundation/cache_metadata_store_test.dart test/utils/data_export_cache_exclusion_test.dart
git diff --check
```

## Safety Boundary

- This milestone is cache metadata replacement only.
- No changes to cookie security lane (M25.3), history migration lane, settings migration lane, or ReaderNext routing authority.
- Cache misses are expected and acceptable recovery behavior.
- Cache metadata is not user data.
- Cache metadata is not route authority.
- Cache metadata is excluded from default export/backup.
- Cache image/blob bytes remain filesystem files and must not be stored in canonical DB.
