import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/bridge/downloads_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/downloads_route_readiness_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

void main() {
  const controller = DownloadsRouteCutoverController();
  const readyArtifact = ReadinessArtifact(
    readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
    sourceSchemaVersion: 1,
    postApplyVerified: true,
    allowHistory: false,
    allowFavorites: false,
    allowDownloads: true,
  );

  DownloadsPreflightInput input({
    String recordId = 'dl-646922',
    String sourceKey = 'nhentai',
    String canonicalComicId = 'remote:nhentai:646922',
    String upstreamComicRefId = '646922',
    String chapterRefId = '1',
    String? downloadSessionId = 'session-1',
  }) {
    return DownloadsPreflightInput(
      recordId: recordId,
      sourceKey: sourceKey,
      canonicalComicId: canonicalComicId,
      sourceRef: DownloadsSourceRefSnapshot(
        sourceKey: sourceKey,
        upstreamComicRefId: upstreamComicRefId,
        chapterRefId: chapterRefId,
      ),
      downloadSessionId: downloadSessionId,
    );
  }

  test('downloads controller uses only M14 + M17 preflight authority', () {
    final result = controller.evaluate(
      input: input(),
      artifact: readyArtifact,
      isRowStale: false,
      featureFlagEnabled: true,
    );
    expect(result.decision, DownloadsRouteDecision.readerNextEligible);
    expect(result.diagnostic.entrypoint, 'downloads');
    expect(
      result.diagnostic.currentSourceRefValidationCode,
      DownloadsSourceRefValidationCode.valid,
    );
  });

  test('downloads legacyExplicit path calls explicit legacy route only', () async {
    var legacyCalls = 0;
    var blockedCalls = 0;
    var eligibleCalls = 0;

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: input(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: false,
      openLegacy: () async => legacyCalls += 1,
      onBlocked: (_) async => blockedCalls += 1,
      onEligible: (_) async => eligibleCalls += 1,
    );

    expect(decision, DownloadsRouteDecision.legacyExplicit);
    expect(legacyCalls, 1);
    expect(blockedCalls, 0);
    expect(eligibleCalls, 0);
  });

  test('downloads blocked path is terminal (no fallback)', () async {
    var legacyCalls = 0;
    var blockedCalls = 0;
    var eligibleCalls = 0;

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: input(upstreamComicRefId: 'remote:nhentai:646922'),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacyCalls += 1,
      onBlocked: (_) async => blockedCalls += 1,
      onEligible: (_) async => eligibleCalls += 1,
    );

    expect(decision, DownloadsRouteDecision.blocked);
    expect(legacyCalls, 0);
    expect(blockedCalls, 1);
    expect(eligibleCalls, 0);
  });

  test('downloads eligible path is prepared-only in M17.1', () async {
    var legacyCalls = 0;
    var blockedCalls = 0;
    var eligibleCalls = 0;
    DownloadsRouteCutoverResult? eligibleResult;

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: input(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacyCalls += 1,
      onBlocked: (_) async => blockedCalls += 1,
      onEligible: (result) async {
        eligibleCalls += 1;
        eligibleResult = result;
      },
    );

    expect(decision, DownloadsRouteDecision.readerNextEligible);
    expect(legacyCalls, 0);
    expect(blockedCalls, 0);
    expect(eligibleCalls, 1);
    expect(eligibleResult?.preflightResult, isNotNull);
    expect(
      eligibleResult?.diagnostic.currentSourceRefValidationCode,
      DownloadsSourceRefValidationCode.valid,
    );
  });

  test('downloads diagnostics are redacted', () async {
    DownloadsRouteDecisionDiagnosticPacket? packet;
    await routeDownloadsReadOpen(
      controller: controller,
      input: input(recordId: 'dl-646922', downloadSessionId: 'session-raw-1'),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (_) async {},
      onDiagnostic: (p) => packet = p,
    );

    expect(packet, isNotNull);
    expect(packet!.recordIdRedacted.contains('646922'), isFalse);
    expect(packet!.downloadSessionIdRedacted?.contains('session-raw-1'), isFalse);
    expect(packet!.sourceKey, 'nhentai');
    expect(packet!.candidateId, isNotEmpty);
  });
}
