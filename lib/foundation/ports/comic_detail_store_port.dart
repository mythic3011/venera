import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

/// legacy-compatible: temporarily exposes persistence-shaped records.
abstract class ComicDetailStorePort {
  Future<UnifiedComicSnapshot?> loadComicSnapshot(String comicId);
  Future<ComicSourceLinkRecord?> loadPrimaryComicSourceLink(String comicId);
  Future<SourcePlatformRecord?> loadSourcePlatformById(String platformId);
  Future<List<SourceTagRecord>> loadSourceTagsForComicSourceLink(
    String comicSourceLinkId,
  );
  Future<List<UserTagRecord>> loadUserTagsForComic(String comicId);
  Future<int> countPagesForChapter(String chapterId);
  Future<HistoryEventRecord?> loadLatestHistoryEvent(String comicId);
  Future<PageOrderSummaryRecord> loadPageOrderSummary(String comicId);
  Future<String> syncRemoteComic(ComicDetails detail);
}
