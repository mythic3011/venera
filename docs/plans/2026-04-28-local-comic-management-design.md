# Local Comic Management UI Design

> Legacy note: this document is UI history from the local-only manager
> direction. Under Venera Next Core Rewrite, local comic management must be a
> sub-surface of the unified `comicId` detail/domain model rather than a
> separate authority.

## Goal

Improve local comic and chapter management so large imported comics can be edited from one predictable surface, with complete translation coverage for the new UI.

## Current Problems

- Local chapter tools are split across several dialogs: manage chapters, reorder pages, and set cover.
- `Manage Chapters` writes destructive changes immediately, including delete and reorder.
- New UI strings use `.tl`, but many keys are missing from `assets/translation.json`.
- zh-HK currently has no reliable translation fallback, so it can fall back to raw English.

## Chosen Approach

Use one sidebar-based local comic manager. This matches the app's existing `showSideBar` pattern and scales better than a fixed dialog on desktop and mobile.

The manager contains four tabs:

- `Chapters`: list, search, rename, delete, reorder.
- `Pages`: select chapter and reorder pages.
- `Cover`: select chapter/page and save a cover.
- `Merge`: select other local comics and add them as chapters.

## i18n Strategy

Keep the codebase's existing English-string key style for now. Add every new local management string to `assets/translation.json`.

Update translation fallback rules so zh-HK can fall back to zh-TW before returning the English key. This avoids duplicating the full zh-TW table while still allowing zh-HK-specific overrides later.

Fallback order:

- `zh_HK` -> `zh_TW` -> `zh_CN` -> original string
- `zh_TW` -> `zh_CN` -> original string
- `zh_CN` -> original string
- `en_*` -> original string

## Safety Rules

- Delete chapter must show confirmation with the chapter title.
- Page reorder remains draft until the user presses `Save`.
- Merge must show source deletion as an explicit checkbox.
- Long operations must show loading state or progress message.

## Acceptance Criteria

- Local comic context menu opens a unified manager sidebar.
- Existing actions for reorder pages, set cover, and manage chapters remain usable or route to the unified manager.
- Local comics with chapters can be searched and reordered.
- New strings are translated in zh-CN and zh-TW, with zh-HK fallback to zh-TW.
- `flutter analyze` has no new errors.
- `flutter test` passes.
