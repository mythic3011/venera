import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/features/reader/data/reader_activity_repository.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/pages/home_page.dart';

void main() {
  Future<UnifiedComicsStore> createStore(Directory tempDir) async {
    final store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-a',
        title: 'Comic A',
        normalizedTitle: 'comic a',
      ),
    );
    return store;
  }

  void expectNoLegacyRuntimeFiles(Directory tempDir) {
    expect(File(p.join(tempDir.path, 'history.db')).existsSync(), isFalse);
    expect(File(p.join(tempDir.path, 'implicitData.json')).existsSync(), isFalse);
  }

  test('home history snapshot reads canonical activity without legacy init', () async {
    final tempDir = await Directory.systemTemp.createTemp('home-history-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final store = await createStore(tempDir);
    addTearDown(store.close);

    await ReaderSessionRepository(store: store).upsertCurrentLocation(
      comicId: 'comic-a',
      chapterId: 'chapter-1',
      pageIndex: 5,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-home-source',
      ),
    );

    final snapshot = await loadHomeReaderActivitySnapshot(
      ReaderActivityRepository(store: store),
    );

    expect(snapshot.count, 1);
    expect(snapshot.recent, hasLength(1));
    expect(snapshot.recent.single.comicId, 'comic-a');
    expect(snapshot.recent.single.sourceKey, 'remote-home-source');
    expectNoLegacyRuntimeFiles(tempDir);
  });
}
