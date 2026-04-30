import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/features/reader_next/runtime/session.dart';

void main() {
  group('ReaderResumeSession.validate', () {
    final remoteRef = SourceRef.remote(
      sourceKey: 'nhentai',
      upstreamComicRefId: '646922',
      chapterRefId: 'c1',
    );

    test('rejects non-namespaced canonical comic id', () {
      final session = ReaderResumeSession(
        canonicalComicId: '646922',
        sourceRef: remoteRef,
        chapterRefId: 'c1',
        page: 0,
      );

      expect(
        () => session.validate(),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CANONICAL_ID_INVALID'),
        ),
      );
    });

    test('accepts namespaced canonical comic id', () {
      final session = ReaderResumeSession(
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: remoteRef,
        chapterRefId: 'c1',
        page: 0,
      );

      expect(session.validate, returnsNormally);
    });

    test('rejects malformed resume payload with empty chapterRefId', () {
      final session = ReaderResumeSession(
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: remoteRef,
        chapterRefId: '',
        page: 0,
      );

      expect(
        () => session.validate(),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SESSION_INVALID'),
        ),
      );
    });

    test('rejects malformed resume payload with negative page index', () {
      final session = ReaderResumeSession(
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: remoteRef,
        chapterRefId: 'c1',
        page: -1,
      );

      expect(
        () => session.validate(),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'SESSION_INVALID'),
        ),
      );
    });
  });

  group('InMemoryReaderSessionStore', () {
    test('save enforces session validation before persistence', () async {
      final store = InMemoryReaderSessionStore();
      final invalid = ReaderResumeSession(
        canonicalComicId: 'not-namespaced',
        sourceRef: SourceRef.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
        ),
        chapterRefId: 'c1',
        page: 1,
      );

      await expectLater(
        () => store.save(invalid),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CANONICAL_ID_INVALID'),
        ),
      );

      final loaded = await store.load(canonicalComicId: 'not-namespaced');
      expect(loaded, isNull);
    });
  });
}
