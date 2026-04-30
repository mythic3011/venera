import 'package:venera/foundation/db/unified_comics_store.dart';

class ReaderDebugSnapshot {
  const ReaderDebugSnapshot({
    required this.generatedAt,
    required this.comicId,
    required this.loadMode,
    required this.controllerLifecycle,
    this.localLibraryItemId,
    this.comicSourceId,
    this.readerTabId,
    this.pageOrderId,
    this.chapterId,
  });

  final DateTime generatedAt;
  final String comicId;
  final String loadMode;
  final String controllerLifecycle;
  final String? localLibraryItemId;
  final String? comicSourceId;
  final String? readerTabId;
  final String? pageOrderId;
  final String? chapterId;

  Map<String, Object?> toJson() {
    return {
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'comicId': comicId,
      'localLibraryItemId': localLibraryItemId,
      'comicSourceId': comicSourceId,
      'readerTabId': readerTabId,
      'pageOrderId': pageOrderId,
      'chapterId': chapterId,
      'loadMode': loadMode,
      'controllerLifecycle': controllerLifecycle,
    };
  }
}

class ReaderDebugSnapshotService {
  const ReaderDebugSnapshotService({required this.store});

  final UnifiedComicsStore store;

  Future<ReaderDebugSnapshot> build({
    required String comicId,
    required String loadMode,
    required String controllerLifecycle,
    String? chapterId,
  }) async {
    final isLocal = loadMode == 'local';
    final localItem = isLocal
        ? await store.loadPrimaryLocalLibraryItem(comicId)
        : null;
    if (isLocal && localItem == null) {
      throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:$comicId');
    }

    final pageOrder = chapterId == null
        ? null
        : await store.loadActivePageOrderForChapter(chapterId);
    if (isLocal && chapterId != null && pageOrder == null) {
      throw StateError('CANONICAL_PAGE_ORDER_NOT_FOUND:$chapterId');
    }

    return ReaderDebugSnapshot(
      generatedAt: DateTime.now(),
      comicId: comicId,
      loadMode: loadMode,
      controllerLifecycle: controllerLifecycle,
      localLibraryItemId: localItem?.id,
      pageOrderId: pageOrder?.id,
      chapterId: chapterId,
    );
  }
}
