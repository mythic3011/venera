import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/bridge/reader_next_open_bridge.dart';
import 'package:venera/pages/comic_detail_page.dart';

void main() {
  test('feature flag default helper is strict bool true only', () {
    expect(isReaderNextEnabledSetting(true), isTrue);
    expect(isReaderNextEnabledSetting(false), isFalse);
    expect(isReaderNextEnabledSetting('true'), isFalse);
    expect(isReaderNextEnabledSetting(1), isFalse);
    expect(isReaderNextEnabledSetting(null), isFalse);
  });

  test('reader_next_enabled=false always uses explicit legacy route', () async {
    var legacyCalls = 0;
    var readerNextCalls = 0;
    var blockedCalls = 0;
    ComicDetailDryRunDiagnosticPacket? packet;

    final decision = await routeComicDetailReadOpen(
      readerNextEnabled: false,
      sourceKey: 'nhentai',
      comicId: '646922',
      chapterRefId: '0',
      onDiagnostic: (value) => packet = value,
      openLegacy: () async => legacyCalls += 1,
      openReaderNext: (_) async => readerNextCalls += 1,
      onBridgeBlocked: (_) async => blockedCalls += 1,
    );

    expect(decision, ComicDetailRouteDecision.legacy);
    expect(legacyCalls, 1);
    expect(readerNextCalls, 0);
    expect(blockedCalls, 0);
    expect(packet?.featureFlagEnabled, isFalse);
    expect(packet?.routeDecision, ComicDetailRouteDecision.legacy);
    expect(packet?.bridgeResultCode, 'legacy_route');
  });

  test(
    'comic detail entrypoint does not fall back to legacy when ReaderNext bridge blocks',
    () async {
      var legacyCalls = 0;
      var readerNextCalls = 0;
      var blockedCalls = 0;
      ReaderNextBridgeDiagnostic? blocked;
      ComicDetailDryRunDiagnosticPacket? packet;

      final decision = await routeComicDetailReadOpen(
        readerNextEnabled: true,
        sourceKey: 'nhentai',
        comicId: 'remote:nhentai:646922',
        chapterRefId: '0',
        onDiagnostic: (value) => packet = value,
        openLegacy: () async => legacyCalls += 1,
        openReaderNext: (_) async => readerNextCalls += 1,
        onBridgeBlocked: (diagnostic) async {
          blockedCalls += 1;
          blocked = diagnostic;
        },
      );

      expect(decision, ComicDetailRouteDecision.blocked);
      expect(legacyCalls, 0);
      expect(readerNextCalls, 0);
      expect(blockedCalls, 1);
      expect(
        blocked?.code,
        ReaderNextBridgeDiagnosticCode.canonicalIdInUpstreamField,
      );
      expect(packet?.featureFlagEnabled, isTrue);
      expect(packet?.routeDecision, ComicDetailRouteDecision.blocked);
      expect(
        packet?.bridgeResultCode,
        ReaderNextBridgeDiagnosticCode.canonicalIdInUpstreamField.name,
      );
    },
  );

  test('feature flag does not relax ReaderNext SourceRef validation', () async {
    var legacyCalls = 0;
    var readerNextCalls = 0;
    var blockedCalls = 0;

    final decision = await routeComicDetailReadOpen(
      readerNextEnabled: true,
      sourceKey: 'nhentai',
      comicId: 'remote:nhentai:646922',
      chapterRefId: '0',
      openLegacy: () async => legacyCalls += 1,
      openReaderNext: (_) async => readerNextCalls += 1,
      onBridgeBlocked: (_) async => blockedCalls += 1,
    );

    expect(decision, ComicDetailRouteDecision.blocked);
    expect(readerNextCalls, 0);
    expect(legacyCalls, 0);
    expect(blockedCalls, 1);
  });
}
