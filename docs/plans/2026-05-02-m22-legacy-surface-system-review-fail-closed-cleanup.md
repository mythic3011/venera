# M22 Legacy Surface System Review / Fail-Closed Cleanup

Goal:

- Audit legacy surfaces that can leak uninitialized `late` globals into UI/import/runtime flows.
- Replace crash-prone direct calls with typed safe or fail-closed bridge results.
- Fix confirmed local comics legacy crashes without changing ReaderNext cutover semantics.
  Scope:
- audit first
- targeted bugfix only
- fix LEG-001 settings local comics path crash
- fix LEG-002 CBZ import duplicate lookup crash
- no ReaderNext route semantics change
- no migration/import redesign
- no broad legacy rewrite
- no fake default paths
- no silent catch-all swallowing

## Hard Rules

1. M22 must not change ReaderNext M20 freeze semantics.
2. M22 must not add ReaderNext entrypoints.
3. M22 must not change feature-flag semantics.
4. M22 must not add fallback after blocked ReaderNext decisions.
5. Read-only UI legacy access may degrade to nullable / not configured state.
6. Import/write legacy access must fail closed when required legacy state is unavailable.
7. Import/write paths must not treat unavailable legacy DB as “not found”.
8. No fake default local comics path.
9. No auto-created local comics DB merely to bypass initialization errors.
10. No broad legacy manager rewrite in this milestone.
11. Safe bridge APIs must expose typed outcomes, not raw `LateInitializationError`.
12. Regression tests must prove no mutation occurs when import preconditions fail.

## Known Incidents

| ID      | Caller            | Legacy Surface                                          | Failure Mode                                                     | Flow Type    | Fix Policy                                      |
| ------- | ----------------- | ------------------------------------------------------- | ---------------------------------------------------------------- | ------------ | ----------------------------------------------- |
| LEG-001 | settings app page | `legacyReadLocalComicsRootPath`                         | `LateInitializationError: Field 'path' has not been initialized` | read-only UI | safe nullable getter + `Not configured` display |
| LEG-002 | CBZ import        | `legacyFindLocalComicByName -> LocalManager.findByName` | `LateInitializationError: Field '_db' has not been initialized`  | import/write | typed unavailable result + fail closed          |

## Audit Commands

```bash
rg -n "late .*;" lib/foundation lib/utils lib/pages
rg -n "LateInitializationError|LateError" lib test
rg -n "LocalManager\\.|legacy.*Local|localComics|_db|path" lib/foundation lib/utils lib/pages
rg -n "legacy[A-Z].*\\(" lib
rg -n "findByName|read.*Path|rootPath|database|init" lib/foundation lib/utils lib/pages
```

## Flow Classification Policy

| Flow Type             | Uninitialized Legacy State Policy                |
| --------------------- | ------------------------------------------------ |
| read-only UI          | nullable / disabled / Not configured             |
| import/write/mutation | typed blocked result / fail closed / no mutation |
| route authority       | blocked / no fallback / no identity guessing     |
| diagnostics           | redacted structured error                        |

## Tasks

| Task ID | Deliverable                                                                | Verification                |
| ------- | -------------------------------------------------------------------------- | --------------------------- |
| M22-T1  | legacy surface hazard report from grep audit                               | doc/table review            |
| M22-T2  | add safe nullable local comics path read API                               | unit test                   |
| M22-T3  | settings page uses safe path API and shows Not configured                  | widget test                 |
| M22-T4  | add typed local comic lookup result for import path                        | unit test                   |
| M22-T5  | CBZ import fails closed when local DB unavailable                          | import/unit test            |
| M22-T6  | authority guard: import/write unavailable must not be treated as not found | regression test             |
| M22-T7  | regression pack: ReaderNext M20 semantics unchanged                        | existing M20 command subset |

## Acceptance Tests

```dart
testWidgets('settings page does not crash when local comics path is uninitialized', (tester) async {
  // legacy path uninitialized
  // open settings page
  // expect no LateInitializationError
  // expect Not configured
});
test('legacy local comics path safe getter returns null when path is uninitialized', () {
  // legacy path uninitialized
  // expect null
});
test('local comic lookup returns unavailable when LocalManager database is uninitialized', () async {
  // LocalManager._db uninitialized
  // expect LegacyLocalComicLookupUnavailable
});
test('CBZ import fails closed when local comics database is unavailable', () async {
  // LocalManager._db uninitialized
  // import CBZ
  // expect typed/import-safe error
  // expect no duplicate-check false negative
  // expect no DB/file mutation
});
test('import path does not treat unavailable legacy lookup as not found', () async {
  // unavailable lookup
  // expect import blocked
  // expect not continue as new comic
});
```

## Verification Commands

```bash
flutter test test/foundation/local_comics_legacy_bridge_test.dart
flutter test test/pages/settings_app_local_comics_test.dart
flutter test test/utils/cbz_import_local_comics_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/foundation/local_storage_legacy_bridge.dart lib/foundation/local_comics_legacy_bridge.dart lib/pages/settings/app.dart lib/utils/cbz.dart test
git diff --check
```

## Exit Criteria

- LEG-001 fixed without fake default path.
- LEG-002 fixed with fail-closed import behavior.
- Read-only UI path handles uninitialized legacy state as Not configured.
- Import/write path blocks when legacy DB is unavailable.
- Unavailable lookup is not treated as not found.
- Hazard report exists for future legacy cleanup.
- ReaderNext route semantics remain unchanged.

## M22-T1 Hazard Report (Audit Snapshot)

Audit commands executed:

- `rg -n "late .*;" lib/foundation lib/utils lib/pages`
- `rg -n "LateInitializationError|LateError" lib test`
- `rg -n "legacy[A-Z].*\\(" lib`

Key findings:

- High-risk late surfaces remain concentrated in legacy manager-backed authorities:
  - `lib/foundation/local.dart`: `late Database _db`, `late String path`
  - `lib/foundation/favorites.dart`: `late Database _db`
  - `lib/foundation/cache_manager.dart`: `late Database _db`
- Settings read-only path now goes through nullable-safe bridge:
  - `lib/foundation/local_storage_legacy_bridge.dart` → `tryReadLocalComicsStoragePath`
- Import/write duplicate lookup now has typed unavailable classification:
  - `lib/foundation/local_comics_legacy_bridge.dart` → `LegacyLocalComicLookupResult`
  - `lib/utils/cbz.dart` fail-closed guard before duplicate decision

Risk classification for this milestone:

- LEG-001 (settings path read): mitigated via nullable-safe bridge + `Not configured`.
- LEG-002 (CBZ duplicate lookup): mitigated via typed unavailable + fail-closed import stop.
- Broader import surfaces in `lib/utils/import_comic.dart` still contain direct legacy lookups and are out of M22 targeted scope.

## M22 Closeout Evidence

Implemented:

- M22-T2: safe nullable local comics path read API
- M22-T3: settings display fallback to `Not configured`
- M22-T4: typed local comic lookup unavailable result
- M22-T5: CBZ import fail-closed when lookup authority unavailable
- M22-T6: regression assertion that unavailable is not treated as not found

Verification:

1. `flutter test test/foundation/local_comics_legacy_bridge_test.dart`  
   Result: All tests passed (`+2`)
2. `flutter test test/pages/settings_app_local_comics_test.dart`  
   Result: All tests passed (`+1`)
3. `flutter test test/utils/cbz_import_local_comics_test.dart`  
   Result: All tests passed (`+2`)
4. `flutter test test/features/reader_next/runtime/*authority*`  
   Result: All tests passed (`+24`)
5. `dart analyze lib/foundation/local_storage_legacy_bridge.dart lib/foundation/local_comics_legacy_bridge.dart lib/pages/settings/app.dart lib/utils/cbz.dart test`  
   Result: No issues found
6. `git diff --check`  
   Result: clean, no output

Scope confirmation:

- bugfix-only changes
- no ReaderNext route semantics changes
- no feature-flag semantic changes
- no migration/import redesign

## M23 Hazard Inventory (Post-M22 Audit)

Audit run on:

- `rg -n "late .*;" lib/foundation lib/utils lib/pages`
- `rg -n "LateInitializationError|LateError" lib test`
- `rg -n "LocalManager\\.|legacy.*Local|localComics|_db|path" lib/foundation lib/utils lib/pages`
- `rg -n "legacy[A-Z].*\\(" lib`
- `rg -n "findByName|read.*Path|rootPath|database|init" lib/foundation lib/utils lib/pages`

### Inventory Table

| Hazard ID | Surface                                       | Evidence                                                                                                        | Flow Type                       | Severity | Current Handling                                                                             | Suggested Follow-up                                                                            |
| --------- | --------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------- | -------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| HZ-001    | `LocalManager` late DB/path                   | `lib/foundation/local.dart:43,51`                                                                               | import/write + local UI/runtime | high     | M22 added safe read (`tryReadLocalComicsStoragePath`) and typed lookup unavailable in bridge | add typed wrappers for remaining write-sensitive legacy lookups in `import_comic.dart`         |
| HZ-002    | direct legacy duplicate checks in import flow | `lib/utils/import_comic.dart:312,487,822`                                                                       | import/write                    | high     | CBZ path fail-closed fixed in M22; other import entrypoints still direct                     | add typed unavailable/fail-closed checks for non-CBZ import flows                              |
| HZ-003    | legacy favorites DB late init                 | `lib/foundation/favorites.dart:292`                                                                             | favorites management            | medium   | existing init flow, no new guard in M22                                                      | audit read-before-init callsites in favorites pages; add typed unavailable result where needed |
| HZ-004    | legacy cache DB late init                     | `lib/foundation/cache_manager.dart:15`                                                                          | settings/debug/cache ops        | medium   | relies on singleton init timing                                                              | add explicit unavailable signal for cache-size read in settings when init not ready            |
| HZ-005    | translation map late init                     | `lib/utils/translations.dart:40`                                                                                | read-only UI                    | medium   | current usage assumes app boot path                                                          | add safe fallback text helper for early-test / pre-init contexts                               |
| HZ-006    | reader/home legacy local adapters             | `lib/pages/home_page_legacy_sections.dart`, `lib/pages/local_comics_page.dart` via `legacy*Local*` bridge calls | read-only UI + runtime routeing | medium   | dependent on local manager init checks in page flow                                          | maintain guard discipline; avoid direct late surface access from page layer                    |

### M23 Audit Conclusions

- M22 fixed both confirmed incidents (LEG-001 / LEG-002) with fail-closed behavior and no ReaderNext semantic change.
- Remaining high-risk items are concentrated in non-CBZ import paths that still use direct legacy lookups.
- Route authority boundaries for ReaderNext remain unchanged (validated by `test/features/reader_next/runtime/*authority*` in M22 verification).

### Suggested Next Lane (Docs Recommendation Only)

- Keep runtime semantics frozen.
- Open a narrow bugfix lane for `import_comic.dart` typed unavailable/fail-closed harmonization (no redesign, no fallback changes).

## Next Stage: M23 UI Runtime Surface Migration Audit

Goal:

- Audit UI surfaces still reading legacy runtime or manager state directly.
- Identify which UI surfaces can safely move to new runtime adapters.
- Keep ReaderNext M20 cutover freeze semantics intact.
- Prevent uninitialized legacy manager state from leaking into UI/import/runtime flows.

Scope:

- audit first
- no broad UI rewrite
- no ReaderNext route semantics change
- no identity derivation change
- no import/write behavior change
- no fake initialization
- no default fake path
- no direct legacy manager replacement in this stage

## M23 Hard Rules

1. M23 must not change ReaderNext M20 freeze semantics.
2. M23 must not add ReaderNext entrypoints.
3. M23 must not move route authority into pages.
4. M23 must not allow UI code to construct `SourceRef`.
5. M23 must not allow UI code to construct `ReaderNextOpenRequest`.
6. Read-only UI may show nullable, disabled, unavailable, or `Not configured` states.
7. Mutation/import UI must use typed command results and fail closed when runtime authority is unavailable.
8. Mutation/import UI must not treat unavailable runtime state as not found.
9. No fake default local comics path.
10. No fake database initialization merely to bypass readiness errors.
11. No broad legacy manager rewrite in M23.
12. M23 output must be an inventory and migration plan before implementation.

## M23 Audit Commands

```bash
rg -n "LocalManager\\.|FavoritesManager\\.|CacheManager\\.|late .*_db|legacy.*\\(" lib/pages lib/components lib/widgets
rg -n "foundation/(local|favorites|cache_manager)\\.dart" lib/pages lib/components lib/widgets
rg -n "localComics|favorites|downloads|cache|history" lib/pages lib/components lib/widgets
rg -n "ReaderNextOpenRequest\\(|SourceRef\\.|upstreamComicRefId|chapterRefId|fromLegacyRemote" lib/pages lib/components lib/widgets
```

## M23 UI Surface Classification

| Class           | Meaning                       | Required Policy                          |
| --------------- | ----------------------------- | ---------------------------------------- |
| UI-read         | display-only state            | nullable adapter / unavailable state     |
| UI-command      | user-triggered action         | typed command result                     |
| import/write    | mutation path                 | fail closed / no mutation on unavailable |
| route-authority | opens reader/imports identity | bridge/controller only                   |
| diagnostics     | reporting/logging             | redacted structured output               |

## M23 Initial Hazard Table

| ID         | Surface                     | Risk                                           | Flow Type         | Required Follow-up                          |
| ---------- | --------------------------- | ---------------------------------------------- | ----------------- | ------------------------------------------- |
| UI-LEG-001 | settings local comics path  | legacy path may be uninitialized               | UI-read           | already mitigated by M22 safe getter        |
| UI-LEG-002 | CBZ import duplicate lookup | legacy DB may be unavailable                   | import/write      | already mitigated by M22 fail-closed lookup |
| UI-LEG-003 | local comics pages          | may read `LocalManager` directly               | UI-read / command | audit required                              |
| UI-LEG-004 | favorites pages             | may read `FavoritesManager` directly           | UI-read / command | audit required                              |
| UI-LEG-005 | downloads/cache pages       | may read cache/download manager state directly | UI-read / command | audit required                              |

## M23 Deliverables

| Task ID | Deliverable                                                                                 | Verification             |
| ------- | ------------------------------------------------------------------------------------------- | ------------------------ |
| M23-T1  | UI legacy runtime surface inventory                                                         | hazard table review      |
| M23-T2  | classify each surface as UI-read, UI-command, import/write, route-authority, or diagnostics | classification review    |
| M23-T3  | identify read-only surfaces safe for adapter migration                                      | migration candidate list |
| M23-T4  | identify mutation/import surfaces requiring fail-closed command results                     | migration candidate list |
| M23-T5  | identify surfaces that must remain bridge/controller-owned                                  | authority review         |
| M23-T6  | propose M23.1 import/write fail-closed harmonization plan                                   | follow-up plan           |

## M23 Exit Criteria

- UI legacy runtime surface inventory exists.
- Each surface is classified by flow type.
- Read-only UI migration candidates are identified separately from mutation/import surfaces.
- Import/write surfaces are not migrated without fail-closed command semantics.
- Route-authority surfaces remain bridge/controller-owned.
- ReaderNext M20 freeze semantics remain unchanged.
- No runtime behavior changes are introduced in M23 audit.

## Next Stage: M23.1 Import Flow Fail-Closed Harmonization

Goal:

- Extend M22 CBZ fail-closed lookup semantics to remaining import flows.
- Ensure unavailable legacy local comics DB is never treated as duplicate-not-found.
- Prevent import/write paths from mutating files or DB state when legacy lookup authority is unavailable.
- Keep ReaderNext M20 freeze semantics unchanged.

Scope:

- import/write bugfix only
- focus on `lib/utils/import_comic.dart`
- add or reuse typed legacy bridge lookup wrappers
- no import redesign
- no importer UX redesign
- no fake DB initialization
- no fake default path
- no legacy manager rewrite
- no ReaderNext route semantics change
- no feature-flag semantics change

## M23.1 Hard Rules

1. Import/write paths must fail closed when local comics lookup authority is unavailable.
2. Unavailable legacy DB must never be treated as duplicate-not-found.
3. No file mutation may occur after unavailable lookup.
4. No DB mutation may occur after unavailable lookup.
5. No fake default local comics path.
6. No auto-created local comics DB merely to bypass readiness errors.
7. No silent catch-all swallowing.
8. Existing successful CBZ import semantics must remain unchanged.
9. Existing M22 CBZ fail-closed behavior must remain unchanged.
10. ReaderNext M20 freeze semantics must remain unchanged.
11. Import errors must be typed/actionable enough for UI to show recovery guidance later.
12. M23.1 must not broaden into full import redesign.

## M23.1 Target Evidence

Known direct duplicate-check surfaces from audit:

| Evidence                          | Flow         | Risk                                           | Required Policy                 |
| --------------------------------- | ------------ | ---------------------------------------------- | ------------------------------- |
| `lib/utils/import_comic.dart:312` | import/write | unavailable lookup may be treated as not found | typed unavailable + fail closed |
| `lib/utils/import_comic.dart:487` | import/write | unavailable lookup may be treated as not found | typed unavailable + fail closed |
| `lib/utils/import_comic.dart:822` | import/write | unavailable lookup may be treated as not found | typed unavailable + fail closed |

Line numbers are audit hints only. Implementation must match current code structure rather than relying on fixed line numbers.

## M23.1 Tasks

| Task ID  | Deliverable                                                        | Verification             |
| -------- | ------------------------------------------------------------------ | ------------------------ |
| M23.1-T1 | identify non-CBZ import duplicate lookup callsites                 | grep/code review         |
| M23.1-T2 | route non-CBZ duplicate lookups through typed legacy bridge result | unit test                |
| M23.1-T3 | fail closed when lookup result is unavailable                      | import/unit test         |
| M23.1-T4 | prove unavailable lookup is not treated as not found               | regression test          |
| M23.1-T5 | prove no mutation occurs after unavailable lookup                  | regression test          |
| M23.1-T6 | keep CBZ M22 behavior unchanged                                    | regression test          |
| M23.1-T7 | verify ReaderNext M20 authority tests remain green                 | existing authority tests |

## M23.1 Acceptance Tests

```dart
test('non-CBZ import fails closed when local lookup is unavailable', () async {
  // LocalManager._db uninitialized or legacy lookup unavailable
  // trigger non-CBZ import path
  // expect typed/import-safe error
  // expect no DB mutation
  // expect no file mutation
});

test('import_comic duplicate checks do not treat unavailable as not found', () async {
  // unavailable lookup result
  // expect import blocked
  // expect import does not continue as new comic
});

test('CBZ fail-closed behavior remains unchanged', () async {
  // preserve M22 CBZ regression behavior
  // unavailable lookup blocks import
  // unavailable lookup is not treated as not found
});

test('successful import behavior is unchanged when local lookup is available', () async {
  // LocalManager lookup ready
  // duplicate-not-found remains not found
  // existing success path still works
});
```

## M23.1 Verification Commands

```bash
rg -n "findByName|legacyFindLocalComicByName|legacyLookupLocalComicByName|LegacyLocalComicLookup" lib/utils/import_comic.dart lib/utils/cbz.dart lib/foundation/local_comics_legacy_bridge.dart
flutter test test/utils/import_comic_legacy_lookup_fail_closed_test.dart
flutter test test/utils/cbz_import_local_comics_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/foundation/local_comics_legacy_bridge.dart lib/utils/import_comic.dart lib/utils/cbz.dart test/utils/import_comic_legacy_lookup_fail_closed_test.dart test/utils/cbz_import_local_comics_test.dart
git diff --check
```

## M23.1 Exit Criteria

- Non-CBZ import duplicate lookups use typed legacy bridge results.
- Unavailable legacy lookup blocks import/write flow.
- Unavailable legacy lookup is not treated as duplicate-not-found.
- No file/DB mutation occurs after unavailable lookup.
- Existing CBZ M22 fail-closed behavior remains unchanged.
- Existing successful import behavior remains unchanged when lookup authority is available.
- ReaderNext M20 freeze semantics remain unchanged.

## M23.1 Implementation Evidence (Import Fail-Closed Harmonization)

Implemented (bugfix-only):

- Added import-level typed duplicate lookup helper:
  - `lookupLocalComicForImportDuplicateCheck(...)`
- Added import-level root-path requirement helper:
  - `requireLocalComicsRootPathForImport(...)`
- Updated `import_comic.dart` direct legacy lookup/root-path callsites to fail closed on unavailable legacy state:
  - `_importBundleAsSingleComic(...)`
  - `_importPdfAsComic(...)`
  - `_checkSingleComic(...)`
  - `_copyComicsToLocalDir(...)`

Verification:

1. `flutter test test/utils/import_comic_fail_closed_test.dart`  
   Result: All tests passed (`+2`)
2. `flutter test test/utils/cbz_import_local_comics_test.dart`  
   Result: All tests passed (`+2`)
3. `flutter test test/features/reader_next/runtime/*authority*`  
   Result: All tests passed (`+24`)
4. `dart analyze lib/utils/import_comic.dart lib/utils/cbz.dart lib/foundation/local_comics_legacy_bridge.dart test/utils/import_comic_fail_closed_test.dart test/utils/cbz_import_local_comics_test.dart`  
   Result: No issues found
5. `git diff --check`  
   Result: clean, no output

Scope confirmation:

- no ReaderNext route semantic changes
- no feature-flag semantic changes
- no migration/import redesign
