import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/res.dart';

void main() {
  test('static repository returns mapped detail for comic id', () async {
    final repository = StaticComicDetailRepository({
      'comic-1': ComicDetailViewModel.scaffold(
        comicId: 'comic-1',
        title: 'Mapped',
        libraryState: LibraryState.downloaded,
      ),
    });

    final detail = await repository.getComicDetail('comic-1');

    expect(detail, isNotNull);
    expect(detail!.title, 'Mapped');
    expect(detail.libraryState, LibraryState.downloaded);
  });

  test(
    'composite repository returns first non-null detail from loaders',
    () async {
      final calls = <String>[];
      final repository = CompositeComicDetailRepository(
        loaders: [
          (comicId) async {
            calls.add('first:$comicId');
            return null;
          },
          (comicId) async {
            calls.add('second:$comicId');
            return ComicDetailViewModel.scaffold(
              comicId: comicId,
              title: 'Resolved',
              libraryState: LibraryState.localWithRemoteSource,
            );
          },
          (comicId) async {
            calls.add('third:$comicId');
            return ComicDetailViewModel.scaffold(
              comicId: comicId,
              title: 'Unexpected',
              libraryState: LibraryState.unavailable,
            );
          },
        ],
      );

      final detail = await repository.getComicDetail('comic-9');

      expect(detail, isNotNull);
      expect(detail!.title, 'Resolved');
      expect(calls, ['first:comic-9', 'second:comic-9']);
    },
  );

  test(
    'stub repository provides conservative unavailable placeholder',
    () async {
      const repository = StubComicDetailRepository();

      final detail = await repository.getComicDetail('missing-comic');

      expect(detail, isNotNull);
      expect(detail!.comicId, 'missing-comic');
      expect(detail.title, 'missing-comic');
      expect(detail.libraryState, LibraryState.unavailable);
      expect(detail.availableActions.hasAnyAction, isFalse);
    },
  );

  test(
    'unified local repository reads canonical store detail surface',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-1',
          title: 'Canonical Local',
          normalizedTitle: 'canonical local',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-1',
          title: 'Canonical Local',
          normalizedTitle: 'canonical local',
          titleType: 'primary',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-1',
          comicId: 'comic-1',
          storageType: 'downloaded',
          localRootPath: '/tmp/local-1',
        ),
      );
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'ehentai',
          canonicalKey: 'ehentai',
          displayName: 'E-Hentai',
          kind: 'remote',
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'source-link-1',
          comicId: 'comic-1',
          sourcePlatformId: 'ehentai',
          sourceComicId: '12345',
          isPrimary: true,
          sourceUrl: 'https://e-hentai.org/g/12345',
          sourceTitle: 'Remote Canonical Local',
          downloadedAt: '2026-04-30T10:00:00.000Z',
          lastVerifiedAt: '2026-04-30T12:00:00.000Z',
        ),
      );
      await store.upsertSourceTag(
        const SourceTagRecord(
          id: 'source-tag-1',
          sourcePlatformId: 'ehentai',
          namespace: 'female',
          tagKey: 'glasses',
          displayName: 'glasses',
        ),
      );
      await store.attachSourceTagToComicSourceLink(
        const ComicSourceLinkTagRecord(
          comicSourceLinkId: 'source-link-1',
          sourceTagId: 'source-tag-1',
        ),
      );
      await store.upsertUserTag(
        const UserTagRecord(
          id: 'user-tag-1',
          name: 'queued',
          normalizedName: 'queued',
        ),
      );
      await store.attachUserTagToComic(
        const ComicUserTagRecord(comicId: 'comic-1', userTagId: 'user-tag-1'),
      );
      await store.upsertChapter(
        const ChapterRecord(
          id: 'chapter-1',
          comicId: 'comic-1',
          chapterNo: 1,
          title: 'Imported',
          normalizedTitle: 'imported',
        ),
      );
      await store.upsertPage(
        const PageRecord(
          id: 'page-1',
          chapterId: 'chapter-1',
          pageIndex: 0,
          localPath: '/tmp/local-1/1.jpg',
        ),
      );
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
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'page-1',
          sortOrder: 0,
        ),
      ]);
      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'history-1',
          comicId: 'comic-1',
          sourceTypeValue: 0,
          sourceKey: 'local',
          title: 'Canonical Local',
          subtitle: '',
          cover: '',
          eventTime: '2026-04-30T12:00:00.000Z',
          chapterIndex: 1,
          pageIndex: 3,
          readEpisode: '1',
        ),
      );

      final repository = UnifiedLocalComicDetailRepository(store: store);
      final detail = await repository.getComicDetail('comic-1');

      expect(detail, isNotNull);
      expect(detail!.libraryState, LibraryState.downloaded);
      expect(detail.primarySource, isNotNull);
      expect(detail.primarySource?.platformName, 'E-Hentai');
      expect(detail.primarySource?.comicUrl, 'https://e-hentai.org/g/12345');
      expect(detail.primarySource?.sourceTitle, 'Remote Canonical Local');
      expect(detail.sourceTags.single.name, 'glasses');
      expect(detail.sourceTags.single.namespace, 'female');
      expect(detail.userTags.single.name, 'queued');
      expect(detail.availableActions.canViewSource, isTrue);
      expect(detail.availableActions.canContinueReading, isTrue);
      expect(detail.chapters.single.title, 'Imported');
      expect(detail.chapters.single.lastReadAt, isNotNull);
      expect(detail.updatedAt, isNotNull);
      expect(
        detail.pageOrderSummary.activeOrderType,
        PageOrderKind.sourceDefault,
      );
      expect(detail.pageOrderSummary.totalPageCount, 1);
      expect(detail.availableActions.canManagePageOrder, isTrue);
    },
  );

  test(
    'unified local repository returns not-linked local comic when provenance is absent',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-no-source',
          title: 'No Source',
          normalizedTitle: 'no source',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-no-source',
          comicId: 'comic-no-source',
          storageType: 'user_imported',
          localRootPath: '/tmp/no-source',
        ),
      );

      final repository = UnifiedLocalComicDetailRepository(store: store);
      final detail = await repository.getComicDetail('comic-no-source');

      expect(detail, isNotNull);
      expect(detail!.libraryState, LibraryState.localOnly);
      expect(detail.primarySource, isNull);
      expect(detail.availableActions.canViewSource, isFalse);
    },
  );

  test(
    'unified local repository does not match fractional chapter numbers to integer history',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-2',
          title: 'Fractional Chapter',
          normalizedTitle: 'fractional chapter',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-2',
          title: 'Fractional Chapter',
          normalizedTitle: 'fractional chapter',
          titleType: 'primary',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-2',
          comicId: 'comic-2',
          storageType: 'user_imported',
          localRootPath: '/tmp/local-2',
        ),
      );
      await store.upsertChapter(
        const ChapterRecord(
          id: 'chapter-2',
          comicId: 'comic-2',
          chapterNo: 1.5,
          title: 'Chapter 1.5',
          normalizedTitle: 'chapter 1.5',
        ),
      );
      await store.upsertPage(
        const PageRecord(
          id: 'page-2',
          chapterId: 'chapter-2',
          pageIndex: 0,
          localPath: '/tmp/local-2/1.jpg',
        ),
      );
      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'history-2',
          comicId: 'comic-2',
          sourceTypeValue: 0,
          sourceKey: 'local',
          title: 'Fractional Chapter',
          subtitle: '',
          cover: '',
          eventTime: '2026-04-30T12:00:00.000Z',
          chapterIndex: 1,
          pageIndex: 0,
          readEpisode: '1',
        ),
      );

      final repository = UnifiedLocalComicDetailRepository(store: store);
      final detail = await repository.getComicDetail('comic-2');

      expect(detail, isNotNull);
      expect(detail!.availableActions.canContinueReading, isTrue);
      expect(detail.chapters.single.lastReadAt, isNull);
    },
  );

  test(
    'unified canonical repository returns remote-only metadata surface',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.upsertComic(
        const ComicRecord(
          id: 'remote:picacg:abc123',
          title: 'Remote Canonical',
          normalizedTitle: 'remote canonical',
        ),
      );
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'picacg',
          canonicalKey: 'picacg',
          displayName: 'PicACG',
          kind: 'remote',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'remote:picacg:abc123',
          title: 'Remote Canonical',
          normalizedTitle: 'remote canonical',
          titleType: 'primary',
          sourcePlatformId: 'picacg',
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'remote-link-1',
          comicId: 'remote:picacg:abc123',
          sourcePlatformId: 'picacg',
          sourceComicId: 'abc123',
          isPrimary: true,
          sourceUrl: 'https://example.com/comic/abc123',
          sourceTitle: 'Remote Canonical Source',
        ),
      );
      await store.upsertSourceTag(
        const SourceTagRecord(
          id: 'remote-source-tag-1',
          sourcePlatformId: 'picacg',
          namespace: 'artist',
          tagKey: 'alice',
          displayName: 'Alice',
        ),
      );
      await store.attachSourceTagToComicSourceLink(
        const ComicSourceLinkTagRecord(
          comicSourceLinkId: 'remote-link-1',
          sourceTagId: 'remote-source-tag-1',
        ),
      );
      await store.upsertUserTag(
        const UserTagRecord(
          id: 'remote-user-tag-1',
          name: 'queued',
          normalizedName: 'queued',
        ),
      );
      await store.attachUserTagToComic(
        const ComicUserTagRecord(
          comicId: 'remote:picacg:abc123',
          userTagId: 'remote-user-tag-1',
        ),
      );

      final repository = UnifiedCanonicalComicDetailRepository(store: store);
      final detail = await repository.getComicDetail('remote:picacg:abc123');

      expect(detail, isNotNull);
      expect(detail!.libraryState, LibraryState.remoteOnly);
      expect(detail.primarySource?.platformName, 'PicACG');
      expect(
        detail.primarySource?.comicUrl,
        'https://example.com/comic/abc123',
      );
      expect(detail.primarySource?.sourceTitle, 'Remote Canonical Source');
      expect(detail.sourceTags.single.namespace, 'artist');
      expect(detail.sourceTags.single.name, 'Alice');
      expect(detail.userTags.single.name, 'queued');
      expect(detail.availableActions.canManageUserTags, isTrue);
      expect(detail.availableActions.canViewSource, isTrue);
    },
  );

  test(
    'canonical remote repository returns page-ready detail with canonical overlays',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.seedDefaultSourcePlatforms();
      await store.upsertComic(
        const ComicRecord(
          id: 'remote:picacg:abc123',
          title: 'Remote Source Title',
          normalizedTitle: 'remote source title',
        ),
      );
      await store.upsertUserTag(
        const UserTagRecord(
          id: 'user-tag-remote',
          name: 'queued',
          normalizedName: 'queued',
        ),
      );
      await store.attachUserTagToComic(
        const ComicUserTagRecord(
          comicId: 'remote:picacg:abc123',
          userTagId: 'user-tag-remote',
        ),
      );

      final repository = CanonicalRemoteComicDetailRepository(store: store);
      final detailRes = await repository.getRemoteComicDetail(
        comicId: 'abc123',
        loadComicInfo: (comicId) async {
          return Res(
            ComicDetails.fromJson({
              'title': 'Remote Source Title',
              'subtitle': 'Uploader',
              'cover': 'https://example.com/cover.jpg',
              'description': 'Original description',
              'tags': {
                'artist': ['Alice'],
              },
              'chapters': null,
              'sourceKey': 'picacg',
              'comicId': comicId,
              'thumbnails': null,
              'recommend': null,
              'isFavorite': false,
              'subId': 'sub-1',
              'likesCount': 4,
              'isLiked': false,
              'commentCount': 2,
              'uploader': 'Uploader',
              'uploadTime': '2026-04-29',
              'updateTime': '2026-04-30T02:03:04Z',
              'url': 'https://example.com/comic/abc123',
              'stars': 4.5,
              'maxPage': 12,
              'comments': [
                {'userName': 'A', 'content': 'B', 'id': 'comment-1'},
              ],
            }),
          );
        },
      );

      expect(detailRes.success, isTrue);
      expect(detailRes.data.canonicalComicId, 'remote:picacg:abc123');
      expect(detailRes.data.detail.description, 'Remote Source Title');
      expect(detailRes.data.detail.url, 'https://example.com/comic/abc123');
      expect(detailRes.data.detail.tags['artist'], ['Alice']);
      expect(detailRes.data.detail.tags['User Tags'], ['queued']);
      expect(detailRes.data.detail.commentCount, 2);
      expect(detailRes.data.detail.maxPage, 12);
      expect(detailRes.data.detail.stars, 4.5);
      expect(detailRes.data.detail.comments, hasLength(1));
      expect(detailRes.data.detail.subId, 'sub-1');
    },
  );
}
