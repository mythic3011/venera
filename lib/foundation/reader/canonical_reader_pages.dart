import 'package:venera/foundation/db/unified_comics_store.dart';

class CanonicalReaderPages {
  const CanonicalReaderPages({required this.store});

  final UnifiedComicsStore store;

  Future<List<String>> loadLocalPages({
    required String localComicId,
    String? chapterId,
  }) async {
    final snapshot = await store.loadComicSnapshot(localComicId);
    if (snapshot == null || snapshot.localLibraryItems.isEmpty) {
      throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:$localComicId');
    }

    final targetChapterId = chapterId ?? _firstChapterId(snapshot);
    if (targetChapterId == null) {
      throw StateError('CANONICAL_CHAPTER_NOT_FOUND:$localComicId');
    }

    final pages = await store.loadActivePageOrderPages(targetChapterId);
    if (pages.isEmpty) {
      throw StateError('CANONICAL_PAGE_ORDER_NOT_FOUND:$targetChapterId');
    }

    return pages.map((page) => Uri.file(page.localPath).toString()).toList();
  }

  String? _firstChapterId(UnifiedComicSnapshot snapshot) {
    if (snapshot.chapters.isEmpty) {
      return null;
    }
    return snapshot.chapters.first.id;
  }
}
