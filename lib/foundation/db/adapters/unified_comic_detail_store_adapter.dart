import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';

class UnifiedComicDetailStoreAdapter implements ComicDetailStorePort {
  const UnifiedComicDetailStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<int> countPagesForChapter(String chapterId) {
    return store.countPagesForChapter(chapterId);
  }

  @override
  Future<HistoryEventRecord?> loadLatestHistoryEvent(String comicId) {
    return store.loadLatestHistoryEvent(comicId);
  }

  @override
  Future<ComicSourceLinkRecord?> loadPrimaryComicSourceLink(String comicId) {
    return store.loadPrimaryComicSourceLink(comicId);
  }

  @override
  Future<SourcePlatformRecord?> loadSourcePlatformById(String platformId) {
    return store.loadSourcePlatformById(platformId);
  }

  @override
  Future<List<SourceTagRecord>> loadSourceTagsForComicSourceLink(
    String comicSourceLinkId,
  ) {
    return store.loadSourceTagsForComicSourceLink(comicSourceLinkId);
  }

  @override
  Future<List<UserTagRecord>> loadUserTagsForComic(String comicId) {
    return store.loadUserTagsForComic(comicId);
  }

  @override
  Future<PageOrderSummaryRecord> loadPageOrderSummary(String comicId) {
    return store.loadPageOrderSummary(comicId);
  }

  @override
  Future<UnifiedComicSnapshot?> loadComicSnapshot(String comicId) {
    return store.loadComicSnapshot(comicId);
  }

  @override
  Future<String> syncRemoteComic(ComicDetails detail) {
    return RemoteComicCanonicalSyncService(store: store).syncComic(detail);
  }
}
