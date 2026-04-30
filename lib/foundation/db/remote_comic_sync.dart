import 'package:venera/features/sources/comic_source/comic_source.dart';

import 'unified_comics_store.dart';

String canonicalRemoteComicId({
  required String sourceKey,
  required String comicId,
}) {
  return 'remote:$sourceKey:$comicId';
}

const String _canonicalRemoteDefaultPageOrderName = 'Source Default';

class RemoteComicCanonicalSyncService {
  const RemoteComicCanonicalSyncService({required this.store});

  final UnifiedComicsStore store;

  Future<String> syncComic(ComicDetails comic) async {
    final canonicalComicId = canonicalRemoteComicId(
      sourceKey: comic.sourceKey,
      comicId: comic.comicId,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final sourceLinkId = 'source_link:$canonicalComicId';
    final chapterEntries =
        comic.chapters?.allChapters.entries.toList(growable: false) ?? const [];

    await store.transaction(() async {
      await store.upsertComic(
        ComicRecord(
          id: canonicalComicId,
          title: comic.title,
          normalizedTitle: _normalizeText(comic.title),
          createdAt: now,
          updatedAt: _normalizeTimestamp(comic.updateTime) ?? now,
        ),
      );
      await store.insertComicTitle(
        ComicTitleRecord(
          comicId: canonicalComicId,
          title: comic.title,
          normalizedTitle: _normalizeText(comic.title),
          titleType: 'primary',
          sourcePlatformId: comic.sourceKey,
          createdAt: now,
        ),
      );
      await store.upsertComicSourceLink(
        ComicSourceLinkRecord(
          id: sourceLinkId,
          comicId: canonicalComicId,
          sourcePlatformId: comic.sourceKey,
          sourceComicId: comic.comicId,
          isPrimary: true,
          sourceUrl: comic.url,
          sourceTitle: comic.title,
          linkedAt: now,
          updatedAt: _normalizeTimestamp(comic.updateTime) ?? now,
          lastVerifiedAt: now,
        ),
      );
      if (chapterEntries.isNotEmpty) {
        await store.deleteChaptersForComic(canonicalComicId);
      }
      for (
        var chapterIndex = 0;
        chapterIndex < chapterEntries.length;
        chapterIndex++
      ) {
        final chapterEntry = chapterEntries[chapterIndex];
        final chapterId = '$canonicalComicId:${chapterEntry.key}';
        await store.upsertChapter(
          ChapterRecord(
            id: chapterId,
            comicId: canonicalComicId,
            chapterNo: (chapterIndex + 1).toDouble(),
            title: chapterEntry.value,
            normalizedTitle: _normalizeText(chapterEntry.value),
            createdAt: now,
            updatedAt: _normalizeTimestamp(comic.updateTime) ?? now,
          ),
        );
        await store.upsertChapterSourceLink(
          ChapterSourceLinkRecord(
            id: '$sourceLinkId:chapter:${chapterEntry.key}',
            chapterId: chapterId,
            comicSourceLinkId: sourceLinkId,
            sourceChapterId: chapterEntry.key,
            linkedAt: now,
            updatedAt: _normalizeTimestamp(comic.updateTime) ?? now,
          ),
        );
      }
      await store.clearSourceTagsForComicSourceLink(sourceLinkId);
      for (final entry in comic.tags.entries) {
        final namespace = entry.key.trim();
        for (final rawTag in entry.value) {
          final normalizedTag = rawTag.trim();
          if (normalizedTag.isEmpty) {
            continue;
          }
          final tagId =
              'source_tag:${comic.sourceKey}:${namespace.toLowerCase()}:${normalizedTag.toLowerCase()}';
          await store.upsertSourceTag(
            SourceTagRecord(
              id: tagId,
              sourcePlatformId: comic.sourceKey,
              namespace: namespace,
              tagKey: normalizedTag.toLowerCase(),
              displayName: normalizedTag,
              createdAt: now,
            ),
          );
          await store.attachSourceTagToComicSourceLink(
            ComicSourceLinkTagRecord(
              comicSourceLinkId: sourceLinkId,
              sourceTagId: tagId,
              addedAt: now,
            ),
          );
        }
      }
    });

    return canonicalComicId;
  }

  Future<void> syncChapterPages({
    required String sourceKey,
    required String comicId,
    required String chapterId,
    required List<String> pageKeys,
  }) async {
    final canonicalComicId = canonicalRemoteComicId(
      sourceKey: sourceKey,
      comicId: comicId,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final sourceLinkId = 'source_link:$canonicalComicId';
    final canonicalChapterId = '$canonicalComicId:$chapterId';
    final chapterSourceLinkId = '$sourceLinkId:chapter:$chapterId';
    final normalizedChapterTitle = _normalizeText(chapterId);

    await store.transaction(() async {
      await store.upsertComic(
        ComicRecord(
          id: canonicalComicId,
          title: comicId,
          normalizedTitle: _normalizeText(comicId),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.upsertComicSourceLink(
        ComicSourceLinkRecord(
          id: sourceLinkId,
          comicId: canonicalComicId,
          sourcePlatformId: sourceKey,
          sourceComicId: comicId,
          isPrimary: true,
          linkedAt: now,
          updatedAt: now,
          lastVerifiedAt: now,
        ),
      );
      await store.upsertChapter(
        ChapterRecord(
          id: canonicalChapterId,
          comicId: canonicalComicId,
          title: chapterId,
          normalizedTitle: normalizedChapterTitle,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.upsertChapterSourceLink(
        ChapterSourceLinkRecord(
          id: chapterSourceLinkId,
          chapterId: canonicalChapterId,
          comicSourceLinkId: sourceLinkId,
          sourceChapterId: chapterId,
          linkedAt: now,
          updatedAt: now,
        ),
      );
      await store.deletePagesForChapter(canonicalChapterId);
      for (var pageIndex = 0; pageIndex < pageKeys.length; pageIndex++) {
        final pageKey = pageKeys[pageIndex];
        final canonicalPageId = '$canonicalChapterId:$pageIndex';
        await store.upsertPage(
          PageRecord(
            id: canonicalPageId,
            chapterId: canonicalChapterId,
            pageIndex: pageIndex,
            localPath: pageKey,
            createdAt: now,
          ),
        );
        await store.upsertPageSourceLink(
          PageSourceLinkRecord(
            id: '$chapterSourceLinkId:page:$pageIndex',
            pageId: canonicalPageId,
            comicSourceLinkId: sourceLinkId,
            chapterSourceLinkId: chapterSourceLinkId,
            sourcePageId: pageIndex.toString(),
            sourceUrl: pageKey,
            linkedAt: now,
            updatedAt: now,
          ),
        );
      }
      final orderId = '$canonicalChapterId:source_default';
      await store.upsertPageOrder(
        PageOrderRecord(
          id: orderId,
          chapterId: canonicalChapterId,
          orderName: _canonicalRemoteDefaultPageOrderName,
          normalizedOrderName: _normalizeText(
            _canonicalRemoteDefaultPageOrderName,
          ),
          orderType: 'source_default',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.replacePageOrderItems(orderId, [
        for (var pageIndex = 0; pageIndex < pageKeys.length; pageIndex++)
          PageOrderItemRecord(
            pageOrderId: orderId,
            pageId: '$canonicalChapterId:$pageIndex',
            sortOrder: pageIndex,
          ),
      ]);
    });
  }
}

String _normalizeText(String value) => value.trim().toLowerCase();

String? _normalizeTimestamp(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc().toIso8601String() ?? value;
}
