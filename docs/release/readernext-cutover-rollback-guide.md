# ReaderNext Cutover Rollback Guide

Status: release/operator guide  
Scope: ReaderNext production cutover for history, favorites, and downloads

## Summary

ReaderNext cutover is guarded by independent feature flags for each supported entrypoint:

- history
- favorites
- downloads

Each entrypoint can be rolled back independently by disabling its own flag.

Rollback changes route selection only. It does not mutate identity data, readiness artifacts, SourceRef snapshots, importer state, backfill state, or persisted rows.

## Supported Entrypoints

| Entrypoint | Feature Flag                    | ReaderNext Route Authority                                | Rollback Behavior                               |
| ---------- | ------------------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| history    | `reader_next_history_enabled`   | M14 readiness + current-row validation                    | route history opens to explicit legacy reader   |
| favorites  | `reader_next_favorites_enabled` | M14 readiness + M16 folder-scoped favorites preflight     | route favorites opens to explicit legacy reader |
| downloads  | `reader_next_downloads_enabled` | M14 readiness + M17 explicit-identity downloads preflight | route downloads opens to explicit legacy reader |

## Rollback Procedures

### Roll back history

Set:

```text
reader_next_history_enabled=false
```

Expected result:

- History opens use the explicit legacy reader route.
- ReaderNext approved executor is not called for history opens.
- M14 readiness artifacts are unchanged.
- SourceRef snapshots are unchanged.
- History rows are unchanged.
- Favorites and downloads behavior are unchanged.

### Roll back favorites

Set:

```text
reader_next_favorites_enabled=false
```

Expected result:

- Favorites opens use the explicit legacy reader route.
- ReaderNext approved executor is not called for favorites opens.
- M14 readiness artifacts are unchanged.
- M16 favorites preflight state is unchanged.
- SourceRef snapshots are unchanged.
- Favorites rows are unchanged.
- History and downloads behavior are unchanged.

### Roll back downloads

Set:

```text
reader_next_downloads_enabled=false
```

Expected result:

- Downloads opens use the explicit legacy reader route.
- ReaderNext approved executor is not called for downloads opens.
- M14 readiness artifacts are unchanged.
- M17 downloads preflight state is unchanged.
- SourceRef snapshots are unchanged.
- Downloads rows are unchanged.
- History and favorites behavior are unchanged.

## Important Behavior Notes

### Feature flags are route-selection controls only

Feature flags decide whether an entrypoint attempts the ReaderNext path or the explicit legacy path.

Feature flags must not:

- bypass SourceRef validation
- bypass M14 readiness checks
- bypass M16 favorites folder-scoped identity checks
- bypass M17 downloads explicit-identity checks
- convert a blocked ReaderNext decision into a legacy fallback

### Blocked ReaderNext decisions are terminal

A blocked ReaderNext decision is intentional fail-closed behavior.

Blocked does not mean the app crashed. It means the row did not pass the required identity, readiness, or validation checks.

When an entrypoint flag is enabled:

- eligible rows open through the approved ReaderNext executor
- blocked rows render or emit a blocked state
- blocked rows do not fall back to legacy
- blocked rows do not call the approved ReaderNext executor

To route future opens through legacy, disable the relevant feature flag.

## Diagnostics and Redaction

ReaderNext cutover diagnostics are redacted by default.

Diagnostics may include:

- entrypoint
- route decision
- validation code
- blocked reason
- schema version
- redacted or hashed record id
- redacted or hashed candidate id
- redacted or hashed identity fingerprint

Diagnostics must not expose:

- raw canonical IDs
- raw upstream IDs
- raw chapter IDs
- local paths
- cache paths
- archive paths
- filenames
- full URLs
- cookies
- request headers
- bearer tokens

## Release Gate

Before release, run the frozen M20 regression pack.

Reference:

- `docs/plans/2026-05-02-m20-readernext-cutover-freeze-regression-pack.md`

Required commands:

```bash
flutter test test/features/reader_next/presentation/*navigation_executor*
flutter test test/pages/history_page_m15_test.dart
flutter test test/pages/favorites_page_m16_2_test.dart
flutter test test/pages/downloads_page_m17_4_test.dart
flutter test test/pages/m19_production_cutover_final_smoke_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/presentation lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages
git diff --check
```

Expected release-gate result:

- all tests pass
- `dart analyze` reports no issues
- `git diff --check` has no output
- authority guards remain clean

## Release Checklist

Before enabling ReaderNext in release:

- [ ] M20 regression pack passed.
- [ ] History rollback flag is documented.
- [ ] Favorites rollback flag is documented.
- [ ] Downloads rollback flag is documented.
- [ ] Operators understand blocked means fail-closed, not crash.
- [ ] Operators understand blocked rows do not fall back to legacy.
- [ ] Diagnostics redaction expectations are documented.
- [ ] No new entrypoint, fallback behavior, or identity semantics change was introduced without a new ADR.

## Future Change Policy

After this cutover lane is frozen, future changes are bugfix-only unless a new ADR opens a new lane.

Allowed without new ADR:

- fix incorrect blocked decisions
- fix incorrect flag-off route selection
- fix diagnostic redaction bugs
- fix authority guard false positives without weakening the protected invariant
- improve internal code clarity without moving authority into pages

Requires new ADR:

- new ReaderNext entrypoint
- new fallback path
- page-level ReaderNextOpenRequest construction
- page-level SourceRef construction
- identity derivation from local path, cache path, archive path, filename, title, URL, or canonical ID string split
- changing M14 readiness semantics
- changing M16 favorites folder-scoped identity semantics
- changing M17 downloads explicit-identity semantics
- using raw M14/M16/M17 artifacts as page-level route authority
