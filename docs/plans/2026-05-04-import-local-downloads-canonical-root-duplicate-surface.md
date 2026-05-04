# Canonical Local Downloads + Duplicate Import Surface Plan

## Summary
- First fix `ImportComic.localDownloads()` as the immediate blocker: remove `legacyLocalComicsDirectory()` from `lib/utils/import_comic.dart` and resolve the root through `localImportStorage.requireRootPath()`.
- Then fix duplicate import reporting: replace raw `Exception("Comic with name ... already exists")` with typed `ImportFailure.duplicateDetected` and structured diagnostics.
- Keep the reconcile work out of this patch except passive missing-file handling. No cleanup, no duplicate repair flow, no legacy DB repair.

## Key Changes
- Extend `ImportFailure` in `lib/utils/import_comic.dart` with:
  - `ImportFailure.duplicateDetected({comicTitle, targetDirectory, existingComicId})`
  - `ImportFailure.missingFiles({comicTitle, targetDirectory})`
  - structured fields: `code`, `message`, `data`, `uiMessage`
- `localDownloads()` behavior:
  - call `await localImportStorage.requireRootPath()`
  - `Directory(rootPath).createSync(recursive: true)` if the canonical root is missing
  - inspect root with `FileSystemEntity.typeSync(rootPath, followLinks: false)`
  - if root path is a file or invalid entity, emit `import.local.missingFiles` / repair-needed typed failure and return `false`
  - scan with `listSync(recursive: false, followLinks: false)` or equivalent shallow async listing
  - sort candidate directories by natural name before probing, so import order is deterministic
  - never use filesystem order as page order
- `_checkSingleComic()` directory probing:
  - use `FileSystemEntity.typeSync(directory.path, followLinks: false)` before listing
  - if missing/file/not-directory, return typed missing-files result through the caller path instead of allowing `LateInitializationError`
  - keep page/chapter ordering owned by existing natural sort helpers
- Duplicate handling:
  - replace raw duplicate exceptions in `ImportComic._importPdfAsComic()` and `CBZ._importExtractedDirectory()`
  - emit diagnostics on channel `import.local`, message `import.local.duplicateDetected`
  - diagnostic data: `comicTitle`, `targetDirectory`, `existingComicId` when available, `action: blocked`
  - UI should show an "already exists" conflict message from `ImportFailure.uiMessage`, not `e.toString()` or a stack-looking message
  - duplicate remains fail-closed: no registration, no copy, no app-unhandled crash

## Tests
- Add focused tests in `test/utils/cbz_import_canonical_storage_test.dart` or a new import-local test file:
  - `localDownloads` source contains no `legacyLocalComicsDirectory`
  - missing canonical root is created before scanning
  - canonical root path that is a file returns false and emits `import.local.missingFiles`
  - shallow scan ignores nested folders and does not follow symlinks
  - duplicate CBZ/PDF import throws or returns `ImportFailure.duplicateDetected`, emits `import.local.duplicateDetected`, and includes `action: blocked`
  - duplicate path does not log `app.unhandled` and does not register imported comic
- Run:
  - `flutter test test/import_comic_structure_test.dart`
  - `flutter test test/utils/cbz_import_canonical_storage_test.dart`
  - `dart analyze lib/utils/import_comic.dart lib/utils/cbz.dart`

## Assumptions
- Preserve public caller signature `Future<bool> localDownloads()` for this slice.
- `existingComicId` is optional unless current canonical browse records expose it cheaply.
- "Passive hide missing files" means return a typed false/blocked result plus diagnostics only; no filesystem deletion, no DB cleanup, no repair UI in this patch.
