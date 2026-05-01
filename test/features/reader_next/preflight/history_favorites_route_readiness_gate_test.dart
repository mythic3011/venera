import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/backfill/explicit_identity_backfill_apply.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

void main() {
  const gate = ReaderNextRouteReadinessGate();

  IdentityCoverageResult buildRow({
    required String recordId,
    required SourceRefValidationCode code,
    IdentityRecordKind kind = IdentityRecordKind.history,
    String? folderName,
  }) {
    return IdentityCoverageResult(
      kind: kind,
      recordId: recordId,
      sourceRefValidationCode: code,
      remediationAction: RemediationAction.none,
      sourceKey: 'nhentai',
      hasSourceRef: code == SourceRefValidationCode.valid,
      folderName: folderName,
      observedIdentityFingerprint: 'fp-$recordId',
      canonicalComicIdRedacted: 're***22',
      upstreamComicRefIdRedacted: '64***22',
      chapterRefIdRedacted: '<redacted>',
    );
  }

  test(
    'M14-T1 readiness artifact model supports explicit per-entrypoint booleans',
    () {
      const artifact = ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: true,
        allowHistory: false,
        allowFavorites: true,
        allowDownloads: false,
      );
      final decision = gate.evaluateArtifact(artifact);
      expect(decision.enableHistory, isFalse);
      expect(decision.enableFavorites, isTrue);
      expect(decision.enableDownloads, isFalse);
    },
  );

  test('M14-T2 gate matrix evaluates history/favorites separately', () {
    final denied = gate.evaluateArtifact(
      const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: false,
        allowHistory: true,
        allowFavorites: true,
        allowDownloads: true,
      ),
    );
    expect(denied.enableHistory, isFalse);
    expect(denied.enableFavorites, isFalse);
    expect(denied.enableDownloads, isFalse);

    final split = gate.evaluateArtifact(
      const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: 1,
        postApplyVerified: true,
        allowHistory: true,
        allowFavorites: false,
        allowDownloads: false,
      ),
    );
    expect(split.enableHistory, isTrue);
    expect(split.enableFavorites, isFalse);
    expect(split.enableDownloads, isFalse);
  });

  test(
    'readiness gate does not enable favorites when only history is ready',
    () {
      final artifact = gate.fromPostApplyResult(
        verify: const BackfillPostApplyVerifierResult(
          validAppliedCount: 8,
          invalidAppliedCount: 0,
        ),
        requestedHistoryEnable: true,
        requestedFavoritesEnable: false,
        requestedDownloadsEnable: false,
      );
      final decision = gate.evaluateArtifact(artifact);
      expect(decision.enableHistory, isTrue);
      expect(decision.enableFavorites, isFalse);
      expect(decision.enableDownloads, isFalse);
    },
  );

  test(
    'M14-T3 blocked-route policy blocks invalid rows and never falls back',
    () {
      const readiness = RouteReadinessDecision(
        enableHistory: true,
        enableFavorites: true,
        enableDownloads: false,
      );
      final packet = gate.evaluateOpenAttempt(
        entrypoint: ReaderNextEntrypoint.history,
        artifact: const ReadinessArtifact(
          readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
          sourceSchemaVersion: m13ExpectedReportSchemaVersion,
          postApplyVerified: true,
          allowHistory: true,
          allowFavorites: true,
          allowDownloads: false,
        ),
        readiness: readiness,
        featureFlagEnabled: true,
        row: buildRow(recordId: 'h-1', code: SourceRefValidationCode.missing),
        isRowStale: false,
      );
      expect(packet.routeDecision, RouteDecision.blocked);
      expect(packet.blockedReason, ReadinessBlockedReason.missingSourceRef);
    },
  );

  test('M14-T5 dry-run route decision packet is emitted per open attempt', () {
    const readiness = RouteReadinessDecision(
      enableHistory: false,
      enableFavorites: false,
      enableDownloads: false,
    );
    final packet = gate.evaluateOpenAttempt(
      entrypoint: ReaderNextEntrypoint.favorites,
      artifact: const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: m13ExpectedReportSchemaVersion,
        postApplyVerified: true,
        allowHistory: false,
        allowFavorites: false,
        allowDownloads: false,
      ),
      readiness: readiness,
      featureFlagEnabled: true,
      row: buildRow(recordId: 'fav-1', code: SourceRefValidationCode.valid),
      isRowStale: false,
      candidateId: 'cand-1',
    );
    expect(packet.entrypoint, ReaderNextEntrypoint.favorites);
    expect(packet.routeDecision, RouteDecision.blocked);
    expect(packet.blockedReason, ReadinessBlockedReason.gateDeniedEntrypoint);
    expect(packet.featureFlagEnabled, isTrue);
    expect(packet.recordId, 'fav-1');
    expect(packet.sourceKey, 'nhentai');
    expect(packet.candidateId, 'cand-1');
    expect(packet.readinessArtifactSchemaVersion, 1);
  });

  test('M14-T6 allowlist is initially disabled', () {
    final artifact = gate.fromPostApplyResult(
      verify: const BackfillPostApplyVerifierResult(
        validAppliedCount: 10,
        invalidAppliedCount: 0,
      ),
      requestedHistoryEnable: false,
      requestedFavoritesEnable: false,
      requestedDownloadsEnable: false,
    );
    final decision = gate.evaluateArtifact(artifact);
    expect(decision.enableHistory, isFalse);
    expect(decision.enableFavorites, isFalse);
    expect(decision.enableDownloads, isFalse);
  });

  test(
    'feature flag controls route selection only, stale identity remains blocked',
    () {
      const readiness = RouteReadinessDecision(
        enableHistory: true,
        enableFavorites: true,
        enableDownloads: false,
      );
      final packet = gate.evaluateOpenAttempt(
        entrypoint: ReaderNextEntrypoint.history,
        artifact: const ReadinessArtifact(
          readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
          sourceSchemaVersion: m13ExpectedReportSchemaVersion,
          postApplyVerified: true,
          allowHistory: true,
          allowFavorites: true,
          allowDownloads: false,
        ),
        readiness: readiness,
        featureFlagEnabled: true,
        row: buildRow(recordId: 'h-2', code: SourceRefValidationCode.valid),
        isRowStale: true,
      );
      expect(packet.routeDecision, RouteDecision.blocked);
      expect(packet.blockedReason, ReadinessBlockedReason.staleIdentity);
    },
  );

  test(
    'readiness gate treats stale post-apply identity as blocked even if M13 apply report was successful',
    () {
      final artifact = gate.fromPostApplyResult(
        verify: const BackfillPostApplyVerifierResult(
          validAppliedCount: 10,
          invalidAppliedCount: 0,
        ),
        requestedHistoryEnable: true,
        requestedFavoritesEnable: true,
        requestedDownloadsEnable: false,
      );
      final readiness = gate.evaluateArtifact(artifact);
      expect(readiness.enableHistory, isTrue);
      final packet = gate.evaluateOpenAttempt(
        entrypoint: ReaderNextEntrypoint.history,
        artifact: artifact,
        readiness: readiness,
        featureFlagEnabled: true,
        row: buildRow(recordId: 'h-3', code: SourceRefValidationCode.valid),
        isRowStale: true,
      );
      expect(packet.routeDecision, RouteDecision.blocked);
      expect(packet.blockedReason, ReadinessBlockedReason.staleIdentity);
    },
  );

  test(
    'downloads readiness decision is independent from history/favorites',
    () {
      final artifact = gate.fromPostApplyResult(
        verify: const BackfillPostApplyVerifierResult(
          validAppliedCount: 4,
          invalidAppliedCount: 0,
        ),
        requestedHistoryEnable: false,
        requestedFavoritesEnable: false,
        requestedDownloadsEnable: true,
      );
      final decision = gate.evaluateArtifact(artifact);
      expect(decision.enableHistory, isFalse);
      expect(decision.enableFavorites, isFalse);
      expect(decision.enableDownloads, isTrue);
    },
  );

  test('unknown readiness artifact schema disables all entrypoints', () {
    final decision = gate.evaluateArtifact(
      const ReadinessArtifact(
        readinessArtifactSchemaVersion: 99,
        sourceSchemaVersion: m13ExpectedReportSchemaVersion,
        postApplyVerified: true,
        allowHistory: true,
        allowFavorites: true,
        allowDownloads: true,
      ),
    );
    expect(decision.enableHistory, isFalse);
    expect(decision.enableFavorites, isFalse);
    expect(decision.enableDownloads, isFalse);
  });

  test('favorites row without folderName is blocked', () {
    const readiness = RouteReadinessDecision(
      enableHistory: false,
      enableFavorites: true,
      enableDownloads: false,
    );
    final packet = gate.evaluateOpenAttempt(
      entrypoint: ReaderNextEntrypoint.favorites,
      artifact: const ReadinessArtifact(
        readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
        sourceSchemaVersion: m13ExpectedReportSchemaVersion,
        postApplyVerified: true,
        allowHistory: false,
        allowFavorites: true,
        allowDownloads: false,
      ),
      readiness: readiness,
      featureFlagEnabled: true,
      row: buildRow(
        recordId: 'fav-2',
        code: SourceRefValidationCode.valid,
        kind: IdentityRecordKind.favorite,
      ),
      isRowStale: false,
    );
    expect(packet.routeDecision, RouteDecision.blocked);
    expect(
      packet.blockedReason,
      ReadinessBlockedReason.missingFavoritesFolderName,
    );
  });
}
