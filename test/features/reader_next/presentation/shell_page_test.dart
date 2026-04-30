import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/presentation/shell_page.dart';
import 'package:venera/features/reader_next/runtime/runtime.dart';

class _FakeAdapter implements ExternalSourceAdapter {
  _FakeAdapter({
    required this.sourceKey,
    this.shouldFailSearch = false,
    this.withDelay = false,
  });

  @override
  final String sourceKey;
  final bool shouldFailSearch;
  final bool withDelay;

  @override
  Future<List<SearchResultItem>> search({required SearchQuery query}) async {
    if (withDelay) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (shouldFailSearch) {
      throw ReaderRuntimeException('SOURCE_REF_INVALID', 'bad source ref');
    }
    return const <SearchResultItem>[
      SearchResultItem(
        upstreamComicRefId: 'comic-1',
        title: 'Title One',
        cover: 'cover-1',
        tags: <String>['tag-1'],
      ),
    ];
  }

  @override
  Future<ComicDetailResult> loadComicDetail({
    required String upstreamComicRefId,
  }) async {
    if (withDelay) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return const ComicDetailResult(
      title: 'Detail One',
      description: 'desc',
      chapters: <ChapterRef>[
        ChapterRef(chapterRefId: 'chapter-1', title: 'Chapter 1'),
      ],
    );
  }

  @override
  Future<List<ReaderImageRef>> loadReaderPageImages({
    required String upstreamComicRefId,
    required String chapterRefId,
    required int page,
  }) async {
    if (withDelay) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return const <ReaderImageRef>[
      ReaderImageRef(imageKey: 'img-1', imageUrl: 'url-1'),
      ReaderImageRef(imageKey: 'img-2', imageUrl: 'url-2'),
    ];
  }
}

ReaderNextRuntime _buildRuntime({
  required String sourceKey,
  bool shouldFailSearch = false,
  bool withDelay = false,
}) {
  final registry = SourceRegistry()
    ..register(
      _FakeAdapter(
        sourceKey: sourceKey,
        shouldFailSearch: shouldFailSearch,
        withDelay: withDelay,
      ),
    );
  return ReaderNextRuntime(
    gateway: RemoteAdapterGateway(registry),
    sessionStore: InMemoryReaderSessionStore(),
    imageCacheStore: InMemoryImageCacheStore(),
  );
}

void main() {
  group('ReaderNextShellPage', () {
    testWidgets('renders loading and then content for successful search', (
      tester,
    ) async {
      final runtime = _buildRuntime(sourceKey: 'test-source', withDelay: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderNextShellPage(runtime: runtime, sourceKey: 'test-source'),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('reader-next-search-input')),
        'hello',
      );
      await tester.tap(find.byKey(const Key('reader-next-search-button')));
      await tester.pump();
      expect(find.byKey(const Key('reader-next-loading')), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-next-error')), findsNothing);
      expect(find.byKey(const Key('reader-next-result-comic-1')), findsOneWidget);
    });

    testWidgets('renders typed error when runtime throws boundary failure', (
      tester,
    ) async {
      final runtime = _buildRuntime(
        sourceKey: 'test-source',
        shouldFailSearch: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderNextShellPage(runtime: runtime, sourceKey: 'test-source'),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('reader-next-search-input')),
        'hello',
      );
      await tester.tap(find.byKey(const Key('reader-next-search-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader-next-error')), findsOneWidget);
      expect(find.textContaining('Identity Boundary Error'), findsOneWidget);
    });

    testWidgets('shows detail and first-page image count after selecting result', (
      tester,
    ) async {
      final runtime = _buildRuntime(sourceKey: 'test-source', withDelay: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderNextShellPage(runtime: runtime, sourceKey: 'test-source'),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('reader-next-search-input')),
        'hello',
      );
      await tester.tap(find.byKey(const Key('reader-next-search-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reader-next-result-comic-1')));
      await tester.pump();
      expect(find.byKey(const Key('reader-next-loading')), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader-next-detail-title')), findsOneWidget);
      expect(find.text('Detail One'), findsOneWidget);
      expect(
        find.byKey(const Key('reader-next-first-page-image-count')),
        findsOneWidget,
      );
      expect(find.text('First page images: 2'), findsOneWidget);
    });
  });
}
