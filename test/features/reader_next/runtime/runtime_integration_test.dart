import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/runtime.dart';

class _FakeExternalSourceAdapter implements ExternalSourceAdapter {
  _FakeExternalSourceAdapter({required this.sourceKey});

  @override
  final String sourceKey;

  SearchQuery? lastSearchQuery;
  String? lastDetailUpstreamComicRefId;
  String? lastPageUpstreamComicRefId;
  String? lastPageChapterRefId;
  int? lastPageIndex;
  List<ReaderImageRef> pageImages = const <ReaderImageRef>[
    ReaderImageRef(imageKey: 'img-1', imageUrl: 'https://example.com/1.jpg'),
    ReaderImageRef(imageKey: 'img-2', imageUrl: 'https://example.com/2.jpg'),
  ];

  @override
  Future<List<SearchResultItem>> search({required SearchQuery query}) async {
    lastSearchQuery = query;
    return <SearchResultItem>[
      const SearchResultItem(
        upstreamComicRefId: 'upstream-comic-1',
        title: 'Comic One',
        cover: 'https://example.com/cover-1.jpg',
        tags: <String>['action'],
      ),
    ];
  }

  @override
  Future<ComicDetailResult> loadComicDetail({required String upstreamComicRefId}) async {
    lastDetailUpstreamComicRefId = upstreamComicRefId;
    return const ComicDetailResult(
      title: 'Comic One',
      description: 'Detail payload',
      chapters: <ChapterRef>[
        ChapterRef(chapterRefId: 'ch-1', title: 'Chapter 1'),
      ],
    );
  }

  @override
  Future<List<ReaderImageRef>> loadReaderPageImages({
    required String upstreamComicRefId,
    required String chapterRefId,
    required int page,
  }) async {
    lastPageUpstreamComicRefId = upstreamComicRefId;
    lastPageChapterRefId = chapterRefId;
    lastPageIndex = page;
    return pageImages;
  }
}

class _RecordingLocalResolver implements LocalReaderPageResolver {
  ComicIdentity? lastIdentity;
  String? lastChapterRefId;
  int? lastPage;
  List<ReaderImageRef> images = const <ReaderImageRef>[
    ReaderImageRef(imageKey: 'local-1', imageUrl: '/tmp/local-1.jpg'),
  ];
  Object? throwError;

  @override
  Future<List<ReaderImageRef>> loadReaderPageImages({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
  }) async {
    lastIdentity = identity;
    lastChapterRefId = chapterRefId;
    lastPage = page;
    if (throwError != null) {
      throw throwError!;
    }
    return images;
  }
}

void main() {
  group('ReaderNextRuntime integration harness', () {
    late _FakeExternalSourceAdapter adapter;
    late ReaderNextRuntime runtime;
    const sourceKey = 'fake-source';
    const upstreamComicRefId = 'comic-42';
    const canonicalComicId = 'source:comic-42';

    ComicIdentity identity() {
      return ComicIdentity(
        canonicalComicId: canonicalComicId,
        sourceRef: SourceRef.remote(
          sourceKey: sourceKey,
          upstreamComicRefId: upstreamComicRefId,
        ),
      );
    }

    setUp(() {
      adapter = _FakeExternalSourceAdapter(sourceKey: sourceKey);
      final registry = SourceRegistry()..register(adapter);
      runtime = ReaderNextRuntime(
        gateway: RemoteAdapterGateway(registry),
        sessionStore: InMemoryReaderSessionStore(),
      );
    });

    test('search delegates to gateway/adapter with trimmed keyword and page', () async {
      final results = await runtime.search(
        sourceKey: sourceKey,
        keyword: '  hello world  ',
        page: 3,
      );

      expect(results, hasLength(1));
      expect(results.first.upstreamComicRefId, 'upstream-comic-1');
      expect(adapter.lastSearchQuery?.keyword, 'hello world');
      expect(adapter.lastSearchQuery?.page, 3);
    });

    test('loadComicDetail resolves through gateway into adapter', () async {
      final detail = await runtime.loadComicDetail(identity: identity());

      expect(detail.title, 'Comic One');
      expect(detail.chapters, hasLength(1));
      expect(adapter.lastDetailUpstreamComicRefId, upstreamComicRefId);
    });

    test('loadReaderPage returns cache-key wrapped images and tracks adapter args', () async {
      final images = await runtime.loadReaderPage(
        identity: identity(),
        chapterRefId: 'ch-1',
        page: 5,
      );

      expect(images, hasLength(2));
      expect(images.first.image.imageUrl, 'https://example.com/1.jpg');
      expect(
        images.first.cacheKey,
        '$sourceKey@$canonicalComicId@$upstreamComicRefId@ch-1@img-1',
      );
      expect(adapter.lastPageUpstreamComicRefId, upstreamComicRefId);
      expect(adapter.lastPageChapterRefId, 'ch-1');
      expect(adapter.lastPageIndex, 5);
    });

    test('remote ReaderNext route with empty image refs throws typed error', () async {
      adapter.pageImages = const <ReaderImageRef>[];
      await expectLater(
        () => runtime.loadReaderPage(
          identity: identity(),
          chapterRefId: 'ch-1',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'REMOTE_PAGES_EMPTY'),
        ),
      );
    });

    test('saveResumeSession then loadResumeSession round-trips', () async {
      await runtime.saveResumeSession(
        identity: identity(),
        chapterRefId: 'ch-9',
        page: 11,
      );

      final session = await runtime.loadResumeSession(canonicalComicId: canonicalComicId);
      expect(session, isNotNull);
      expect(session?.canonicalComicId, canonicalComicId);
      expect(session?.sourceRef.sourceKey, sourceKey);
      expect(session?.sourceRef.upstreamComicRefId, upstreamComicRefId);
      expect(session?.chapterRefId, 'ch-9');
      expect(session?.page, 11);
    });
  });

  group('ReaderNextRuntime local resolver flow', () {
    late _FakeExternalSourceAdapter adapter;
    late _RecordingLocalResolver localResolver;
    late ReaderNextRuntime runtime;

    setUp(() {
      adapter = _FakeExternalSourceAdapter(sourceKey: 'fake-source');
      localResolver = _RecordingLocalResolver();
      final registry = SourceRegistry()..register(adapter);
      runtime = ReaderNextRuntime(
        gateway: RemoteAdapterGateway(registry),
        sessionStore: InMemoryReaderSessionStore(),
        localPageResolver: localResolver,
      );
    });

    test('ReaderNext local resolver opens local chapter pages', () async {
      final identity = ComicIdentity(
        canonicalComicId: 'local:local-comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'local-comic-1',
          chapterRefId: '1:chapter-key',
        ),
      );

      final refs = await runtime.loadReaderPage(
        identity: identity,
        chapterRefId: '1:chapter-key',
        page: 1,
      );

      expect(refs, hasLength(1));
      expect(refs.first.image.imageUrl, '/tmp/local-1.jpg');
      expect(refs.first.cacheKey, contains('local:local-comic-1'));
      expect(refs.first.cacheKey, isNot(contains('Instance of')));
      expect(localResolver.lastIdentity?.sourceRef.type, SourceRefType.local);
      expect(localResolver.lastIdentity?.sourceRef.upstreamComicRefId, 'local-comic-1');
      expect(localResolver.lastChapterRefId, '1:chapter-key');
      expect(adapter.lastPageUpstreamComicRefId, isNull);
    });

    test('ReaderNext local resolver blocks missing local comic without fallback', () async {
      localResolver.throwError = ReaderRuntimeException(
        'LOCAL_COMIC_NOT_FOUND',
        'Local comic was not found for ReaderNext request',
      );
      final identity = ComicIdentity(
        canonicalComicId: 'local:missing-local-comic',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'missing-local-comic',
          chapterRefId: '1:chapter-key',
        ),
      );

      await expectLater(
        () => runtime.loadReaderPage(
          identity: identity,
          chapterRefId: '1:chapter-key',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'LOCAL_COMIC_NOT_FOUND'),
        ),
      );
      expect(adapter.lastPageUpstreamComicRefId, isNull);
    });

    test('ReaderNext local resolver maps legacy late failure to LOCAL_STORAGE_UNAVAILABLE', () async {
      localResolver.throwError = ReaderRuntimeException(
        'LOCAL_STORAGE_UNAVAILABLE',
        'Local storage is unavailable',
      );
      final identity = ComicIdentity(
        canonicalComicId: 'local:local-comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'local-comic-1',
          chapterRefId: '1:chapter-key',
        ),
      );

      await expectLater(
        () => runtime.loadReaderPage(
          identity: identity,
          chapterRefId: '1:chapter-key',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'LOCAL_STORAGE_UNAVAILABLE'),
        ),
      );
    });

    test('local ReaderNext route with empty image refs throws typed error', () async {
      localResolver.images = const <ReaderImageRef>[];
      final identity = ComicIdentity(
        canonicalComicId: 'local:local-comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'local-comic-1',
          chapterRefId: '1:chapter-key',
        ),
      );

      await expectLater(
        () => runtime.loadReaderPage(
          identity: identity,
          chapterRefId: '1:chapter-key',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'LOCAL_PAGES_EMPTY'),
        ),
      );
    });
  });

  group('Reader runtime canonical/upstream guards', () {
    test('SourceRef.remote rejects canonical upstream id', () {
      expect(
        () => SourceRef.remote(
          sourceKey: 'fake-source',
          upstreamComicRefId: 'source:canonical-upstream',
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID')
              .having((e) => e.message, 'message', contains('must not be canonical')),
        ),
      );
    });

    test('loadResumeSession rejects non-canonical comic id', () async {
      final runtime = ReaderNextRuntime(
        gateway: RemoteAdapterGateway(SourceRegistry()),
        sessionStore: InMemoryReaderSessionStore(),
      );

      expect(
        () => runtime.loadResumeSession(canonicalComicId: 'not-namespaced-id'),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CANONICAL_ID_INVALID'),
        ),
      );
    });

    test('registry/gateway path throws when adapter is missing', () async {
      final runtime = ReaderNextRuntime(
        gateway: RemoteAdapterGateway(SourceRegistry()),
        sessionStore: InMemoryReaderSessionStore(),
      );

      expect(
        () => runtime.search(sourceKey: 'missing-source', keyword: 'hello'),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'ADAPTER_NOT_FOUND'),
        ),
      );
    });
  });
}
