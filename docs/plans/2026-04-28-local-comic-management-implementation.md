# Local Comic Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

> Legacy note: this document is now appendix-only UI history. Under Venera Next
> Core Rewrite, `LocalManager` and local-only comic flows are not long-term
> domain authorities. Any surviving ideas here must be re-routed through the
> canonical `comicId` model and `ComicDetailPage(comicId)`.

## Status

- Local Comic Manager UI work reflects an older local-only direction.
- Remaining useful content here is transitional UI cutover detail, not active
  domain architecture.
- Translation fallback is moved to a separate future lane unless separately approved.

**Goal:** Replace fragmented local comic maintenance dialogs with one translated sidebar manager.

**Architecture:** Historical direction only. Do not keep backend operations in
`LocalManager` as long-term authority. If this UI survives, it must become a
temporary cutover surface over the canonical comic domain.

**Tech Stack:** Flutter/Dart, existing Venera component library, JSON translation table.

---

### Task 1: Translation Fallbacks (Deferred Lane)

**Files:**
- Modify: `lib/utils/translations.dart`
- Modify: `assets/translation.json`

**Steps:**
- Defer from manager UI PR scope.
- Track as separate future lane with explicit approval.
- Do not bundle translation fallback into Local Comic Manager UI implementation by default.

### Task 2: Unified Manager Entry Point

**Files:**
- Modify: `lib/pages/local_comics_page.dart`

**Steps:**
- Replace `showManageChaptersDialog` internals with `showSideBar`.
- Add a `LocalComicManagePanel` stateful widget.
- Keep existing context-menu entries, but route chapter/page/cover actions into the new panel with an initial tab.
- Run targeted analyze on `local_comics_page.dart`.

### Task 3: Chapters Tab

**Files:**
- Modify: `lib/pages/local_comics_page.dart`

**Steps:**
- Implement search and chapter count header.
- Show row actions for rename/delete and a drag handle for reorder.
- Confirm delete before calling `LocalManager().deleteComicChapters`.
- Refresh local comic state after each operation.

### Task 4: Pages and Cover Tabs

**Files:**
- Modify: `lib/pages/local_comics_page.dart`

**Steps:**
- Move page reorder UI into the manager.
- Move cover selection UI into the manager.
- Keep standalone wrappers only as temporary cutover entry points with explicit
  deletion criteria once unified detail routing replaces them.
- Run targeted analyze.

### Task 5: Merge Tab

**Files:**
- Modify: `lib/pages/local_comics_page.dart`

**Steps:**
- Move add-comics-as-chapters UI into the manager.
- Show selected count and delete-source checkbox.
- Add loading state while merge runs.
- Refresh chapters after merge.

### Task 6: Verification

**Files:**
- Test existing suite.

**Steps:**
- Run `flutter analyze`.
- Run `flutter test`.
- Manually inspect source for untranslated new strings.
