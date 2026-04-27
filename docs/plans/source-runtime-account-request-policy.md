# Source Runtime Account + Request Policy Core

## Problem

Comic source JavaScript currently owns too much mutable runtime behavior. Sources can directly manage account state, cookies, request headers, retry behavior, cooldowns, and ad hoc error handling. This makes each source implement its own policy surface and creates inconsistent behavior across account login, account switching, session recovery, and blocked requests.

The current model also makes multi-account support risky. If requests read the active account at execution time, a user switching accounts can cause queued or retried requests to run with different cookies than the request originally intended. That produces hard-to-debug races and source-specific failures.

## Goals

- Move mutable runtime state ownership into Dart.
- Make the request pipeline the only owner of request-time headers, cookies, retry, cooldown, and diagnostics behavior.
- Support multi-account profiles with immutable request-time account snapshots.
- Keep JavaScript source logic bounded to source-specific hooks and parsers.
- Add a first-version diagnostics taxonomy so legacy and new runtime failures can be reported consistently.
- Keep legacy sources working through a best-effort adapter.

## Non-goals

- Do not replace all existing source APIs in one change.
- Do not require every existing source to migrate immediately.
- Do not promise perfect diagnostics classification for legacy throw strings.
- Do not build a full Source SDK v2 in the first implementation.
- Do not implement a custom cryptographic storage layer.

## Ownership Model

Dart owns mutable runtime state and lifecycle:

- account profile index
- account secrets
- active profile selection
- request-time account snapshots
- cookie application
- header profile application
- retry, queue, cooldown, and response classification lifecycle
- diagnostics taxonomy and error wrapping

JavaScript source files provide bounded source-specific behavior:

- declarative capability and account metadata
- URL builders and payload builders
- parsers
- executable hooks with restricted input and structured output

Avoid describing source policy as fully declarative. The correct model is runtime-owned lifecycle with source-provided bounded hooks.

## Runtime Architecture

The MVP introduces these Dart-side components:

- `ComicSourceRuntimeRequest`: single request entrypoint for source-owned network calls.
- `ComicSourceAccountStore`: per-source account profile index plus secure secret references.
- `ComicSourceAccountManager`: profile CRUD, active account selection, and validation orchestration.
- `ComicSourceRequestPolicy`: retry, cooldown, queue, and response classification decisions.
- `ComicSourceDiagnostics`: structured error codes and stage-aware reporting.
- `LegacyComicSourceAdapter`: preserves existing behavior and maps errors opportunistically.

The request pipeline is the authority:

```text
ComicSourceRuntimeRequest
  -> create immutable SourceRequestContext
  -> bind account profile snapshot
  -> apply HeaderProfile
  -> read CookieJar for snapshot profile
  -> apply RequestPolicy
  -> execute HTTP
  -> classify response
  -> emit Diagnostics
```

Account manager must not directly mutate request headers for in-flight requests. Account switching only affects new request contexts.

## Data Model

Non-secret account metadata is stored in a source-scoped account index:

```json
{
  "version": 1,
  "sourceKey": "ehentai",
  "activeProfileId": "profile_1",
  "profiles": [
    {
      "id": "profile_1",
      "label": "Main",
      "fieldNames": ["ipb_member_id", "ipb_pass_hash", "igneous", "star"],
      "cookieDomains": [".e-hentai.org", ".exhentai.org"],
      "secretRef": "comic_source_accounts/ehentai/profile_1",
      "revision": 3,
      "createdAt": "2026-04-28T00:00:00.000Z",
      "lastUsedAt": "2026-04-28T00:00:00.000Z"
    }
  ]
}
```

Secret values are not stored in ordinary source data. They are stored behind secure references:

```text
comic_source_accounts/{sourceKey}/{profileId}
comic_source_account_index/{sourceKey}
```

The account profile revision increments when credential-like material changes.

## Secret Boundary

Credential-like data includes cookie field values, tokens, passwords, and account validation secrets. These values must not be stored as ordinary JSON in source data.

Use platform secure storage where available:

- iOS: Keychain-backed storage.
- Android: Keystore-backed encrypted storage through platform secure storage.
- Other platforms: use the strongest supported platform-backed storage and clearly mark weaker storage behavior.

Do not hand-roll crypto or implement a plain encrypted JSON file as the primary secret store.

Export/import behavior:

- Source configuration and non-secret source data can be exported.
- Account secret store is excluded by default.
- Exporting secrets requires explicit user opt-in and a warning.
- Imported secrets must be revalidated before use.

## Request Flow

Each runtime request creates an immutable context:

```dart
class SourceRequestContext {
  final String sourceKey;
  final String requestId;
  final String? accountProfileId;
  final int? accountRevision;
  final String? headerProfile;
  final DateTime createdAt;
}
```

The context is immutable after creation. Retry, cooldown, queue, and diagnostics must reference or copy the same context. They must not reread the current active account during execution.

Request execution steps:

1. Resolve source and requested header profile.
2. Create `SourceRequestContext`.
3. Resolve account profile snapshot from `accountProfileId` and `accountRevision`.
4. Apply header profile.
5. Load cookies or credential material for the snapshot profile.
6. Execute request through the app HTTP client.
7. Classify response with runtime policy and optional source hook.
8. Emit structured diagnostics for failures.

If the snapshot profile is deleted before execution, fail with `ACCOUNT_PROFILE_UNAVAILABLE`. Do not silently fallback to the active profile.

## Account Switching Semantics

Account switching updates only the active profile pointer used for new requests. It must not mutate existing `SourceRequestContext` instances.

Rules:

- New requests bind to the current active account unless explicitly given a profile id.
- Queued requests continue with their original profile id and revision.
- Retries use the same request context.
- Cooldown keys include source key, domain, and optionally profile id when the block is account-specific.
- Logout clears the active pointer and selected session material, but account profile deletion is explicit.

## Source Hooks Contract

Hooks are executable source-specific logic, not plain declarative policy. They must be bounded and pure-ish.

Initial hooks:

- `AccountValidatorHook`: validates account fields or cookie material.
- `ResponseClassifierHook`: classifies source-specific blocked or expired responses.
- `SessionRecoveryHook`: attempts source-specific recovery when the runtime asks for it.

Hook constraints:

- Hooks receive structured input and return structured results.
- Hooks must not write account store, cookie jar, global source data, or request headers directly.
- Hooks must not mutate runtime-owned state.
- Hooks run with runtime-enforced timeout.
- Hook timeout and hook failure fail closed.

Example result shape:

```json
{
  "ok": false,
  "code": "COOKIE_EXPIRED",
  "message": "Login cookie is expired",
  "metadata": {
    "field": "igneous"
  }
}
```

Timeout behavior:

- Account validation timeout maps to `SOURCE_HOOK_TIMEOUT` and then `ACCOUNT_VALIDATION_FAILED`.
- Response classification timeout maps to `SOURCE_HOOK_TIMEOUT`; the runtime falls back to safe default classification.
- Session recovery timeout maps to `SESSION_RECOVERY_FAILED`.

## Diagnostics Taxonomy

First-version error codes:

```text
ACCOUNT_MISSING_FIELD
ACCOUNT_PROFILE_UNAVAILABLE
ACCOUNT_VALIDATION_FAILED
COOKIE_EXPIRED
COOKIE_APPLY_FAILED
REQUEST_COOLDOWN
REQUEST_TIMEOUT
HTTP_BLOCKED
HTTP_UNEXPECTED_STATUS
PARSER_EMPTY_RESULT
PARSER_INVALID_CONTENT
SESSION_RECOVERY_FAILED
SOURCE_HOOK_FAILED
SOURCE_HOOK_TIMEOUT
```

Runtime errors use a common envelope:

```dart
class SourceRuntimeError {
  final String code;
  final String message;
  final String sourceKey;
  final String? requestId;
  final String? accountProfileId;
  final String stage; // parse, account, request, parser, session
  final Object? cause;
}
```

UI does not need a complex diagnostics screen in the MVP. It should show the user-facing message and preserve structured details for logs/debug tooling.

Do not expose stack traces or raw secret values in user-visible messages or logs.

## Legacy Compatibility

Legacy sources continue to run through existing APIs. The legacy adapter preserves behavior first.

Diagnostics mapping on legacy paths is best-effort only. Legacy throw strings and source-specific errors may map to generic codes such as `SOURCE_HOOK_FAILED`, `HTTP_UNEXPECTED_STATUS`, or `PARSER_INVALID_CONTENT`.

The runtime must not claim complete classification for legacy errors.

## Migration Plan

1. Add diagnostics taxonomy and error envelope without changing source behavior.
2. Add account store index and secure secret store abstraction.
3. Add immutable `SourceRequestContext`.
4. Add runtime request pipeline behind a new bridge API.
5. Add account validation hook support.
6. Add one migrated source as a reference implementation.
7. Keep old source APIs as legacy adapter paths.
8. Gradually move sources to runtime-owned account/request policy.

## Test Plan

Unit tests:

- Account profile create, update, delete, and switch.
- Secret values are not stored in ordinary source data.
- Export excludes account secrets by default.
- Import requires revalidation for secrets.
- Request context is immutable after creation.
- Retry uses the same request context.
- Queued request keeps original account profile after account switch.
- Deleted snapshot profile fails with `ACCOUNT_PROFILE_UNAVAILABLE`.
- Hook timeout maps to fail-closed diagnostics.
- Legacy errors are mapped opportunistically without changing behavior.

Integration tests:

- Add source with legacy account config.
- Add source with runtime account config.
- Switch accounts while requests are queued.
- Validate cookie-based login through hook.
- Classify blocked HTTP response through runtime policy.

Security tests:

- No secret values in logs.
- No secret values in source data export by default.
- Hook cannot directly mutate account store or cookie jar.

## Open Questions

- Which secure storage package or platform abstraction should be used for each supported platform?
- Should cooldown scope default to domain-only or domain plus profile id?
- Should source hooks run in the main JS engine or an isolated JS context?
- What timeout defaults should be used for validation, response classification, and session recovery hooks?
- Which source should be the first migrated reference source?
