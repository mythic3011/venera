import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/features/reader_next/bridge/history_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';

void main() {
  ReaderActivityItem buildRemoteRow({
    String comicId = '646922',
    String chapterId = '1',
    String sourceKey = 'nhentai',
    SourceRef? sourceRef,
  }) {
    return ReaderActivityItem(
      comicId: comicId,
      title: 'Test',
      subtitle: 'Sub',
      cover: 'cover',
      sourceKey: sourceKey,
      sourceRef:
          sourceRef ??
          SourceRef.fromLegacyRemote(
            sourceKey: sourceKey,
            comicId: comicId,
            chapterId: chapterId,
          ),
      chapterId: chapterId,
      pageIndex: 3,
      lastReadAt: DateTime.utc(2026, 5, 2),
    );
  }

  test('flag off keeps legacy route decision', () {
    const controller = HistoryRouteCutoverController();
    final result = controller.evaluate(
      row: buildRemoteRow(),
      readerNextEnabled: false,
      readerNextHistoryEnabled: true,
    );
    expect(result.decision, HistoryRouteDecision.legacyExplicit);
    expect(result.diagnostic.featureFlagEnabled, isFalse);
    expect(result.diagnostic.recordIdRedacted, isNot(contains('646922')));
  });

  test('history flag cannot bypass M14 blocked decision', () {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: false,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
    );
    final result = controller.evaluate(
      row: buildRemoteRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
    );
    expect(result.decision, HistoryRouteDecision.blocked);
    expect(result.blockedReason, ReadinessBlockedReason.gateDeniedEntrypoint);
  });

  test('valid history row can become readerNextEligible when gate allows', () {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: true,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
    );
    final result = controller.evaluate(
      row: buildRemoteRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
    );
    expect(result.decision, HistoryRouteDecision.readerNextEligible);
    expect(result.bridgeResult, isNotNull);
    expect(result.diagnostic.currentSourceRefValidationCode, 'valid');
    expect(result.diagnostic.readinessArtifactSchemaVersion, 1);
  });

  test('stale current-row identity remains blocked', () {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: true,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
      rowStaleEvaluator: (_) => true,
    );
    final result = controller.evaluate(
      row: buildRemoteRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
    );
    expect(result.decision, HistoryRouteDecision.blocked);
    expect(result.blockedReason, ReadinessBlockedReason.staleIdentity);
  });

  test('canonical leak in upstream field is blocked', () {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: true,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
    );
    final row = buildRemoteRow(
      sourceRef: SourceRef(
        id: 'remote:nhentai:remote:nhentai:646922:1',
        type: SourceRefType.remote,
        sourceKey: 'nhentai',
        sourceIdentity: sourceIdentityFromKey('nhentai'),
        refId: 'remote:nhentai:646922',
        params: const {'comicId': 'remote:nhentai:646922', 'chapterId': '1'},
      ),
    );
    final result = controller.evaluate(
      row: row,
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
    );
    expect(result.decision, HistoryRouteDecision.blocked);
    expect(result.diagnostic.currentSourceRefValidationCode, 'canonicalLeakAsUpstream');
  });

  test('flag off: legacy called, readerNext not called', () async {
    const controller = HistoryRouteCutoverController();
    var legacyCalled = 0;
    var readerNextCalled = 0;
    var blockedCalled = 0;
    await routeHistoryReadOpen(
      controller: controller,
      row: buildRemoteRow(),
      readerNextEnabled: false,
      readerNextHistoryEnabled: true,
      openLegacy: () async {
        legacyCalled += 1;
      },
      openReaderNext: (_) async {
        readerNextCalled += 1;
      },
      onBlocked: (_) async {
        blockedCalled += 1;
      },
    );
    expect(legacyCalled, 1);
    expect(readerNextCalled, 0);
    expect(blockedCalled, 0);
  });

  test('flag on + eligible: readerNext called, legacy not called', () async {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: true,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
    );
    var legacyCalled = 0;
    var readerNextCalled = 0;
    var blockedCalled = 0;
    await routeHistoryReadOpen(
      controller: controller,
      row: buildRemoteRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async {
        legacyCalled += 1;
      },
      openReaderNext: (_) async {
        readerNextCalled += 1;
      },
      onBlocked: (_) async {
        blockedCalled += 1;
      },
    );
    expect(legacyCalled, 0);
    expect(readerNextCalled, 1);
    expect(blockedCalled, 0);
  });

  test('flag on + blocked: blocked called, legacy and readerNext not called', () async {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: false,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
    );
    var legacyCalled = 0;
    var readerNextCalled = 0;
    var blockedCalled = 0;
    HistoryRouteDecisionDiagnosticPacket? packet;
    await routeHistoryReadOpen(
      controller: controller,
      row: buildRemoteRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async {
        legacyCalled += 1;
      },
      openReaderNext: (_) async {
        readerNextCalled += 1;
      },
      onBlocked: (_) async {
        blockedCalled += 1;
      },
      onDiagnostic: (next) {
        packet = next;
      },
    );
    expect(legacyCalled, 0);
    expect(readerNextCalled, 0);
    expect(blockedCalled, 1);
    expect(packet, isNotNull);
    expect(packet!.readinessArtifactSchemaVersion, 1);
    expect(packet!.currentSourceRefValidationCode, isNotEmpty);
    expect(packet!.recordIdRedacted, isNot(contains('646922')));
  });

  test('blocked history route never calls legacy even when rollback flag exists', () async {
    final controller = HistoryRouteCutoverController(
      readinessArtifactProvider: () => const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: false,
        allowHistory: true,
        allowFavorites: true,
        allowDownloads: true,
      ),
    );
    var legacyCalled = 0;
    var readerNextCalled = 0;
    var blockedCalled = 0;
    HistoryRouteDecision? decision;

    decision = await routeHistoryReadOpen(
      controller: controller,
      row: buildRemoteRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async {
        legacyCalled += 1;
      },
      openReaderNext: (_) async {
        readerNextCalled += 1;
      },
      onBlocked: (_) async {
        blockedCalled += 1;
      },
    );

    expect(decision, HistoryRouteDecision.blocked);
    expect(legacyCalled, 0);
    expect(readerNextCalled, 0);
    expect(blockedCalled, 1);
  });
}
