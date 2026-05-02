# M25.2 Appdata Settings Store Migration

## Goal
- Migrate app settings state from JSON sidecar files into canonical DB tables.
- Preserve existing semantics for sync filtering, device-local fields, defaults, and feature flags.
- Keep migration safe, idempotent, and reversible.

## Scope
- `appdata.json` -> `app_settings`
- `searchHistory` -> `search_history`
- `implicitData.json` -> `implicit_data`
- appdata init/load/save path only

Out of scope:
- no cookie migration
- no cache migration
- no ReaderNext route semantics change
- no broad storage consolidation beyond appdata/search/implicit lanes

## Hard Rules
1. Migration must be idempotent.
2. Missing `appdata.json` must not crash startup.
3. Corrupt `appdata.json` must not wipe DB settings.
4. Device-specific settings remain local-only.
5. `disableSyncFields` semantics must remain unchanged.
6. Sync-data generation must exclude disabled fields exactly as before.
7. Old `appdata.json` must be kept as backup until migration verification passes.
8. No feature-flag default regression is allowed.
9. `Settings._data` remains defaults authority; DB holds runtime values only.
10. Migration must be fail-closed for writes and fail-open for reads (fallback to defaults without destructive overwrite).

## Data Model

### app_settings
```sql
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  value_type TEXT NOT NULL,
  sync_policy TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
```

### search_history
```sql
CREATE TABLE search_history (
  keyword TEXT PRIMARY KEY,
  position INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
```

### implicit_data
```sql
CREATE TABLE implicit_data (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
```

## Migration Strategy

### Phase A: Schema + Store Adapter
- Add canonical DB schema for `app_settings`, `search_history`, `implicit_data`.
- Add `AppSettingsStore` adapter with typed get/set/list operations.
- Do not switch runtime read path yet.

### Phase B: DB-First Init with JSON Fallback
- Update `Appdata.doInit()` workflow:
  1. Try DB load first.
  2. If DB empty/uninitialized, attempt one-time JSON migration.
  3. If JSON missing, initialize from defaults (`Settings._data`) and continue.
  4. If JSON corrupt, preserve DB state, log redacted warning, continue with DB/defaults.
- Ensure migration marks completion without preventing safe re-run.

### Phase C: Sync Semantics Parity
- Preserve `disableSyncFields` and device-local exclusions exactly.
- Keep `syncdata` output behavior unchanged from caller perspective.
- Add parity tests against current semantics.

### Phase D: Backup + Rollback Safety
- Before JSON->DB migration write:
  - snapshot `appdata.json` backup (timestamped).
- Keep backup until verification criteria pass.
- Rollback path:
  - restore JSON backup and ignore DB settings tables (guarded mode).

## Required Tests

### Startup + Migration Safety
```dart
test('missing appdata.json does not crash startup', () async {});
test('corrupt appdata.json does not wipe existing db settings', () async {});
test('migration is idempotent across repeated init runs', () async {});
```

### Semantics Parity
```dart
test('disableSyncFields semantics unchanged after db migration', () async {});
test('device-specific fields remain local-only', () async {});
test('syncdata excludes disabled fields exactly as before', () async {});
test('feature flag defaults do not regress when db has no row', () async {});
```

### Rollback/Backup
```dart
test('json backup is created before first migration write', () async {});
test('rollback can restore prior json settings snapshot', () async {});
```

## Verification Commands
```bash
flutter test test/foundation/appdata* test/utils/data*
flutter test test/foundation/db/unified_comics_store_test.dart
dart analyze lib/foundation/appdata.dart lib/foundation/db test/foundation test/utils
git diff --check
```

## Exit Criteria
- App starts with DB-backed app settings without JSON dependency on steady state.
- Missing/corrupt JSON no longer causes startup failure or destructive overwrite.
- Sync filtering and local-only semantics remain behaviorally identical.
- Migration is idempotent and backup/rollback path is documented and tested.
- No cookie/cache/ReaderNext semantics changed in this milestone.

## Implementation Guardrails
- Do not remove `Settings._data` defaults authority in this milestone.
- Do not mix M25.2 with M25.3 cookie security changes.
- Keep patches narrow: appdata lane only.

## M25.2 Closeout Evidence
M25.2 migration acceptance coverage was added via:
- [appdata_m25_2_test.dart](/Users/mythic3014/Documents/project/venera/test/foundation/appdata_m25_2_test.dart)

Verified commands and outcomes:
1. `flutter test test/foundation/appdata_m25_2_test.dart`
   - Result: all tests passed (+5)
2. `dart analyze lib/foundation/appdata.dart test/foundation/appdata_m25_2_test.dart`
   - Result: no issues found
3. `flutter test test/foundation/cache_manager_m25_1_test.dart`
   - Result: all tests passed (+5)
4. `flutter test test/foundation/db/unified_comics_store_test.dart`
   - Result: all tests passed (+26)
5. `git diff --check`
   - Result: clean, no output

Authority and scope confirmation:
- M25.2 remains appdata/searchHistory/implicitData migration only.
- `Settings._data` defaults authority remains intact.
- `disableSyncFields` behavior remains unchanged for sync payload filtering.
- No ReaderNext route semantics changes were introduced.
- No cookie migration or cache migration semantics were introduced in this step.
