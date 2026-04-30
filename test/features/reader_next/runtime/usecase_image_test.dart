import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/runtime.dart';

class _FakeExternalSourceAdapterForImage implements ExternalSourceAdapter {
  @override
  String get sourceKey => 'fake-source';

  @override
  Future<ComicDetailResult> loadComicDetail({
    required String upstreamComicRefId,
  }) async {
    return const ComicDetailResult(
      title: 'x',
      description: 'x',
      chapters: <ChapterRef>[],
    );
  }

  @override
  Future<List<ReaderImageRef>> loadReaderPageImages({
    required String upstreamComicRefId,
    required String chapterRefId,
    required int page,
  }) async {
    return const <ReaderImageRef>[
      ReaderImageRef(
        imageKey: 'img-key-1',
        imageUrl: 'https://example.com/one.jpg',
      ),
    ];
  }

  @override
  Future<List<SearchResultItem>> search({required SearchQuery query}) async {
    return const <SearchResultItem>[];
  }
}

void main() {
  group('ReaderNextRuntime image use case', () {
    late ReaderNextRuntime runtime;

    ComicIdentity identity() {
      return ComicIdentity(
        canonicalComicId: 'source:comic-42',
        sourceRef: SourceRef.remote(
          sourceKey: 'fake-source',
          upstreamComicRefId: 'comic-42',
        ),
      );
    }

    setUp(() {
      final registry = SourceRegistry()
        ..register(_FakeExternalSourceAdapterForImage());
      runtime = ReaderNextRuntime(
        gateway: RemoteAdapterGateway(registry),
        sessionStore: InMemoryReaderSessionStore(),
        imageCacheStore: InMemoryImageCacheStore(),
      );
    });

    test('first load fetches remote bytes and writes cache', () async {
      final refs = await runtime.loadReaderPage(
        identity: identity(),
        chapterRefId: 'ch-1',
        page: 1,
      );
      var fetchCount = 0;

      final result = await runtime.loadImageBytes(
        imageWithCacheKey: refs.first,
        fetchRemoteBytes: (image) async {
          fetchCount++;
          expect(image.imageKey, 'img-key-1');
          return <int>[1, 2, 3, 4];
        },
      );

      expect(fetchCount, 1);
      expect(result.fromCache, isFalse);
      expect(result.bytes, <int>[1, 2, 3, 4]);
      expect(
        result.cacheKey,
        'fake-source@source:comic-42@comic-42@ch-1@img-key-1',
      );
    });

    test('second load serves bytes from cache', () async {
      final refs = await runtime.loadReaderPage(
        identity: identity(),
        chapterRefId: 'ch-1',
        page: 1,
      );

      await runtime.loadImageBytes(
        imageWithCacheKey: refs.first,
        fetchRemoteBytes: (_) async => <int>[9, 9, 9],
      );

      var secondFetchCount = 0;
      final cached = await runtime.loadImageBytes(
        imageWithCacheKey: refs.first,
        fetchRemoteBytes: (_) async {
          secondFetchCount++;
          return <int>[8, 8, 8];
        },
      );

      expect(secondFetchCount, 0);
      expect(cached.fromCache, isTrue);
      expect(cached.bytes, <int>[9, 9, 9]);
    });
  });
}
