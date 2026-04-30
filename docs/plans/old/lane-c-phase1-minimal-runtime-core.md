# Lane C Phase 1: Minimal Runtime Core (Docs-Only Plan)

## Scope Lock

This document defines the **only** allowed implementation scope for Lane C Phase 1.

Included in Phase 1:
1. `SourceRuntimeError`
2. `SourceRuntimeStage`
3. diagnostics code constants
4. immutable `SourceRequestContext`
5. request policy interface skeleton
6. legacy adapter diagnostics wrapper with no behavior change
7. tests for immutable request context and no account-switch mutation

Not included in this phase:
- secure storage implementation
- account CRUD UI
- hook execution
- cookie migration/loading pipeline changes
- protected-origin WebView recovery
- source distribution/feed security
- e-hentai/exhentai migration
- legacy DB compatibility bridges or fallback runtime reads

## Cross-Plan Contract

This lane must stay aligned with the fork-wide breaking-change storage
direction documented in
`docs/plans/2026-04-30-venera-next-core-rewrite-plan.md` and
`docs/plans/2026-04-30-unified-comic-detail-local-remote-architecture.md`.

Hard rules for Lane C Phase 1:

1. Do not introduce runtime fallback reads from `local.db`, `history.db`,
   `local_favorite.db`, or hidden JSON domain state.
2. Do not add adapter code that preserves the old multi-DB authority model.
3. If runtime diagnostics need storage-related metadata later, they must target
   the canonical `data/venera.db` contract rather than legacy store layouts.
4. "Legacy" in this lane means legacy runtime failure shapes only. It does not
   authorize legacy persistence compatibility layers.
5. Old runtime-core code may only be touched here for extraction or
   buildability. This lane must not widen back into old storage-flow repair.

This keeps runtime-core work from accidentally reintroducing the same
compatibility surface that the storage redesign is explicitly removing.

## File-Level Implementation Plan

New files:

1. `lib/foundation/comic_source/runtime/source_runtime_stage.dart`
- Define `SourceRuntimeStage` enum.
- No behavioral wiring in this phase.

2. `lib/foundation/comic_source/runtime/source_runtime_codes.dart`
- Define stable diagnostics code constants.
- Keep as constants only.

3. `lib/foundation/comic_source/runtime/source_runtime_error.dart`
- Define immutable runtime error envelope.
- Include debug-safe `toString()` format.

4. `lib/foundation/comic_source/runtime/source_request_context.dart`
- Define immutable request context object with request/account snapshot metadata.
- No mutable fields and no implicit runtime lookups.

5. `lib/foundation/comic_source/runtime/source_request_policy.dart`
- Define request policy interface skeleton only.
- No concrete retry/cooldown implementation in this phase.

6. `lib/foundation/comic_source/runtime/legacy_source_diagnostics_adapter.dart`
- Define best-effort diagnostics mapping wrapper for legacy failures.
- Must not change runtime behavior or network semantics.

7. `lib/foundation/comic_source/runtime/runtime.dart`
- Barrel export for the new runtime primitives.

Minimal touchpoints (compile-time/export only):

8. `lib/foundation/comic_source/comic_source.dart`
- Optional export/import surface updates only.
- No account/network/runtime behavior changes.

9. `lib/foundation/comic_source/types.dart` (optional)
- Add typedefs only if required by interface signatures.
- No behavior changes.

## Explicit Deferrals

Deferred to later lanes/phases:
- secure storage abstraction and persistence
- account profile CRUD flows and UI
- validator/classifier hook execution runtime
- cookie profile binding/migration behavior
- protected-origin WebView recovery UX/pipeline
- source feed/distribution trust and security
- e-hentai/exhentai migration work
- any storage migration/import execution against legacy DBs

## Test Plan

Add focused tests only for Phase 1 surface:

1. `test/comic_source_runtime/source_request_context_test.dart`
- Verify immutable context contract.
- Verify request/account snapshot fields remain stable after creation.

2. `test/comic_source_runtime/request_context_account_snapshot_test.dart`
- Verify account switch in external state does not mutate existing request context.

3. `test/comic_source_runtime/legacy_source_diagnostics_adapter_test.dart`
- Verify known legacy failure mapping to expected diagnostics code/stage.
- Verify unknown failures map to generic code.
- Verify wrapper is non-invasive (no side effects).

Non-goal for this phase:
- No integration or migration tests for secure storage, hooks, cookie loading, or specific source migrations.
- No tests that encode legacy DB fallback behavior as a supported runtime
  contract.

## Security Notes

- Do not log raw account secrets, cookies, or tokens.
- `accountProfileId` is internal metadata and should be redacted or hashed in user/export logs.
- Hook output must be schema-validated before use.
- Hook-provided text must not become primary user-facing copy.
- Legacy adapter must not mutate request headers or cookies.

## Runtime Error Export Boundary

`SourceRuntimeError.cause` is debug-internal only.

Rules:
- Do not serialize `cause` into normal export/debug bundles.
- Do not show `cause` directly in UI.
- Redact request URLs, headers, cookies, account identifiers, and response bodies before logging.
- User-facing UI should use app-owned localized messages mapped from `code`, not `message` or `cause`.

## Legacy Adapter Boundary

`LegacyComicSourceDiagnosticsAdapter` is a pure mapper in Phase 1.

It must not:
- wrap or replace legacy execution paths
- change thrown exceptions
- change retry/cooldown behavior
- mutate request headers/cookies/accounts
- classify protected origins by parsing arbitrary HTML as normal content
- imply that legacy persistence layouts remain supported runtime authorities

It may only:
- map known legacy failures into `SourceRuntimeError`
- map unknown failures into a generic legacy/runtime diagnostic
- be called explicitly by tests or future wiring
