import 'dart:io';

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
