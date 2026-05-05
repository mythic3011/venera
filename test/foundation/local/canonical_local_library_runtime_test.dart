import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local/canonical_local_library_runtime.dart';

void main() {
  late Directory tempDir;
  late Directory localRoot;
  late UnifiedComicsStore store;
  late CanonicalLocalLibraryRuntimeService service;
  var nextId = 1;

  Future<LocalComic> registerImportedComic(
    LocalComic comic, {
    String? existingComicId,
  }) async {
    final resolvedId = existingComicId ?? 'generated-${nextId++}';
    final resolvedComic = LocalComic(
      id: resolvedId,
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
    await LocalComicCanonicalSyncService(
      store: store,
      resolveCanonicalLocalRootPath: () async => localRoot.path,
    ).syncComic(resolvedComic);
    return resolvedComic;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('canonical-local-runtime-');
    localRoot = Directory(p.join(tempDir.path, 'runtimeRoot', 'local'))
      ..createSync(recursive: true);
    store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    await store.seedDefaultSourcePlatforms();
    nextId = 1;
    AppDiagnostics.configureSinksForTesting(const []);
    service = CanonicalLocalLibraryRuntimeService(
      store: store,
      resolveRootPath: () async => localRoot.path,
      registerImportedComic: registerImportedComic,
    );
  });

  tearDown(() async {
    AppDiagnostics.resetForTesting();
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('recheck creates canonical row for discovered runtimeRoot folder', () async {
    final folder = Directory(p.join(localRoot.path, 'DYE1-1'))
      ..createSync(recursive: true);
    File(p.join(folder.path, '1.jpg')).writeAsBytesSync(<int>[1]);

    final created = await service.recheck();
    final comics = await service.loadAvailableComics();

    expect(created, 1);
    expect(comics, hasLength(1));
    expect(comics.single.title, 'DYE1-1');
    expect(comics.single.id, 'generated-1');
    expect(comics.single.directory, folder.path);
    final event = DevDiagnosticsApi.recent(channel: 'local.library')
        .singleWhere(
          (entry) => entry.message == 'local.library.canonicalFolderDiscovered',
        );
    expect(event.data['discoveredDirectoryName'], 'DYE1-1');
    expect(event.data['action'], 'create');
  });

  test('recheck relinks stale canonical directory to existing folder safely', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-1',
        title: 'DYE1-2',
        normalizedTitle: 'dye1-2',
      ),
    );
    await store.upsertLocalLibraryItem(
      LocalLibraryItemRecord(
        id: 'local-item:comic-1',
        comicId: 'comic-1',
        storageType: 'user_imported',
        localRootPath: p.join(localRoot.path, 'stale-folder'),
        importedAt: DateTime.utc(2026, 5, 5).toIso8601String(),
        updatedAt: DateTime.utc(2026, 5, 5).toIso8601String(),
      ),
    );
    final folder = Directory(p.join(localRoot.path, 'DYE1-2'))
      ..createSync(recursive: true);
    File(p.join(folder.path, '1.jpg')).writeAsBytesSync(<int>[1]);

    final created = await service.recheck();
    final comics = await service.loadAvailableComics();
    final item = await store.loadPrimaryLocalLibraryItem('comic-1');

    expect(created, 0);
    expect(item, isNotNull);
    expect(item!.localRootPath, folder.path);
    expect(comics.map((comic) => comic.id), contains('comic-1'));
    expect(
      DevDiagnosticsApi.recent(channel: 'local.library').any(
        (entry) => entry.message == 'local.library.canonicalRelinked',
      ),
      isTrue,
    );
    expect(
      DevDiagnosticsApi.recent(channel: 'local.library').any(
        (entry) => entry.message == 'local.library.missingCanonicalItem',
      ),
      isFalse,
    );
  });

  test('missing canonical folder remains hidden and emits missingCanonicalItem', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-missing',
        title: 'Missing Comic',
        normalizedTitle: 'missing comic',
      ),
    );
    await store.upsertLocalLibraryItem(
      LocalLibraryItemRecord(
        id: 'local-item:missing',
        comicId: 'comic-missing',
        storageType: 'user_imported',
        localRootPath: p.join(localRoot.path, 'Missing Comic'),
      ),
    );

    final comics = await service.loadAvailableComics();

    expect(comics, isEmpty);
    final event = DevDiagnosticsApi.recent(channel: 'local.library')
        .singleWhere(
          (entry) => entry.message == 'local.library.missingCanonicalItem',
        );
    expect(event.data['comicId'], 'comic-missing');
    expect(event.data['storedDirectoryName'], 'Missing Comic');
    expect(event.data['action'], 'hide');
  });
}
