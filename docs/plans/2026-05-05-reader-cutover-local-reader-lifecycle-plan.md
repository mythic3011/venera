# Reader Cutover Local Reader Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate false local-reader lifecycle diagnostics and stabilize local reader parent/child ownership so canonical local reader opens can render without misleading `PROVIDER_NOT_SUBSCRIBED`, short-lived dispose, or `linkStatus=missing` signals.

**Architecture:** Treat this as a reader-runtime and diagnostics slice inside the broader reader cutover, not a storage or source-runtime slice. Canonical local routing and local image decode are already proven by evidence, so the implementation should tighten lifecycle ownership between `ReaderWithLoading`, `Reader`, image-provider subscription diagnostics, and `ReaderDebugSnapshot` without reopening local DB cutover or M27 runtime surfaces.

**Tech Stack:** Flutter, Dart, widget tests, structured diagnostics via `AppDiagnostics`, canonical reader/session repositories backed by `UnifiedComicsStore`.

---

## Goal Fit Within Broader Reader Cutover

This plan belongs to the reader runtime + sessions + debug lane of the cutover:

- Canonical local import/detail/open path is already in place.
- Current evidence shows page-list load and image decode succeed for local reader.
- Remaining failures are lifecycle/diagnostic truth-boundary issues inside presentation/runtime surfaces.
- This slice must not modify canonical local DB cutover, legacy local lookup, or M27 source runtime.

## Scope

- Local reader only.
- `ReaderImageProvider` subscription diagnostics truthfulness.
- `ReaderWithLoading` and `Reader` parent/child lifetime ownership when opened from `comic_detail.read`.
- `activeReaderTabId` / `expectedReaderTabId` / `retainedTab` verification for canonical local reader route.
- `ReaderDebugSnapshot` local semantics so local canonical reader does not report `linkStatus=missing` merely because remote source-link fields are null.

## Out Of Scope

- Any M27 source runtime changes.
- Reintroducing legacy local lookup or legacy local DB paths.
- Remote/source reader behavior unless the exact same lifecycle bug is proven by shared code and shared tests.
- Local import crash archaeology based on persisted historical logs.
- Broad `ComicType` identity redesign. That cutover can be tracked separately.

## Hard Constraints

- Do not edit non-reader runtime/storage-adjacent code unless a reader test proves it is the owning surface.
- Do not revert or reshape other agents' work; re-read touched files before patching if the worktree changes.
- Preserve canonical local reader routing and local-detail contracts.
- Fail loudly in diagnostics when local canonical data is genuinely missing; only remove false-negative assumptions.

## Evidence Baseline To Preserve

- `pageCount=41` local page list loads successfully.
- Local image provider loads bytes and `image.decode.success` for pages 1 and 2.
- Current warnings are:
  - `reader.render.provider.notSubscribed`
  - `reader.dispose.short_lived`
  - `reader.parent.unmount.retainedTab`
- Historical `Local comic not found` / import crash logs are not current failures.

## Phase 0: Freeze The Slice Boundary

### Task 0.1: Confirm local-only ownership of the bug

**Files to inspect later:**
- `lib/features/reader/presentation/loading.dart`
- `lib/features/reader/presentation/reader.dart`
- `lib/foundation/image_provider/reader_image.dart`
- `lib/foundation/reader/reader_diagnostics.dart`
- `lib/foundation/reader/reader_debug_snapshot.dart`
- `test/reader/reader_load_visibility_test.dart`
- `test/reader/reader_trace_contract_test.dart`
- `test/reader/reader_debug_snapshot_test.dart`

**Work:**
- Reconfirm from tests/log fixtures that local reader open succeeds through canonical request resolution before changing behavior.
- Document which warnings are false positives versus true lifecycle mismatches.
- Keep this slice out of storage-route, import, and M27 source-runtime lanes.

**Acceptance:**
- The implementation branch has a written note or commit description that this slice is local-reader lifecycle only.
- No non-doc/non-reader files are pulled into the change unless a test proves shared ownership.

## Phase 1: Correct Provider Subscription Truth Boundary

### Task 1.1: Reproduce the false-positive provider warning with a widget-level local-reader path

**Files to modify later:**
- `test/reader/reader_load_visibility_test.dart`
- `test/reader/reader_trace_contract_test.dart`

**Work:**
- Add or tighten a widget test that distinguishes:
  - provider created but never attached to an image stream
  - provider created, image load started, decode/render proceeds
- Use a real local-reader render path rather than only direct factory construction where necessary.

**Acceptance:**
- There is a failing test proving that a local page that actually loads/decode-renders can still emit `reader.render.provider.notSubscribed`.

### Task 1.2: Move `PROVIDER_NOT_SUBSCRIBED` to the real subscription boundary

**Files to modify later:**
- `lib/foundation/image_provider/reader_image.dart`
- `lib/foundation/reader/reader_diagnostics.dart`
- `lib/features/reader/presentation/reader_image_provider_factory.dart`
- `test/reader/reader_load_visibility_test.dart`

**Work:**
- Audit where provider creation, stream subscription start, byte load start, decode success, and render-frame callbacks are recorded.
- Ensure `markImageProviderAwaitingSubscription` is only left pending for cases where no consumer subscribes.
- If needed, add an explicit “subscribed/attached” signal from the owning render path instead of inferring solely from provider construction timing.
- Keep the existing warning for truly orphaned providers.

**Acceptance:**
- Local reader pages that decode/render no longer emit `reader.render.provider.notSubscribed`.
- Synthetic orphan-provider tests still emit `PROVIDER_NOT_SUBSCRIBED`.
- Remote behavior is unchanged unless the same shared path is covered by tests.

## Phase 2: Align Parent/Child Lifecycle Ownership

### Task 2.1: Reproduce short-lived local reader disposal from `comic_detail.read`

**Files to modify later:**
- `test/reader/reader_trace_contract_test.dart`
- `test/reader/reader_open_contracts_test.dart`
- `test/features/reader/presentation/reader_route_dispatch_authority_test.dart`

**Work:**
- Add a focused test that opens local reader through the canonical request path used by `comic_detail.read`.
- Capture the route host snapshot, `ReaderWithLoading` branch transitions, and `Reader.dispose` event sequence.
- Prove whether the warning is caused by a real parent teardown, a branch transition, or route lifecycle observer miss.

**Acceptance:**
- The failing test identifies the exact warning path for the local route:
  - parent state disposed too early
  - child replaced during loading/content swap
  - route observer state missing even though route stays active

### Task 2.2: Fix `ReaderWithLoading` retained-tab/unmount heuristics for canonical local reader

**Files to modify later:**
- `lib/features/reader/presentation/loading.dart`
- `lib/features/reader/presentation/diagnostics.dart`
- `test/reader/reader_trace_contract_test.dart`

**Work:**
- Verify whether `expectedReaderTabId` is derived from the same canonical local `SourceRef` used to load the content.
- Verify whether `activeReaderTabId` lookup is racing against session persistence or using a mismatched comic identity.
- Tighten `_recordParentUnmountIfRetained(...)` so the warning only fires when the parent truly unmounts while the same tab remains active unexpectedly.
- Preserve the warning for genuine retained-tab leaks.

**Acceptance:**
- Local reader opened from `comic_detail.read` no longer emits `reader.parent.unmount.retainedTab` for a healthy steady-state open.
- Tests still cover the true retained-tab leak case.

### Task 2.3: Fix `Reader.dispose.short_lived` to respect expected route transitions

**Files to modify later:**
- `lib/features/reader/presentation/reader.dart`
- `lib/features/reader/presentation/diagnostics.dart`
- `test/reader/reader_trace_contract_test.dart`

**Work:**
- Audit whether local reader child replacement during parent loading/content transitions is being misclassified as a short-lived route teardown.
- Ensure `Reader.dispose.short_lived` only warns when the route lifecycle does not explain the short disposal.
- If the local route rebuilds the child with a different key during legitimate state resolution, make the diagnostic reflect “expected child replacement” instead of “unexpected short-lived dispose”.

**Acceptance:**
- Healthy local reader opens no longer emit `reader.dispose.short_lived`.
- Route pop/remove/replace cases and genuine unexpected short-lived disposal remain covered by tests.

## Phase 3: Make Local Debug Snapshot Canonical-First

### Task 3.1: Redefine local `linkStatus` semantics in `ReaderDebugSnapshot`

**Files to modify later:**
- `lib/foundation/reader/reader_debug_snapshot.dart`
- `test/reader/reader_debug_snapshot_test.dart`
- `lib/foundation/diagnostics/debug_diagnostics_service.dart` (only if snapshot serialization/consumer logic must be updated)

**Work:**
- Stop treating absent remote/source link fields as `missing` when `loadMode == 'local'` and canonical local reader state exists.
- Use local-aware semantics such as `local_only` or another explicit local canonical status backed by the actual owning data.
- Keep remote snapshots unchanged.
- Preserve fail-loud behavior when the canonical local comic or page order is actually missing.

**Acceptance:**
- Canonical local reader snapshot no longer reports `linkStatus=missing` solely because remote source-link fields are null.
- Existing local failure tests still throw for real missing canonical records.

### Task 3.2: Add regression coverage for imported local reader sessions

**Files to modify later:**
- `test/reader/reader_debug_snapshot_test.dart`
- `test/reader/reader_dispatch_boundary_test.dart`

**Work:**
- Add or extend fixtures for `__imported__` local sessions where `readerTabId`, `pageOrderId`, and local-only link semantics all coexist.
- Verify the snapshot remains consistent with the canonical local session ID and page-order records.

**Acceptance:**
- Imported local session fixtures prove local snapshot truth without requiring remote source-link presence.

## Phase 4: Integrate With Broader Reader Cutover

### Task 4.1: Record the slice boundary and residual follow-ups

**Files to modify later:**
- `docs/plans/tracker.md` (only if the team wants tracker linkage)
- `docs/plans/2026-05-05-reader-cutover-local-reader-lifecycle-plan.md`

**Work:**
- Mark this slice as reader-runtime/diagnostics-only.
- Capture any follow-up that belongs to later lanes:
  - source-key-first identity cleanup
  - broader `ComicType` cutover
  - any remote-reader lifecycle issue only if proven shared

**Acceptance:**
- The merge summary makes clear what was fixed here versus what remains for later cutover lanes.

## Exact File Paths Expected To Be Touched Later

Primary runtime files:

- `lib/features/reader/presentation/loading.dart`
- `lib/features/reader/presentation/reader.dart`
- `lib/features/reader/presentation/diagnostics.dart`
- `lib/features/reader/presentation/reader_image_provider_factory.dart`
- `lib/foundation/image_provider/reader_image.dart`
- `lib/foundation/reader/reader_diagnostics.dart`
- `lib/foundation/reader/reader_debug_snapshot.dart`

Likely test files:

- `test/reader/reader_load_visibility_test.dart`
- `test/reader/reader_trace_contract_test.dart`
- `test/reader/reader_debug_snapshot_test.dart`
- `test/reader/reader_open_contracts_test.dart`
- `test/features/reader/presentation/reader_route_dispatch_authority_test.dart`
- `test/reader/reader_dispatch_boundary_test.dart`

Route-entry evidence files to inspect but not modify unless proven necessary:

- `lib/pages/comic_details_page/actions.dart`
- `lib/app/router.dart`
- `lib/foundation/local/local_comic.dart`

## Verification Commands

Run the narrow suite first:

```bash
flutter test test/reader/reader_load_visibility_test.dart
flutter test test/reader/reader_trace_contract_test.dart
flutter test test/reader/reader_debug_snapshot_test.dart
flutter test test/reader/reader_open_contracts_test.dart
flutter test test/features/reader/presentation/reader_route_dispatch_authority_test.dart
flutter test test/reader/reader_dispatch_boundary_test.dart
```

Then the broader reader verification:

```bash
flutter test test/reader
flutter analyze
git diff --check
git status --short
```

If Flutter cache permissions fail with `engine.stamp` or similar environment noise, rerun in a permitted context before changing app logic.

## Risks

- The current warning may be a diagnostic-timing bug rather than a runtime bug; a naive fix could suppress real orphan-provider signals.
- `ReaderWithLoading` and `Reader` may both be correct individually but disagree on source-ref/tab identity timing.
- Local imported sessions (`__imported__`) can hide identity mismatches if tests only cover non-imported local fixtures.
- Changing snapshot semantics carelessly could make remote missing-link cases look healthy.
- Another agent may touch adjacent reader files during execution; stale assumptions can invalidate a planned patch quickly.

## Mitigations

- Write the failing test before each runtime change.
- Keep diagnostics truthy: downgrade only false positives, not hard missing-state failures.
- Re-read runtime files immediately before patching if the worktree changes.
- Preserve remote behavior behind local-only tests unless a shared regression is proven.
- Keep commits slice-sized:
  - provider truth-boundary
  - parent/child lifecycle alignment
  - debug snapshot local semantics

## Done Criteria

- Local reader opened from `comic_detail.read` renders without false `reader.render.provider.notSubscribed`.
- Healthy local reader steady-state no longer emits `reader.dispose.short_lived` or `reader.parent.unmount.retainedTab`.
- `expectedReaderTabId` / `activeReaderTabId` checks are aligned with canonical local reader ownership.
- `ReaderDebugSnapshot` reports a local-canonical `linkStatus` for local reader instead of `missing` when remote source-link fields are absent.
- No M27 source runtime changes, no legacy local lookup revival, and no canonical local DB cutover changes are included.
