import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/cache_keys.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  group('buildReaderImageCacheKey', () {
    final remoteRef = SourceRef.remote(
      sourceKey: 'copymanga',
      upstreamComicRefId: 'series-42',
      chapterRefId: 'ch-7',
    );

    test('composes cache key in exact required segment order', () {
      final key = buildReaderImageCacheKey(
        sourceRef: remoteRef,
        canonicalComicId: 'remote:copymanga:series-42',
        upstreamComicRefId: 'series-42',
        chapterRefId: 'ch-7',
        imageKey: 'p-001.jpg',
      );

      expect(
        key,
        'copymanga@remote:copymanga:series-42@series-42@ch-7@p-001.jpg',
      );
      expect(key.split('@'), <String>[
        'copymanga',
        'remote:copymanga:series-42',
        'series-42',
        'ch-7',
        'p-001.jpg',
      ]);
    });

    test('rejects empty required segments', () {
      expect(
        () => buildReaderImageCacheKey(
          sourceRef: remoteRef,
          canonicalComicId: 'remote:copymanga:series-42',
          upstreamComicRefId: '',
          chapterRefId: 'ch-7',
          imageKey: 'p-001.jpg',
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CACHE_KEY_INVALID'),
        ),
      );
    });

    test('rejects canonical upstream comic ref id segment', () {
      expect(
        () => buildReaderImageCacheKey(
          sourceRef: remoteRef,
          canonicalComicId: 'remote:copymanga:series-42',
          upstreamComicRefId: 'remote:copymanga:series-42',
          chapterRefId: 'ch-7',
          imageKey: 'p-001.jpg',
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CACHE_KEY_INVALID'),
        ),
      );
    });
  });
}
