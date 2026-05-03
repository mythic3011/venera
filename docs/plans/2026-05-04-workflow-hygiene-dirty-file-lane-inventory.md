# Workflow Hygiene Dirty File Lane Inventory

Date: 2026-05-04
Scope: inventory only
Behavior change: none

## Purpose

Inventory current dirty files by likely lane ownership to reduce cross-lane bleed.

## Snapshot (`git status --short`)

### Lane: Favorites/Detail Authority Cleanup

- `lib/pages/comic_details_page/actions.dart`
- `lib/pages/comic_details_page/comic_page.dart`
- `lib/pages/comic_details_page/favorite.dart`
- `lib/pages/favorites/local_favorites_page.dart`
- `lib/pages/favorites/side_bar.dart`
- `lib/pages/comic_source_page.dart`
- `lib/foundation/favorite_runtime_authority.dart` (untracked)
- `docs/plans/2026-05-04-favorite-authority-inventory-1.md` (untracked)
- `docs/plans/2026-05-04-favorite-authority-inventory-2.md` (untracked)

### Lane: Follow-Updates/Home Surfaces

- `lib/foundation/follow_updates.dart`
- `lib/pages/follow_updates_page.dart`
- `lib/pages/home_page.dart`
- `lib/pages/home_page_legacy_sections.dart`

### Lane: Diagnostics Test Surface

- `test/foundation/debug_log_exporter_test.dart`

## Notes

- This is an ownership/coordination inventory only; no correctness judgment.
- Lane names are operational buckets for staging/review, not architecture authority.
- Re-run inventory before each commit if additional files become dirty.
