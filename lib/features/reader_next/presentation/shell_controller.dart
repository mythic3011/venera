import 'package:flutter/foundation.dart';
import 'package:venera/features/reader_next/diagnostics/errors.dart';
import 'package:venera/features/reader_next/diagnostics/mapper.dart';
import 'package:venera/features/reader_next/runtime/runtime.dart';

enum ReaderNextShellPhase { idle, loading, ready, error }

class ReaderNextShellState {
  const ReaderNextShellState({
    required this.phase,
    this.error,
    this.searchResults = const <SearchResultItem>[],
    this.selectedDetail,
    this.pageImages = const <ReaderImageRefWithCacheKey>[],
  });

  final ReaderNextShellPhase phase;
  final ReaderNextLoadError? error;
  final List<SearchResultItem> searchResults;
  final ComicDetailResult? selectedDetail;
  final List<ReaderImageRefWithCacheKey> pageImages;

  ReaderNextShellState copyWith({
    ReaderNextShellPhase? phase,
    ReaderNextLoadError? error,
    bool clearError = false,
    List<SearchResultItem>? searchResults,
    ComicDetailResult? selectedDetail,
    bool clearSelectedDetail = false,
    List<ReaderImageRefWithCacheKey>? pageImages,
  }) {
    return ReaderNextShellState(
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      searchResults: searchResults ?? this.searchResults,
      selectedDetail: clearSelectedDetail
          ? null
          : (selectedDetail ?? this.selectedDetail),
      pageImages: pageImages ?? this.pageImages,
    );
  }
}

class ReaderNextShellController extends ChangeNotifier {
  ReaderNextShellController({
    required ReaderNextRuntime runtime,
    required String sourceKey,
  }) : _runtime = runtime,
       _sourceKey = sourceKey;

  final ReaderNextRuntime _runtime;
  final String _sourceKey;

  ReaderNextShellState _state = const ReaderNextShellState(
    phase: ReaderNextShellPhase.idle,
  );
  ReaderNextShellState get state => _state;

  Future<void> search(String keyword) async {
    _state = _state.copyWith(
      phase: ReaderNextShellPhase.loading,
      clearError: true,
      clearSelectedDetail: true,
      pageImages: const <ReaderImageRefWithCacheKey>[],
    );
    notifyListeners();
    try {
      final results = await _runtime.search(
        sourceKey: _sourceKey,
        keyword: keyword,
      );
      _state = _state.copyWith(
        phase: ReaderNextShellPhase.ready,
        searchResults: results,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        phase: ReaderNextShellPhase.error,
        error: mapReaderNextRuntimeError(e),
      );
      notifyListeners();
    }
  }

  Future<void> selectComic(SearchResultItem item) async {
    _state = _state.copyWith(
      phase: ReaderNextShellPhase.loading,
      clearError: true,
      pageImages: const <ReaderImageRefWithCacheKey>[],
    );
    notifyListeners();
    try {
      final identity = ComicIdentity(
        canonicalComicId: '$_sourceKey:${item.upstreamComicRefId}',
        sourceRef: SourceRef.remote(
          sourceKey: _sourceKey,
          upstreamComicRefId: item.upstreamComicRefId,
        ),
      );
      final detail = await _runtime.loadComicDetail(identity: identity);
      List<ReaderImageRefWithCacheKey> firstPageImages =
          const <ReaderImageRefWithCacheKey>[];
      if (detail.chapters.isNotEmpty) {
        firstPageImages = await _runtime.loadReaderPage(
          identity: identity,
          chapterRefId: detail.chapters.first.chapterRefId,
          page: 1,
        );
      }
      _state = _state.copyWith(
        phase: ReaderNextShellPhase.ready,
        selectedDetail: detail,
        pageImages: firstPageImages,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        phase: ReaderNextShellPhase.error,
        error: mapReaderNextRuntimeError(e),
      );
      notifyListeners();
    }
  }
}
