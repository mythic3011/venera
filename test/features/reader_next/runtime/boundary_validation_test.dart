import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  group('ReaderNext runtime boundary validation', () {
    test('remote ReaderNext open request requires SourceRef', () {
      final sourceRef = SourceRef.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
        chapterRefId: '0',
      );
      final request = ReaderNextOpenRequest.remote(
        canonicalComicId: CanonicalComicId.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
        ),
        sourceRef: sourceRef,
        initialPage: 1,
      );

      expect(request.sourceRef, sourceRef);
    });

    test('bridge rejects canonical id as upstreamComicRefId', () {
      expect(
        () => SourceRef.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: 'remote:nhentai:646922',
          chapterRefId: '0',
        ),
        throwsA(isA<ReaderNextBoundaryException>()),
      );
    });
  });
}
