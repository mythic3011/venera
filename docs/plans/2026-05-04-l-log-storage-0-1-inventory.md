# L-log-storage-0/1 Inventory And First Slice

Date: 2026-05-04  
Lane: `L-log-storage-1`  
Scope: inventory + structured persisted writer + size rotation + optional gzip archives + rotation lock file + persistedLevel filter.  
Out of scope: UI redesign, import/local/reconcile.

## Current Surfaces Classification

`runtime memory`
- `AppDiagnostics` ring buffer (`lib/foundation/diagnostics/diagnostics.dart`)
- `DevDiagnosticsApi.recent/exportNdjson` (reads ring buffer events)

`persisted structured`
- `logs/diagnostics.ndjson` under `App.dataPath/logs/` (introduced in L-log-storage-1)
- Writer path is owned by `LogStorageWriter` and receives `DiagnosticEvent.toJson()` records.

`legacy projection`
- `Log.addLog` in-memory list + `logs.txt` append sink (`lib/foundation/log.dart`)
- `_LegacyLogDiagnosticSink` projects warn/error structured events into legacy log text.

`export-only`
- `buildDiagnosticsExportText()` combines in-memory structured NDJSON snapshot + legacy export text (`lib/foundation/diagnostics/log_export_bundle.dart`)
- `Log.exportToFile()` remains legacy-compat export surface.

## L-log-storage-1 Decisions

1. Structured persisted authority file name is `diagnostics.ndjson` to match existing application-support authority docs.
2. Structured file writer is single queue/future-chain (`LogStorageWriter`) to preserve append order.
3. App flow must not fail if file append fails; writer errors are isolated in storage layer.
4. No behavior change for legacy `logs.txt` in this slice.

## Touched Runtime Paths

- Added `lib/foundation/diagnostics/log_storage_writer.dart`
- Added structured file sink to `AppDiagnostics` default sinks in `lib/foundation/diagnostics/diagnostics.dart`

## Verification Focus For This Slice

- NDJSON append ordering is deterministic.
- Each append is exactly one JSON object per line.
- Size-based rotation keeps current file bounded and trims archives to policy cap.
- Rotated archives can be gzip compressed and decoded.
- Rotation acquires `logs/log.lock` via blocking exclusive file lock.
- Structured file writes are filtered by `persistedLevel` independently from runtime in-memory level.
- No runtime route/import/local/reconcile behavior changes.
