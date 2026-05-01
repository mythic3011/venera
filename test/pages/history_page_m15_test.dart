import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/pages/history_page.dart';

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

  testWidgets(
    'HistoryPage uses approved default ReaderNext executor when none injected',
    (tester) async {
      var approvedFactoryCalls = 0;
      var approvedExecutorCalls = 0;
      final request = sampleRequest();

      final executor = resolveHistoryReaderNextExecutor(
        approvedFactory: () {
          approvedFactoryCalls += 1;
          return (ReaderNextOpenRequest req) async {
            approvedExecutorCalls += 1;
            expect(identical(req, request), isTrue);
          };
        },
      );
      await executor(request);

      expect(approvedFactoryCalls, 1);
      expect(approvedExecutorCalls, 1);
    },
  );

  testWidgets(
    'HistoryPage injected executor overrides default executor',
    (tester) async {
      var defaultFactoryCalls = 0;
      var fakeExecutorCalls = 0;
      final request = sampleRequest();

      Future<void> fakeExecutor(ReaderNextOpenRequest req) async {
        fakeExecutorCalls += 1;
        expect(identical(req, request), isTrue);
      }
      final resolved = resolveHistoryReaderNextExecutor(
        injectedExecutor: fakeExecutor,
        approvedFactory: () {
          defaultFactoryCalls += 1;
          return (_) async {};
        },
      );

      await resolved(request);
      expect(fakeExecutorCalls, 1);
      expect(defaultFactoryCalls, 0);
    },
  );
}
