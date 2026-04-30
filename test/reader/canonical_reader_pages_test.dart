import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/canonical_reader_pages.dart';

void main() {
  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'venera-canonical-reader-pages-test-',
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

  test('loads local reader pages from canonical active page order', () async {
    await _insertCanonicalComicFixture(store);

    final pages = await CanonicalReaderPages(
      store: store,
    ).loadLocalPages(localComicId: 'comic-1', chapterId: 'chapter-1');

    expect(pages, [
      Uri.file('/library/comic-1/1.png').toString(),
      Uri.file('/library/comic-1/2.png').toString(),
    ]);
  });

  test('uses first canonical chapter when no chapter id is supplied', () async {
    await _insertCanonicalComicFixture(store);

    final pages = await CanonicalReaderPages(
      store: store,
    ).loadLocalPages(localComicId: 'comic-1');

    expect(pages, [
      Uri.file('/library/comic-1/1.png').toString(),
      Uri.file('/library/comic-1/2.png').toString(),
    ]);
  });

  test('fails when canonical local comic is missing', () async {
    await expectLater(
      CanonicalReaderPages(
        store: store,
      ).loadLocalPages(localComicId: 'missing', chapterId: 'chapter-1'),
      throwsA(isA<StateError>()),
    );
  });

  test('fails when chapter has no active canonical page order', () async {
    await _insertCanonicalComicFixture(store, includePageOrder: false);

    await expectLater(
      CanonicalReaderPages(
        store: store,
      ).loadLocalPages(localComicId: 'comic-1', chapterId: 'chapter-1'),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _insertCanonicalComicFixture(
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
      id: 'page-a',
      chapterId: 'chapter-1',
      pageIndex: 0,
      localPath: '/library/comic-1/2.png',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'page-b',
      chapterId: 'chapter-1',
      pageIndex: 1,
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
    PageOrderItemRecord(pageOrderId: 'order-1', pageId: 'page-b', sortOrder: 0),
    PageOrderItemRecord(pageOrderId: 'order-1', pageId: 'page-a', sortOrder: 1),
  ]);
}
