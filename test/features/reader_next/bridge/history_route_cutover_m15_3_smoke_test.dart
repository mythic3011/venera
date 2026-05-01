import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/features/reader_next/bridge/history_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  ReaderActivityItem buildRow({
    String comicId = '646922',
    String chapterId = '1',
    String sourceKey = 'nhentai',
  }) {
    return ReaderActivityItem(
      comicId: comicId,
      title: 'Smoke',
      subtitle: 'Smoke',
      cover: 'cover',
      sourceKey: sourceKey,
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
      ),
      chapterId: chapterId,
      pageIndex: 2,
      lastReadAt: DateTime.utc(2026, 5, 2),
    );
  }

  const readyArtifact = ReadinessArtifact(
    readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
    sourceSchemaVersion: 1,
    postApplyVerified: true,
    allowHistory: true,
    allowFavorites: true,
    allowDownloads: true,
  );

  test('M15.3-T1 smoke: flag off uses explicit legacy route', () async {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => readyArtifact,
    );
    var legacy = 0;
    var executor = 0;
    var blocked = 0;
    HistoryRouteDecisionDiagnosticPacket? packet;

    final decision = await routeHistoryReadOpen(
      controller: controller,
      row: buildRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: false,
      openLegacy: () async => legacy += 1,
      openReaderNext: (_) async => executor += 1,
      onBlocked: (_) async => blocked += 1,
      onDiagnostic: (p) => packet = p,
    );

    expect(decision, HistoryRouteDecision.legacyExplicit);
    expect(legacy, 1);
    expect(executor, 0);
    expect(blocked, 0);
    expect(packet?.routeDecision, HistoryRouteDecision.legacyExplicit);
  });

  test('M15.3-T2 smoke: flag on + eligible calls approved executor once', () async {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => readyArtifact,
    );
    var legacy = 0;
    var executor = 0;
    var blocked = 0;
    HistoryRouteDecisionDiagnosticPacket? packet;

    final decision = await routeHistoryReadOpen(
      controller: controller,
      row: buildRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (_) async => executor += 1,
      onBlocked: (_) async => blocked += 1,
      onDiagnostic: (p) => packet = p,
    );

    expect(decision, HistoryRouteDecision.readerNextEligible);
    expect(legacy, 0);
    expect(executor, 1);
    expect(blocked, 0);
    expect(packet?.routeDecision, HistoryRouteDecision.readerNextEligible);
  });

  test('M15.3-T3 smoke: flag on + blocked has no legacy fallback', () async {
    const blockedArtifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => blockedArtifact,
    );
    var legacy = 0;
    var executor = 0;
    var blocked = 0;

    final decision = await routeHistoryReadOpen(
      controller: controller,
      row: buildRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (_) async => executor += 1,
      onBlocked: (_) async => blocked += 1,
    );

    expect(decision, HistoryRouteDecision.blocked);
    expect(legacy, 0);
    expect(executor, 0);
    expect(blocked, 1);
  });

  test('M15.3-T4 kill-switch does not mutate readiness or identity state', () async {
    final row = buildRow();
    final beforeRefId = row.sourceRef.refId;
    final beforeCanonical = row.sourceRef.canonicalId;
    final artifact = readyArtifact;
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => artifact,
    );

    await routeHistoryReadOpen(
      controller: controller,
      row: row,
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );
    await routeHistoryReadOpen(
      controller: controller,
      row: row,
      readerNextEnabled: true,
      readerNextHistoryEnabled: false,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );

    expect(artifact.allowHistory, isTrue);
    expect(artifact.readinessArtifactSchemaVersion, 1);
    expect(row.sourceRef.refId, beforeRefId);
    expect(row.sourceRef.canonicalId, beforeCanonical);
  });

  test('M15.3-T5 diagnostics for all decisions are redacted', () async {
    final packets = <HistoryRouteDecisionDiagnosticPacket>[];
    final eligibleController = HistoryRouteCutoverController(
      readinessArtifactProvider: () => readyArtifact,
    );
    const blockedArtifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    final blockedController = HistoryRouteCutoverController(
      readinessArtifactProvider: () => blockedArtifact,
    );

    for (final run in <Future<void> Function()>[
      () => routeHistoryReadOpen(
        controller: eligibleController,
        row: buildRow(),
        readerNextEnabled: true,
        readerNextHistoryEnabled: false,
        openLegacy: () async {},
        openReaderNext: (_) async {},
        onBlocked: (_) async {},
        onDiagnostic: packets.add,
      ),
      () => routeHistoryReadOpen(
        controller: eligibleController,
        row: buildRow(),
        readerNextEnabled: true,
        readerNextHistoryEnabled: true,
        openLegacy: () async {},
        openReaderNext: (_) async {},
        onBlocked: (_) async {},
        onDiagnostic: packets.add,
      ),
      () => routeHistoryReadOpen(
        controller: blockedController,
        row: buildRow(),
        readerNextEnabled: true,
        readerNextHistoryEnabled: true,
        openLegacy: () async {},
        openReaderNext: (_) async {},
        onBlocked: (_) async {},
        onDiagnostic: packets.add,
      ),
    ]) {
      await run();
    }

    expect(packets.map((p) => p.routeDecision).toSet(), {
      HistoryRouteDecision.legacyExplicit,
      HistoryRouteDecision.readerNextEligible,
      HistoryRouteDecision.blocked,
    });
    for (final packet in packets) {
      expect(packet.recordIdRedacted.contains('646922'), isFalse);
      expect(packet.recordIdRedacted, isNotEmpty);
    }
  });
}
