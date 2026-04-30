import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/reader_debug_snapshot.dart';

void main() {
  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'venera-reader-debug-snapshot-test-',
    );
    store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('snapshot exposes canonical local reader identifiers', () async {
    await _insertCanonicalReaderFixture(store);

    final snapshot = await ReaderDebugSnapshotService(store: store).build(
      comicId: 'comic-1',
      chapterId: 'chapter-1',
      loadMode: 'local',
      controllerLifecycle: 'open',
    );

    expect(snapshot.comicId, 'comic-1');
    expect(snapshot.localLibraryItemId, 'local_item:comic-1');
    expect(snapshot.pageOrderId, 'order-1');
    expect(snapshot.chapterId, 'chapter-1');
    expect(snapshot.loadMode, 'local');
    expect(snapshot.controllerLifecycle, 'open');
    expect(snapshot.toJson()['comicId'], 'comic-1');
  });

  test('snapshot fails loudly when canonical comic is missing', () async {
    await expectLater(
      ReaderDebugSnapshotService(store: store).build(
        comicId: 'missing',
        chapterId: 'chapter-1',
        loadMode: 'local',
        controllerLifecycle: 'open',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('snapshot fails loudly when active page order is missing', () async {
    await _insertCanonicalReaderFixture(store, includePageOrder: false);

    await expectLater(
      ReaderDebugSnapshotService(store: store).build(
        comicId: 'comic-1',
        chapterId: 'chapter-1',
        loadMode: 'local',
        controllerLifecycle: 'open',
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _insertCanonicalReaderFixture(
  UnifiedComicsStore store, {
  bool includePageOrder = true,
}) async {
  await store.upsertComic(
    const ComicRecord(
      id: 'comic-1',
      title: 'Comic One',
      normalizedTitle: 'comic one',
    ),
  );
  await store.upsertLocalLibraryItem(
    const LocalLibraryItemRecord(
      id: 'local_item:comic-1',
      comicId: 'comic-1',
      storageType: 'user_imported',
      localRootPath: '/library/comic-1',
    ),
  );
  await store.upsertChapter(
    const ChapterRecord(
      id: 'chapter-1',
      comicId: 'comic-1',
      chapterNo: 1,
      title: 'Chapter 1',
      normalizedTitle: 'chapter 1',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'page-1',
      chapterId: 'chapter-1',
      pageIndex: 0,
      localPath: '/library/comic-1/1.png',
    ),
  );
  if (!includePageOrder) {
    return;
  }
  await store.upsertPageOrder(
    const PageOrderRecord(
      id: 'order-1',
      chapterId: 'chapter-1',
      orderName: 'Source Default',
      normalizedOrderName: 'source default',
      orderType: 'source_default',
      isActive: true,
    ),
  );
  await store.replacePageOrderItems('order-1', const [
    PageOrderItemRecord(pageOrderId: 'order-1', pageId: 'page-1', sortOrder: 0),
  ]);
}
