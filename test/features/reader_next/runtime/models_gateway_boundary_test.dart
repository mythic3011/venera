import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/adapter.dart';
import 'package:venera/features/reader_next/runtime/gateway.dart';
import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/features/reader_next/runtime/registry.dart';

class _RecordingAdapter implements ExternalSourceAdapter {
  _RecordingAdapter({required this.sourceKey});

  @override
  final String sourceKey;

  String? lastDetailUpstreamComicRefId;
  String? lastReaderUpstreamComicRefId;
  String? lastReaderChapterRefId;
  int? lastReaderPage;

  @override
  Future<List<SearchResultItem>> search({required SearchQuery query}) async {
    return const <SearchResultItem>[];
  }

  @override
  Future<ComicDetailResult> loadComicDetail({
    required String upstreamComicRefId,
  }) async {
    lastDetailUpstreamComicRefId = upstreamComicRefId;
    return const ComicDetailResult(title: 'title', description: 'desc', chapters: <ChapterRef>[]);
  }

  @override
  Future<List<ReaderImageRef>> loadReaderPageImages({
    required String upstreamComicRefId,
    required String chapterRefId,
    required int page,
  }) async {
    lastReaderUpstreamComicRefId = upstreamComicRefId;
    lastReaderChapterRefId = chapterRefId;
    lastReaderPage = page;
    return const <ReaderImageRef>[];
  }
}

void main() {
  group('SourceRef.remote fail-closed validation', () {
    test('throws when sourceKey is empty', () {
      expect(
        () => SourceRef.remote(sourceKey: '', upstreamComicRefId: 'upstream-1'),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID'),
        ),
      );
    });

    test('throws when upstreamComicRefId is empty', () {
      expect(
        () => SourceRef.remote(sourceKey: 'copymanga', upstreamComicRefId: ''),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID'),
        ),
      );
    });

    test('throws when upstreamComicRefId is canonical', () {
      expect(
        () => SourceRef.remote(
          sourceKey: 'copymanga',
          upstreamComicRefId: 'copymanga:comic-9',
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID'),
        ),
      );
    });
  });

  group('RemoteAdapterGateway fail-closed boundary', () {
    late SourceRegistry registry;
    late _RecordingAdapter adapter;
    late RemoteAdapterGateway gateway;

    setUp(() {
      registry = SourceRegistry();
      adapter = _RecordingAdapter(sourceKey: 'copymanga');
      registry.register(adapter);
      gateway = RemoteAdapterGateway(registry);
    });

    test('rejects missing/invalid remote SourceRef via local identity', () async {
      final identity = ComicIdentity(
        canonicalComicId: 'copymanga:comic-9',
        sourceRef: SourceRef.local(
          sourceKey: 'copymanga',
          comicRefId: 'comic-9',
        ),
      );

      await expectLater(
        () => gateway.loadComicDetail(identity: identity),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_REQUIRED'),
        ),
      );
      expect(adapter.lastDetailUpstreamComicRefId, isNull);
    });

    test('rejects invalid canonicalComicId before adapter call', () async {
      final identity = ComicIdentity(
        canonicalComicId: '',
        sourceRef: SourceRef.remote(
          sourceKey: 'copymanga',
          upstreamComicRefId: 'upstream-comic-9',
        ),
      );

      await expectLater(
        () => gateway.loadComicDetail(identity: identity),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CANONICAL_ID_INVALID'),
        ),
      );
      expect(adapter.lastDetailUpstreamComicRefId, isNull);
    });

    test('passes upstreamComicRefId to detail adapter call, not canonicalComicId', () async {
      final identity = ComicIdentity(
        canonicalComicId: 'copymanga:canonical-comic-9',
        sourceRef: SourceRef.remote(
          sourceKey: 'copymanga',
          upstreamComicRefId: 'upstream-comic-9',
        ),
      );

      await gateway.loadComicDetail(identity: identity);

      expect(adapter.lastDetailUpstreamComicRefId, 'upstream-comic-9');
      expect(adapter.lastDetailUpstreamComicRefId, isNot(identity.canonicalComicId));
    });

    test('passes upstreamComicRefId to reader image adapter call, not canonicalComicId', () async {
      final identity = ComicIdentity(
        canonicalComicId: 'copymanga:canonical-comic-9',
        sourceRef: SourceRef.remote(
          sourceKey: 'copymanga',
          upstreamComicRefId: 'upstream-comic-9',
        ),
      );

      await gateway.loadReaderPageImages(
        identity: identity,
        chapterRefId: 'ch-1',
        page: 3,
      );

      expect(adapter.lastReaderUpstreamComicRefId, 'upstream-comic-9');
      expect(adapter.lastReaderUpstreamComicRefId, isNot(identity.canonicalComicId));
      expect(adapter.lastReaderChapterRefId, 'ch-1');
      expect(adapter.lastReaderPage, 3);
    });
  });
}
