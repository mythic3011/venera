import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/bridge/reader_next_open_bridge.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  group('ReaderNextOpenBridge', () {
    const bridge = ReaderNextOpenBridge();

    test('valid remote mapping creates ReaderNextOpenRequest with canonical + SourceRef', () {
      final request = bridge.toOpenRequest(
        input: const ReaderNextBridgeInput(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
          chapterRefId: '0',
          initialPage: 1,
        ),
      );

      expect(request.canonicalComicId.value, 'remote:nhentai:646922');
      expect(request.sourceRef.isRemote, isTrue);
      expect(request.sourceRef.sourceKey, 'nhentai');
      expect(request.sourceRef.upstreamComicRefId, '646922');
      expect(request.sourceRef.chapterRefId, '0');
      expect(request.initialPage, 1);
    });

    test('missing/malformed SourceRef fields fail closed with ReaderNextBoundaryException', () {
      expect(
        () => bridge.toOpenRequest(
          input: const ReaderNextBridgeInput(
            sourceKey: null,
            upstreamComicRefId: '646922',
            chapterRefId: '0',
          ),
        ),
        throwsA(
          isA<ReaderNextBoundaryException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID'),
        ),
      );

      expect(
        () => bridge.toOpenRequest(
          input: const ReaderNextBridgeInput(
            sourceKey: 'nhentai',
            upstreamComicRefId: 'remote:nhentai:646922',
            chapterRefId: '0',
          ),
        ),
        throwsA(
          isA<ReaderNextBoundaryException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID'),
        ),
      );

      expect(
        () => bridge.toOpenRequest(
          input: const ReaderNextBridgeInput(
            sourceKey: 'nhentai',
            upstreamComicRefId: '646922',
            chapterRefId: '',
          ),
        ),
        throwsA(
          isA<ReaderNextBoundaryException>()
              .having((e) => e.code, 'code', 'SOURCE_REF_INVALID'),
        ),
      );
    });

    test('ReaderNext bridge does not silently normalize canonical upstream id', () {
      final result = ReaderNextOpenBridge.fromLegacyRemote(
        sourceKey: 'nhentai',
        comicId: 'remote:nhentai:646922',
        chapterId: '0',
      );

      expect(result.isBlocked, isTrue);
      expect(
        result.diagnostic?.code,
        ReaderNextBridgeDiagnosticCode.canonicalIdInUpstreamField,
      );
    });
  });
}
