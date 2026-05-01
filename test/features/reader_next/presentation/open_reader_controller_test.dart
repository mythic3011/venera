import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/presentation/open_reader_controller.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  ReaderNextOpenRequest buildRequest() {
    return ReaderNextOpenRequest.remote(
      canonicalComicId: CanonicalComicId.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
      ),
      sourceRef: SourceRef.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
        chapterRefId: '0',
      ),
      initialPage: 1,
    );
  }

  test('controller accepts typed ReaderNextOpenRequest path and uses it', () async {
    ReaderNextOpenRequest? captured;
    var callCount = 0;
    final controller = OpenReaderController(
      openExecutor: (request) async {
        callCount += 1;
        captured = request;
      },
    );

    final request = buildRequest();
    await controller.open(request);

    expect(callCount, 1);
    expect(identical(captured, request), isTrue);
    expect(controller.state.phase, OpenReaderPhase.opened);
    expect(controller.state.boundaryErrorCode, isNull);
  });

  test('boundary failure path is fail-closed without legacy fallback', () async {
    var callCount = 0;
    final controller = OpenReaderController(
      openExecutor: (_) async {
        callCount += 1;
        throw ReaderNextBoundaryException(
          'SOURCE_REF_REQUIRED',
          'Remote ReaderNext open request requires valid SourceRef',
        );
      },
    );

    await controller.open(buildRequest());

    expect(callCount, 1);
    expect(controller.state.phase, OpenReaderPhase.boundaryRejected);
    expect(controller.state.boundaryErrorCode, 'SOURCE_REF_REQUIRED');
    expect(
      controller.state.errorMessage,
      'Remote ReaderNext open request requires valid SourceRef',
    );
  });

  test('production open emits redacted identity fields only', () async {
    String? title;
    Map<String, String>? fields;
    final controller = OpenReaderController(
      openExecutor: (_) async {},
      productionLog: (logTitle, logFields) {
        title = logTitle;
        fields = logFields;
      },
    );
    final request = buildRequest();

    await controller.open(request);

    expect(title, 'ReaderNextOpen');
    final logged = fields;
    expect(logged, isNotNull);
    expect(logged!.keys, containsAll(<String>[
      'sourceRef.sourceKey',
      'sourceRef.upstreamComicRefId',
      'sourceRef.chapterRefId',
      'canonicalComicId',
      'upstreamComicRefId',
    ]));
    for (final value in logged.values) {
      expect(value.contains('646922'), isFalse);
      expect(value.contains('nhentai'), isFalse);
      expect(value.contains('remote:nhentai:646922'), isFalse);
    }
    expect(controller.state.phase, OpenReaderPhase.opened);
  });
}
