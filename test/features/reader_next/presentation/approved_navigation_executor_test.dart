import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/presentation/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  ReaderNextOpenRequest sampleRequest() {
    return ReaderNextOpenRequest.remote(
      canonicalComicId: CanonicalComicId.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
      ),
      sourceRef: SourceRef.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
        chapterRefId: '1',
      ),
      initialPage: 1,
    );
  }

  test('approved executor accepts ReaderNextOpenRequest and opens', () async {
    var callCount = 0;
    final executor = ApprovedReaderNextNavigationExecutor(
      openExecutor: (_) async => callCount += 1,
    ).build();

    await executor(sampleRequest());
    expect(callCount, 1);
  });

  test('approved executor rejects malformed/unvalidated open result', () async {
    final executor = ApprovedReaderNextNavigationExecutor(
      openExecutor: (_) async {
        throw ReaderNextBoundaryException('SOURCE_REF_INVALID', 'blocked');
      },
    ).build();

    await expectLater(
      () => executor(sampleRequest()),
      throwsA(isA<ReaderNextBoundaryException>()),
    );
  });
}
