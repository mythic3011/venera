import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'venera-remote-comic-sync-test-',
    );
    store = UnifiedComicsStore('${tempDir.path}/unified_comics.db');
    await store.init();
    await store.seedDefaultSourcePlatforms();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'syncComic writes canonical remote comic citation and scoped tags',
    () async {
      final detail = ComicDetails.fromJson({
        'title': 'Remote Comic',
        'subtitle': 'Uploader',
        'cover': 'https://example.com/cover.jpg',
        'description': 'desc',
        'tags': {
          'artist': ['Alice'],
          'group': ['Circle'],
        },
        'chapters': {'chapter-1': 'Opening', 'chapter-2': 'Ending'},
        'sourceKey': 'picacg',
        'comicId': 'abc123',
        'thumbnails': null,
        'recommend': null,
        'isFavorite': false,
        'subId': null,
        'likesCount': 1,
        'isLiked': false,
        'commentCount': 2,
        'uploader': 'Uploader',
        'uploadTime': '2026-04-29',
        'updateTime': '2026-04-30T02:03:04Z',
        'url': 'https://example.com/comic/abc123',
        'stars': 4.5,
        'maxPage': 12,
        'comments': null,
      });

      final canonicalId = await RemoteComicCanonicalSyncService(
        store: store,
      ).syncComic(detail);

      expect(canonicalId, 'remote:picacg:abc123');

      final snapshot = await store.loadComicSnapshot(canonicalId);
      expect(snapshot?.comic.title, 'Remote Comic');

      final links = await store.loadComicSourceLinks(canonicalId);
      expect(links, hasLength(1));
      expect(links.single.sourcePlatformId, 'picacg');
      expect(links.single.sourceComicId, 'abc123');
      expect(links.single.sourceUrl, 'https://example.com/comic/abc123');
      expect(links.single.sourceTitle, 'Remote Comic');

      final tags = await store.loadSourceTagsForComicSourceLink(
        links.single.id,
      );
      final chapterSourceLinks = await store
          .loadChapterSourceLinksForComicSourceLink(links.single.id);
      expect(
        tags.map((tag) => '${tag.namespace}:${tag.displayName}').toList(),
        ['artist:Alice', 'group:Circle'],
      );
      expect(chapterSourceLinks.map((link) => link.sourceChapterId).toList(), [
        'chapter-1',
        'chapter-2',
      ]);
      expect(
        (await store.loadComicSnapshot(
          canonicalId,
        ))?.chapters.map((c) => c.id).toList(),
        ['remote:picacg:abc123:chapter-1', 'remote:picacg:abc123:chapter-2'],
      );
    },
  );

  test('syncComic ensures source platform and comic parent exist before title rows', () async {
    final detail = ComicDetails.fromJson({
      'title': 'Copy Manga Comic',
      'subtitle': 'Uploader',
      'cover': 'https://example.com/cover.jpg',
      'description': 'desc',
      'tags': <String, List<String>>{},
      'chapters': {'chapter-1': 'Opening'},
      'sourceKey': 'copy_manga',
      'comicId': 'weibijianzhimengmianhongerchi',
      'thumbnails': null,
      'recommend': null,
      'isFavorite': false,
      'subId': null,
      'likesCount': 0,
      'isLiked': false,
      'commentCount': 0,
      'uploader': 'Uploader',
      'uploadTime': null,
      'updateTime': null,
      'url': null,
      'stars': null,
      'maxPage': null,
      'comments': null,
    });

    final canonicalId = await RemoteComicCanonicalSyncService(
      store: store,
    ).syncComic(detail);

    final platform = await store.loadSourcePlatformById('copy_manga');
    expect(platform, isNotNull);

    final snapshot = await store.loadComicSnapshot(canonicalId);
    expect(snapshot, isNotNull);

    final titleRows = await store.customSelect(
      'SELECT COUNT(*) AS c FROM comic_titles WHERE comic_id = ?;',
      variables: [Variable<String>(canonicalId)],
    ).getSingle();
    expect(titleRows.read<int>('c'), greaterThan(0));

    final foreignKeyRows = await store.customSelect(
      'PRAGMA foreign_key_check;',
    ).get();
    expect(foreignKeyRows, isEmpty);
  });

  test('syncComic normalizes sourceKey consistently for platform, comic, and title FK', () async {
    final detail = ComicDetails.fromJson({
      'title': 'Whitespace Source Key Comic',
      'subtitle': null,
      'cover': '',
      'description': '',
      'tags': <String, List<String>>{},
      'chapters': {'chapter-1': 'Opening'},
      'sourceKey': ' copy_manga ',
      'comicId': 'wueyxingxuanlv',
      'thumbnails': null,
      'recommend': null,
      'isFavorite': false,
      'subId': null,
      'likesCount': 0,
      'isLiked': false,
      'commentCount': 0,
      'uploader': null,
      'uploadTime': null,
      'updateTime': null,
      'url': null,
      'stars': null,
      'maxPage': null,
      'comments': null,
    });

    final canonicalId = await RemoteComicCanonicalSyncService(
      store: store,
    ).syncComic(detail);
    expect(canonicalId, 'remote:copy_manga:wueyxingxuanlv');

    final platform = await store.loadSourcePlatformById('copy_manga');
    expect(platform, isNotNull);

    final sourceLinkRow = await store.customSelect(
      '''
      SELECT source_platform_id, source_comic_id
      FROM comic_source_links
      WHERE comic_id = ?
      LIMIT 1;
      ''',
      variables: [Variable<String>(canonicalId)],
    ).getSingle();
    expect(sourceLinkRow.read<String>('source_platform_id'), 'copy_manga');
    expect(sourceLinkRow.read<String>('source_comic_id'), 'wueyxingxuanlv');

    final titleRow = await store.customSelect(
      '''
      SELECT source_platform_id
      FROM comic_titles
      WHERE comic_id = ?
      LIMIT 1;
      ''',
      variables: [Variable<String>(canonicalId)],
    ).getSingle();
    expect(titleRow.read<String?>('source_platform_id'), 'copy_manga');

    final foreignKeyRows = await store.customSelect(
      'PRAGMA foreign_key_check;',
    ).get();
    expect(foreignKeyRows, isEmpty);
  });

  test('syncComic rolls back child writes when parent comic insert fails', () async {
    const canonicalId = 'remote:copy_manga:fk-rollback';
    await store.customStatement('''
      CREATE TRIGGER fail_remote_comic_insert
      BEFORE INSERT ON comics
      WHEN NEW.id = '$canonicalId'
      BEGIN
        SELECT RAISE(ABORT, 'forced comics insert failure');
      END;
    ''');

    final detail = ComicDetails.fromJson({
      'title': 'Rollback Comic',
      'subtitle': null,
      'cover': '',
      'description': '',
      'tags': <String, List<String>>{},
      'chapters': <String, String>{},
      'sourceKey': 'copy_manga',
      'comicId': 'fk-rollback',
      'thumbnails': null,
      'recommend': null,
      'isFavorite': false,
      'subId': null,
      'likesCount': 0,
      'isLiked': false,
      'commentCount': 0,
      'uploader': null,
      'uploadTime': null,
      'updateTime': null,
      'url': null,
      'stars': null,
      'maxPage': null,
      'comments': null,
    });

    final service = RemoteComicCanonicalSyncService(store: store);
    await expectLater(service.syncComic(detail), throwsA(isA<Exception>()));

    final comicRows = await store.customSelect(
      'SELECT COUNT(*) AS c FROM comics WHERE id = ?;',
      variables: [const Variable<String>(canonicalId)],
    ).getSingle();
    expect(comicRows.read<int>('c'), 0);

    final titleRows = await store.customSelect(
      'SELECT COUNT(*) AS c FROM comic_titles WHERE comic_id = ?;',
      variables: [const Variable<String>(canonicalId)],
    ).getSingle();
    expect(titleRows.read<int>('c'), 0);
  });

  test('syncComic is idempotent for title upsert and keeps FK consistency', () async {
    final detail = ComicDetails.fromJson({
      'title': 'Idempotent Comic',
      'subtitle': 'Uploader',
      'cover': '',
      'description': '',
      'tags': <String, List<String>>{},
      'chapters': {'chapter-1': 'Opening'},
      'sourceKey': 'copy_manga',
      'comicId': 'idempotent-1',
      'thumbnails': null,
      'recommend': null,
      'isFavorite': false,
      'subId': null,
      'likesCount': 0,
      'isLiked': false,
      'commentCount': 0,
      'uploader': null,
      'uploadTime': null,
      'updateTime': null,
      'url': null,
      'stars': null,
      'maxPage': null,
      'comments': null,
    });

    final service = RemoteComicCanonicalSyncService(store: store);
    final canonicalId = await service.syncComic(detail);
    await service.syncComic(detail);

    final titleRows = await store.customSelect(
      '''
      SELECT COUNT(*) AS c
      FROM comic_titles
      WHERE comic_id = ?
        AND title_type = ?
        AND source_platform_id = ?;
      ''',
      variables: [
        Variable<String>(canonicalId),
        const Variable<String>('primary'),
        const Variable<String>('copy_manga'),
      ],
    ).getSingle();
    expect(titleRows.read<int>('c'), 1);

    final foreignKeyRows = await store.customSelect(
      'PRAGMA foreign_key_check;',
    ).get();
    expect(foreignKeyRows, isEmpty);
  });

  test('syncComic rejects empty normalized sourceKey', () async {
    final detail = ComicDetails.fromJson({
      'title': 'Invalid Source Key Comic',
      'subtitle': null,
      'cover': '',
      'description': '',
      'tags': <String, List<String>>{},
      'chapters': {'chapter-1': 'Opening'},
      'sourceKey': '   ',
      'comicId': 'invalid-source',
      'thumbnails': null,
      'recommend': null,
      'isFavorite': false,
      'subId': null,
      'likesCount': 0,
      'isLiked': false,
      'commentCount': 0,
      'uploader': null,
      'uploadTime': null,
      'updateTime': null,
      'url': null,
      'stars': null,
      'maxPage': null,
      'comments': null,
    });

    final service = RemoteComicCanonicalSyncService(store: store);
    await expectLater(
      service.syncComic(detail),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('sourceKey must not be empty'),
        ),
      ),
    );
  });

  test('syncComic regression: copy_manga wueyxingxuanlv inserts title without FK violation', () async {
    final detail = ComicDetails.fromJson({
      'title': '午夜心旋律',
      'subtitle': null,
      'cover': '',
      'description': '',
      'tags': <String, List<String>>{},
      'chapters': {'1': 'Chapter 1'},
      'sourceKey': 'copy_manga',
      'comicId': 'wueyxingxuanlv',
      'thumbnails': null,
      'recommend': null,
      'isFavorite': false,
      'subId': null,
      'likesCount': 0,
      'isLiked': false,
      'commentCount': 0,
      'uploader': null,
      'uploadTime': null,
      'updateTime': null,
      'url': null,
      'stars': null,
      'maxPage': null,
      'comments': null,
    });

    final canonicalId = await RemoteComicCanonicalSyncService(
      store: store,
    ).syncComic(detail);
    expect(canonicalId, 'remote:copy_manga:wueyxingxuanlv');

    final titleRow = await store.customSelect(
      '''
      SELECT comic_id, source_platform_id, title
      FROM comic_titles
      WHERE comic_id = ?
      LIMIT 1;
      ''',
      variables: [Variable<String>(canonicalId)],
    ).getSingle();
    expect(titleRow.read<String>('comic_id'), canonicalId);
    expect(titleRow.read<String?>('source_platform_id'), 'copy_manga');
    expect(titleRow.read<String>('title'), '午夜心旋律');

    final foreignKeyRows = await store.customSelect(
      'PRAGMA foreign_key_check;',
    ).get();
    expect(foreignKeyRows, isEmpty);
  });

  test(
    'syncChapterPages writes canonical remote pages and page source links',
    () async {
      final service = RemoteComicCanonicalSyncService(store: store);

      await service.syncChapterPages(
        sourceKey: 'picacg',
        comicId: 'abc123',
        chapterId: 'chapter-1',
        pageKeys: const [
          'https://img.example/1.jpg',
          'https://img.example/2.jpg',
        ],
      );

      final canonicalId = 'remote:picacg:abc123';
      final links = await store.loadComicSourceLinks(canonicalId);
      expect(links, hasLength(1));
      expect(links.single.sourceComicId, 'abc123');

      final chapterSourceLinks = await store
          .loadChapterSourceLinksForComicSourceLink(links.single.id);
      expect(chapterSourceLinks, hasLength(1));
      expect(chapterSourceLinks.single.sourceChapterId, 'chapter-1');

      final pageSourceLinks = await store.loadPageSourceLinksForComicSourceLink(
        links.single.id,
      );
      expect(pageSourceLinks, hasLength(2));
      expect(pageSourceLinks.map((link) => link.sourceUrl).toList(), [
        'https://img.example/1.jpg',
        'https://img.example/2.jpg',
      ]);

      final pages = await store.loadActivePageOrderPages(
        'remote:picacg:abc123:chapter-1',
      );
      expect(pages.map((page) => page.localPath).toList(), [
        'https://img.example/1.jpg',
        'https://img.example/2.jpg',
      ]);
    },
  );

  test(
    'syncChapterPages is idempotent and replaces stale chapter page rows',
    () async {
      final service = RemoteComicCanonicalSyncService(store: store);

      await service.syncChapterPages(
        sourceKey: 'picacg',
        comicId: 'abc123',
        chapterId: 'chapter-1',
        pageKeys: const [
          'https://img.example/1.jpg',
          'https://img.example/2.jpg',
          'https://img.example/3.jpg',
        ],
      );

      await service.syncChapterPages(
        sourceKey: 'picacg',
        comicId: 'abc123',
        chapterId: 'chapter-1',
        pageKeys: const [
          'https://img.example/10.jpg',
          'https://img.example/20.jpg',
        ],
      );

      final chapterId = 'remote:picacg:abc123:chapter-1';
      final pages = await store.loadActivePageOrderPages(chapterId);
      expect(pages.map((page) => page.localPath).toList(), [
        'https://img.example/10.jpg',
        'https://img.example/20.jpg',
      ]);
      expect(pages.map((page) => page.id).toList(), [
        '$chapterId:0',
        '$chapterId:1',
      ]);

      final pageSourceLinks = await store.loadPageSourceLinksForComicSourceLink(
        'source_link:remote:picacg:abc123',
      );
      expect(pageSourceLinks, hasLength(2));
      expect(pageSourceLinks.map((link) => link.sourceUrl).toList(), [
        'https://img.example/10.jpg',
        'https://img.example/20.jpg',
      ]);
    },
  );

  test(
    'page source links stay scoped to comic and chapter source links',
    () async {
      final service = RemoteComicCanonicalSyncService(store: store);
      await service.syncChapterPages(
        sourceKey: 'picacg',
        comicId: 'abc123',
        chapterId: 'chapter-1',
        pageKeys: const ['https://img.example/1.jpg'],
      );
      await service.syncChapterPages(
        sourceKey: 'picacg',
        comicId: 'abc123',
        chapterId: 'chapter-2',
        pageKeys: const ['https://img.example/2.jpg'],
      );
      await service.syncChapterPages(
        sourceKey: 'ehentai',
        comicId: 'abc123',
        chapterId: 'chapter-1',
        pageKeys: const ['https://img.example/e1.jpg'],
      );

      final picaLinks = await store.loadPageSourceLinksForComicSourceLink(
        'source_link:remote:picacg:abc123',
      );
      expect(picaLinks, hasLength(2));
      expect(picaLinks.map((link) => link.chapterSourceLinkId).toSet(), {
        'source_link:remote:picacg:abc123:chapter:chapter-1',
        'source_link:remote:picacg:abc123:chapter:chapter-2',
      });

      final ehLinks = await store.loadPageSourceLinksForComicSourceLink(
        'source_link:remote:ehentai:abc123',
      );
      expect(ehLinks, hasLength(1));
      expect(
        ehLinks.single.chapterSourceLinkId,
        'source_link:remote:ehentai:abc123:chapter:chapter-1',
      );
    },
  );
}
