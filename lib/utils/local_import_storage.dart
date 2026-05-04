import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local/local_library_file_probe.dart';
import 'package:venera/foundation/local.dart';

enum LocalImportPreflightAction {
  createNew,
  repairExisting,
  conflictExistingDirectory,
  conflictExistingCanonicalRecord,
}

class LocalImportPreflightDecision {
  const LocalImportPreflightDecision({
    required this.action,
    required this.targetDirectory,
    this.existingComicId,
  });

  final LocalImportPreflightAction action;
  final String targetDirectory;
  final String? existingComicId;
}

abstract class LocalImportStoragePort {
  Future<void> assertStorageReadyForImport(String comicTitle);
  Future<bool> hasDuplicateTitle(String title);
  Future<String> requireRootPath();
  Future<LocalImportPreflightDecision> preflightImport(String comicTitle);
  Future<LocalComic> registerImportedComic(
    LocalComic comic, {
    String? existingComicId,
  });
}

class CanonicalLocalImportStorage implements LocalImportStoragePort {
  const CanonicalLocalImportStorage({
    this.loadBrowseRecords,
    this.resolveRootPath,
    this.legacyMigrationMirror,
    this.enableLegacyMigrationMirror = false,
    this.syncComic,
    this.idSeed,
    this.hasCanonicalComicId,
  });

  final Future<List<dynamic>> Function()? loadBrowseRecords;
  final Future<String> Function()? resolveRootPath;
  final Future<void> Function(LocalComic comic, String rootPath)?
  legacyMigrationMirror;
  final bool enableLegacyMigrationMirror;
  final Future<void> Function(LocalComic comic)? syncComic;
  final String Function()? idSeed;
  final Future<bool> Function(String comicId)? hasCanonicalComicId;
  final LocalLibraryFileProbe fileProbe = const LocalLibraryFileProbe();

  String _sanitizeDirectoryName(String name) {
    final invalid = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
    final cleaned = name.trim().replaceAll(invalid, '_');
    return cleaned.isEmpty ? 'comic' : cleaned;
  }

  Future<List<dynamic>> _loadCanonicalBrowseRecords(String comicTitle) async {
    AppDiagnostics.trace(
      'import.local',
      'import.local.storageRoute',
      data: {
        'comicTitle': comicTitle,
        'authority': 'canonical_local_library',
        'storage': 'canonical_db',
      },
    );
    try {
      final rows =
          await (loadBrowseRecords ??
              () => App.repositories.localLibrary.store
                  .loadLocalLibraryBrowseRecords())();
      AppDiagnostics.trace(
        'import.local',
        'import.local.canonicalReady',
        data: {
          'comicTitle': comicTitle,
          'storage': 'canonical_db',
          'browseRecordCount': rows.length,
        },
      );
      return rows;
    } catch (error) {
      throw Exception(
        'Canonical local library unavailable (fail closed): '
        'CANONICAL_UNAVAILABLE',
      );
    }
  }

  String _normalizeTitle(String title) => title.trim().toLowerCase();

  @override
  Future<void> assertStorageReadyForImport(String comicTitle) async {
    AppDiagnostics.info(
      'import.local',
      'import.local.legacyMirrorSkipped',
      data: {
        'comicTitle': comicTitle,
        'code': 'LEGACY_MIRROR_DISABLED',
        'authority': 'legacy_local_db',
        'reason': 'policy_skip',
      },
    );
    await _loadCanonicalBrowseRecords(comicTitle);
  }

  @override
  Future<bool> hasDuplicateTitle(String title) async {
    final normalizedTitle = _normalizeTitle(title);
    final rows = await _loadCanonicalBrowseRecords(title);
    for (final row in rows) {
      final dynamicRecord = row;
      final recordTitle = dynamicRecord.title?.toString() ?? '';
      final recordNormalized = dynamicRecord.normalizedTitle?.toString() ?? '';
      if (_normalizeTitle(recordTitle) == normalizedTitle ||
          _normalizeTitle(recordNormalized) == normalizedTitle) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<String> requireRootPath() async {
    try {
      final rootPath = await (resolveRootPath ?? _resolveCanonicalRootPath)();
      if (rootPath.trim().isEmpty) {
        throw Exception('empty path');
      }
      return rootPath.trim();
    } catch (_) {
      throw Exception(
        'Canonical local storage unavailable (fail closed): '
        'CANONICAL_ROOT_UNAVAILABLE',
      );
    }
  }

  Future<String> _allocateComicId() async {
    final baseSeed =
        (idSeed ?? () => DateTime.now().microsecondsSinceEpoch.toString())();
    var suffix = 0;
    while (true) {
      final candidate = suffix == 0 ? baseSeed : '$baseSeed-$suffix';
      final exists =
          await (hasCanonicalComicId ??
              (String comicId) async =>
                  (await App.unifiedComicsStore.loadComicSnapshot(comicId)) !=
                  null)(candidate);
      if (!exists) {
        return candidate;
      }
      suffix++;
    }
  }

  @override
  Future<LocalImportPreflightDecision> preflightImport(
    String comicTitle,
  ) async {
    final rootPath = await requireRootPath();
    final directoryName = _sanitizeDirectoryName(comicTitle);
    final targetDirectory = p.join(rootPath, directoryName);
    final targetType = FileSystemEntity.typeSync(
      targetDirectory,
      followLinks: false,
    );

    final rows = await _loadCanonicalBrowseRecords(comicTitle);
    dynamic matched;
    final normalizedTitle = _normalizeTitle(comicTitle);
    for (final row in rows) {
      final recordTitle = row.title?.toString() ?? '';
      final recordNormalized = row.normalizedTitle?.toString() ?? '';
      if (_normalizeTitle(recordTitle) == normalizedTitle ||
          _normalizeTitle(recordNormalized) == normalizedTitle) {
        matched = row;
        break;
      }
    }

    if (matched != null) {
      final primaryItem = await App.repositories.localLibrary
          .loadPrimaryLocalLibraryItem(matched.comicId.toString());
      if (primaryItem != null) {
        final probeResult = fileProbe.probe(
          canonicalRootPath: primaryItem.localRootPath,
          comicDirectoryName: directoryName,
          preferredExpectedDirectory: primaryItem.localRootPath,
        );
        if (probeResult.isAvailable) {
          return LocalImportPreflightDecision(
            action: LocalImportPreflightAction.conflictExistingCanonicalRecord,
            targetDirectory: primaryItem.localRootPath,
            existingComicId: matched.comicId.toString(),
          );
        }
        if (probeResult.isCleanupCandidate) {
          return LocalImportPreflightDecision(
            action: LocalImportPreflightAction.repairExisting,
            targetDirectory: primaryItem.localRootPath,
            existingComicId: matched.comicId.toString(),
          );
        }
      }
      return LocalImportPreflightDecision(
        action: LocalImportPreflightAction.conflictExistingCanonicalRecord,
        targetDirectory: targetDirectory,
        existingComicId: matched.comicId.toString(),
      );
    }

    if (targetType == FileSystemEntityType.directory ||
        targetType == FileSystemEntityType.file ||
        targetType == FileSystemEntityType.link) {
      return LocalImportPreflightDecision(
        action: LocalImportPreflightAction.conflictExistingDirectory,
        targetDirectory: targetDirectory,
      );
    }

    return LocalImportPreflightDecision(
      action: LocalImportPreflightAction.createNew,
      targetDirectory: targetDirectory,
    );
  }

  @override
  Future<LocalComic> registerImportedComic(
    LocalComic comic, {
    String? existingComicId,
  }) async {
    final id = existingComicId ?? await _allocateComicId();
    final registeredComic = LocalComic(
      id: id,
      title: comic.title,
      subtitle: comic.subtitle,
      tags: comic.tags,
      directory: comic.directory,
      chapters: comic.chapters,
      cover: comic.cover,
      comicType: comic.comicType,
      downloadedChapters: comic.downloadedChapters,
      createdAt: comic.createdAt,
    );
    await (syncComic ??
        (LocalComic comic) => LocalComicCanonicalSyncService(
          store: App.unifiedComicsStore,
        ).syncComic(comic))(registeredComic);
    if (enableLegacyMigrationMirror) {
      try {
        final rootPath = await requireRootPath();
        await legacyMigrationMirror?.call(registeredComic, rootPath);
      } catch (error) {
        AppDiagnostics.warn(
          'import.local',
          'import.local.legacyMirrorFailed',
          data: {
            'comicTitle': registeredComic.title,
            'authority': 'legacy_local_db',
            'error': error.toString(),
          },
        );
      }
    }
    return registeredComic;
  }
}

Future<String> _resolveCanonicalRootPath() async {
  final persistedPathFile = File(
    '${App.dataPath}${Platform.pathSeparator}local_path',
  );
  if (persistedPathFile.existsSync()) {
    final persistedPath = persistedPathFile.readAsStringSync().trim();
    if (persistedPath.isNotEmpty) {
      return persistedPath;
    }
  }
  return '${App.dataPath}${Platform.pathSeparator}local';
}
