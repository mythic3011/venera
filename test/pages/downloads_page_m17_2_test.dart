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

  DownloadsPreflightInput buildInput({
    String recordId = 'dl-646922',
    String sourceKey = 'nhentai',
    String canonicalComicId = 'remote:nhentai:646922',
    String upstreamComicRefId = '646922',
    String chapterRefId = '1',
    String downloadSessionId = 'session-1',
    DownloadsSourceRefSnapshot? sourceRef,
    String localPath = '/downloads/nhentai/646922/chapter-1.cbz',
    String cachePath = '/cache/nhentai/646922/chapter-1',
  }) {
    return DownloadsPreflightInput(
      recordId: recordId,
      sourceKey: sourceKey,
      canonicalComicId: canonicalComicId,
      sourceRef:
          sourceRef ??
          DownloadsSourceRefSnapshot(
            sourceKey: sourceKey,
            upstreamComicRefId: upstreamComicRefId,
            chapterRefId: chapterRefId,
          ),
      downloadSessionId: downloadSessionId,
      localPath: localPath,
      cachePath: cachePath,
    );
  }

  testWidgets('M17.2-T1 downloads smoke: flag off uses explicit legacy route', (
    tester,
  ) async {
    var legacy = 0;
    var blocked = 0;
    var eligible = 0;

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: false,
      openLegacy: () async => legacy += 1,
      onBlocked: (_) async => blocked += 1,
      onEligible: (_) async => eligible += 1,
    );

    expect(decision, DownloadsRouteDecision.legacyExplicit);
    expect(legacy, 1);
    expect(blocked, 0);
    expect(eligible, 0);
  });

  testWidgets('M17.2-T2 downloads smoke: flag on eligible is prepared only', (
    tester,
  ) async {
    var legacy = 0;
    var blocked = 0;
    var eligible = 0;
    DownloadsRouteCutoverResult? eligibleResult;

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacy += 1,
      onBlocked: (_) async => blocked += 1,
      onEligible: (result) async {
        eligible += 1;
        eligibleResult = result;
      },
    );

    expect(decision, DownloadsRouteDecision.readerNextEligible);
    expect(legacy, 0);
    expect(blocked, 0);
    expect(eligible, 1);
    expect(eligibleResult, isNotNull);
    expect(
      eligibleResult!.diagnostic.currentSourceRefValidationCode,
      DownloadsSourceRefValidationCode.valid,
    );
    expect(eligibleResult!.preflightResult, isNotNull);
    expect(eligibleResult!.preflightResult!.candidate, isNotNull);
  });

  testWidgets('M17.2-T3 downloads smoke: blocked row does not fallback', (
    tester,
  ) async {
    var legacy = 0;
    var blocked = 0;
    var eligible = 0;

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(
        sourceRef: const DownloadsSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: 'remote:nhentai:646922',
          chapterRefId: '1',
        ),
      ),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacy += 1,
      onBlocked: (_) async => blocked += 1,
      onEligible: (_) async => eligible += 1,
    );

    expect(decision, DownloadsRouteDecision.blocked);
    expect(legacy, 0);
    expect(blocked, 1);
    expect(eligible, 0);
  });

  test('M17.2-T4 kill-switch does not mutate readiness or identity state', () async {
    final input = buildInput();
    final beforeSchema = readyArtifact.readinessArtifactSchemaVersion;
    final beforeAllowDownloads = readyArtifact.allowDownloads;
    final beforeRecordId = input.recordId;
    final beforeCanonical = input.canonicalComicId;
    final beforeUpstream = input.sourceRef!.upstreamComicRefId;
    final beforeSession = input.downloadSessionId;

    await routeDownloadsReadOpen(
      controller: controller,
      input: input,
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (_) async {},
    );
    await routeDownloadsReadOpen(
      controller: controller,
      input: input,
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: false,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (_) async {},
    );

    expect(readyArtifact.readinessArtifactSchemaVersion, beforeSchema);
    expect(readyArtifact.allowDownloads, beforeAllowDownloads);
    expect(input.recordId, beforeRecordId);
    expect(input.canonicalComicId, beforeCanonical);
    expect(input.sourceRef!.upstreamComicRefId, beforeUpstream);
    expect(input.downloadSessionId, beforeSession);
  });

  test('M17.2-T5 downloads diagnostics are redacted for all route decisions', () async {
    final packets = <DownloadsRouteDecisionDiagnosticPacket>[];

    for (final run in <Future<void> Function()>[
      () => routeDownloadsReadOpen(
        controller: controller,
        input: buildInput(recordId: 'dl-646922', downloadSessionId: 'session-1'),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextDownloadsEnabled: false,
        openLegacy: () async {},
        onBlocked: (_) async {},
        onEligible: (_) async {},
        onDiagnostic: packets.add,
      ),
      () => routeDownloadsReadOpen(
        controller: controller,
        input: buildInput(recordId: 'dl-646922', downloadSessionId: 'session-1'),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextDownloadsEnabled: true,
        openLegacy: () async {},
        onBlocked: (_) async {},
        onEligible: (_) async {},
        onDiagnostic: packets.add,
      ),
      () => routeDownloadsReadOpen(
        controller: controller,
        input: buildInput(
          sourceRef: const DownloadsSourceRefSnapshot(
            sourceKey: 'nhentai',
            upstreamComicRefId: 'remote:nhentai:646922',
            chapterRefId: '1',
          ),
        ),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextDownloadsEnabled: true,
        openLegacy: () async {},
        onBlocked: (_) async {},
        onEligible: (_) async {},
        onDiagnostic: packets.add,
      ),
    ]) {
      await run();
    }

    expect(packets.length, 3);
    for (final packet in packets) {
      expect(packet.recordIdRedacted.contains('646922'), isFalse);
      expect(packet.downloadSessionIdRedacted?.contains('session-1'), isFalse);
      expect(packet.sourceKey.contains('remote:'), isFalse);
      expect(packet.blockedReason.contains('/downloads/'), isFalse);
    }
  });

  test('M17.2-T6 eligible prepared output still exposes no ReaderNextOpenRequest', () async {
    DownloadsRouteCutoverResult? eligibleResult;
    await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (result) async => eligibleResult = result,
    );

    expect(eligibleResult, isNotNull);
    expect(eligibleResult!.decision, DownloadsRouteDecision.readerNextEligible);
    expect(eligibleResult!.preflightResult, isNotNull);
    expect(eligibleResult!.diagnostic.routeDecision, DownloadsRouteDecision.readerNextEligible);
    expect(eligibleResult!.preflightResult!.candidate, isNotNull);
  });
}
