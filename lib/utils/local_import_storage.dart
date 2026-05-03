import 'dart:async';
import 'dart:io';

import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';

abstract class LocalImportStoragePort {
  Future<void> assertStorageReadyForImport(String comicTitle);
  Future<bool> hasDuplicateTitle(String title);
  Future<String> requireRootPath();
  Future<LocalComic> registerImportedComic(LocalComic comic);
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
    AppDiagnostics.warn(
      'import.local',
      'import.local.legacyBlocked',
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
  Future<LocalComic> registerImportedComic(LocalComic comic) async {
    final id = await _allocateComicId();
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
