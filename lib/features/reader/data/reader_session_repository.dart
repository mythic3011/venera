import 'dart:convert';

import 'package:venera/features/comic_detail/data/comic_detail_models.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/reader_session_store_port.dart';
import 'package:venera/foundation/sources/source_ref.dart';

class ReaderSessionRepository {
  ReaderSessionRepository({required this.store});
  static int _pendingWrites = 0;

  static int get pendingWrites => _pendingWrites;

  final ReaderSessionStorePort store;
  final Map<String, _SessionProgressSnapshot> _lastProgressByTabId = {};
  final Map<String, String?> _lastActiveTabByComicId = {};

  static String sessionIdForComic(String comicId) {
    return 'reader-session:${Uri.encodeComponent(comicId)}';
  }

  static String defaultTabIdForSourceRef(SourceRef sourceRef) {
    return sourceRef.id;
  }

  Future<List<ReaderTabVm>> loadReaderTabs(String comicId) async {
    final session = await store.loadReaderSessionByComic(comicId);
    if (session == null) {
      return const <ReaderTabVm>[];
    }
    final tabs = await store.loadReaderTabsForSession(session.id);
    return tabs
        .map((tab) => _mapTab(tab, activeTabId: session.activeTabId))
        .toList(growable: false);
  }

  Future<ReaderTabVm?> loadActiveReaderTab(String comicId) async {
    final tabs = await loadReaderTabs(comicId);
    for (final tab in tabs) {
      if (tab.isActive) {
        return tab;
      }
    }
    return tabs.isEmpty ? null : tabs.first;
  }

  Future<void> upsertCurrentLocation({
    required String comicId,
    required String chapterId,
    required int pageIndex,
    required SourceRef sourceRef,
    String? pageOrderId,
    String? tabId,
    bool makeActive = true,
  }) async {
    final sessionId = sessionIdForComic(comicId);
    final resolvedTabId = tabId ?? defaultTabIdForSourceRef(sourceRef);
    final sourceRefJson = jsonEncode(sourceRef.toJson());
    final snapshot = _SessionProgressSnapshot(
      chapterId: chapterId,
      pageIndex: pageIndex,
      sourceRefJson: sourceRefJson,
      pageOrderId: pageOrderId,
    );
    if (_lastProgressByTabId[resolvedTabId] == snapshot &&
        (!makeActive || _lastActiveTabByComicId[comicId] == resolvedTabId)) {
      return;
    }
    await _trackWrite(() async {
      await saveProgress(
        sessionId: sessionId,
        comicId: comicId,
        tabId: resolvedTabId,
        chapterId: chapterId,
        pageIndex: pageIndex,
        sourceRefJson: sourceRefJson,
        pageOrderId: pageOrderId,
        makeActive: makeActive,
      );
      _lastProgressByTabId[resolvedTabId] = snapshot;
      if (makeActive) {
        _lastActiveTabByComicId[comicId] = resolvedTabId;
      }
    });
  }

  Future<void> markActiveTab({
    required String comicId,
    required String tabId,
  }) async {
    if (_lastActiveTabByComicId[comicId] == tabId) {
      return;
    }
    final session = await store.loadReaderSessionByComic(comicId);
    if (session == null) {
      throw StateError('No reader session exists for comic $comicId.');
    }
    await _trackWrite(() async {
      await updateActiveTab(
        sessionId: session.id,
        activeTabId: tabId,
      );
      _lastActiveTabByComicId[comicId] = tabId;
    });
  }

  Future<void> upsertSession({
    required String sessionId,
    required String comicId,
    String? activeTabId,
  }) {
    return store.upsertReaderSession(
      ReaderSessionRecord(
        id: sessionId,
        comicId: comicId,
        activeTabId: activeTabId,
      ),
    );
  }

  Future<void> updateActiveTab({
    required String sessionId,
    required String activeTabId,
  }) {
    return store.setReaderSessionActiveTab(
      sessionId: sessionId,
      activeTabId: activeTabId,
    );
  }

  Future<void> saveProgress({
    required String sessionId,
    required String comicId,
    required String tabId,
    required String chapterId,
    required int pageIndex,
    required String sourceRefJson,
    String? pageOrderId,
    required bool makeActive,
  }) async {
    if (store is UnifiedComicsStore) {
      final dbStore = store as UnifiedComicsStore;
      await dbStore.saveReaderProgress(
        session: ReaderSessionRecord(id: sessionId, comicId: comicId),
        tab: ReaderTabRecord(
          id: tabId,
          sessionId: sessionId,
          comicId: comicId,
          chapterId: chapterId,
          pageIndex: pageIndex,
          sourceRefJson: sourceRefJson,
          pageOrderId: pageOrderId,
        ),
        makeActive: makeActive,
      );
      return;
    }

    await upsertSession(sessionId: sessionId, comicId: comicId);
    await store.upsertReaderTab(
      ReaderTabRecord(
        id: tabId,
        sessionId: sessionId,
        comicId: comicId,
        chapterId: chapterId,
        pageIndex: pageIndex,
        sourceRefJson: sourceRefJson,
        pageOrderId: pageOrderId,
      ),
    );
    if (makeActive) {
      await updateActiveTab(sessionId: sessionId, activeTabId: tabId);
    }
  }

  Future<void> deleteSession(String comicId) async {
    final session = await store.loadReaderSessionByComic(comicId);
    if (session == null) {
      return;
    }
    await _trackWrite(() async {
      await store.deleteReaderSession(session.id);
    });
  }

  Future<void> _trackWrite(Future<void> Function() action) async {
    _pendingWrites++;
    try {
      await action();
    } finally {
      _pendingWrites--;
    }
  }

  ReaderTabVm _mapTab(ReaderTabRecord tab, {required String? activeTabId}) {
    final sourceRef = SourceRef.fromJson(
      Map<String, dynamic>.from(jsonDecode(tab.sourceRefJson) as Map),
    );
    return ReaderTabVm(
      tabId: tab.id,
      currentChapterId: tab.chapterId,
      currentPageIndex: tab.pageIndex,
      sourceRef: sourceRef,
      loadMode: sourceRef.type == SourceRefType.local
          ? ReaderTabLoadMode.localLibrary
          : ReaderTabLoadMode.remoteSource,
      pageOrderId: tab.pageOrderId,
      isActive: tab.id == activeTabId,
      updatedAt: DateTime.tryParse(tab.updatedAt ?? ''),
    );
  }
}

class _SessionProgressSnapshot {
  const _SessionProgressSnapshot({
    required this.chapterId,
    required this.pageIndex,
    required this.sourceRefJson,
    required this.pageOrderId,
  });

  final String chapterId;
  final int pageIndex;
  final String sourceRefJson;
  final String? pageOrderId;

  @override
  bool operator ==(Object other) {
    return other is _SessionProgressSnapshot &&
        other.chapterId == chapterId &&
        other.pageIndex == pageIndex &&
        other.sourceRefJson == sourceRefJson &&
        other.pageOrderId == pageOrderId;
  }

  @override
  int get hashCode => Object.hash(
    chapterId,
    pageIndex,
    sourceRefJson,
    pageOrderId,
  );
}
