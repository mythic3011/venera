import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/bridge/favorites_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

void main() {
  const controller = FavoritesRouteCutoverController();

  IdentityCoverageInput favoriteInput({
    required String folderName,
    String recordId = '646922',
  }) {
    return IdentityCoverageInput.favorite(
      recordId: recordId,
      sourceKey: 'nhentai',
      folderName: folderName,
      canonicalComicId: 'remote:nhentai:$recordId',
      sourceRef: ExplicitSourceRefSnapshot(
        sourceKey: 'nhentai',
        upstreamComicRefId: recordId,
        chapterRefId: '1',
      ),
      explicitSnapshotAlreadyPersisted: true,
    );
  }

  test('favorites controller uses M14 + M16 preflight only', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    final result = controller.evaluate(
      input: favoriteInput(folderName: 'A'),
      artifact: artifact,
      isRowStale: false,
    );
    expect(result.decision, FavoritesRouteDecision.readerNextEligible);
    expect(result.diagnostic.recordKind, 'favorites');
    expect(result.diagnostic.folderName, 'A');
  });

  test('favorites blocked decision remains terminal (no fallback signal)', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    final result = controller.evaluate(
      input: favoriteInput(folderName: 'A'),
      artifact: artifact,
      isRowStale: false,
    );
    expect(result.decision, FavoritesRouteDecision.blocked);
    expect(result.diagnostic.blockedReason, isNot('none'));
  });

  test('favorites without folderName are blocked', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    final input = IdentityCoverageInput.favorite(
      recordId: '646922',
      sourceKey: 'nhentai',
      folderName: null,
      canonicalComicId: 'remote:nhentai:646922',
      sourceRef: const ExplicitSourceRefSnapshot(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
        chapterRefId: '1',
      ),
      explicitSnapshotAlreadyPersisted: true,
    );
    final result = controller.evaluate(
      input: input,
      artifact: artifact,
      isRowStale: false,
    );
    expect(result.decision, FavoritesRouteDecision.blocked);
    expect(
      result.diagnostic.blockedReason,
      ReadinessBlockedReason.missingFavoritesFolderName.name,
    );
  });

  test('legacyExplicit favorites calls only explicit legacy route', () async {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    var legacyCalls = 0;
    var executorCalls = 0;
    var blockedCalls = 0;

    final decision = await routeFavoritesReadOpen(
      controller: controller,
      input: favoriteInput(folderName: 'A'),
      artifact: artifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: false,
      openLegacy: () async {
        legacyCalls += 1;
      },
      openReaderNext: (_) async {
        executorCalls += 1;
      },
      onBlocked: (_) async {
        blockedCalls += 1;
      },
    );

    expect(decision, FavoritesRouteDecision.legacyExplicit);
    expect(legacyCalls, 1);
    expect(executorCalls, 0);
    expect(blockedCalls, 0);
  });

  test('eligible favorites dispatches injected executor exactly once', () async {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );
    var legacyCalls = 0;
    var executorCalls = 0;
    var blockedCalls = 0;

    final decision = await routeFavoritesReadOpen(
      controller: controller,
      input: favoriteInput(folderName: 'A'),
      artifact: artifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async {
        legacyCalls += 1;
      },
      openReaderNext: (request) async {
        executorCalls += 1;
        expect(request.sourceRef.sourceKey, 'nhentai');
        expect(request.sourceRef.upstreamComicRefId, '646922');
      },
      onBlocked: (_) async {
        blockedCalls += 1;
      },
    );

    expect(decision, FavoritesRouteDecision.readerNextEligible);
    expect(legacyCalls, 0);
    expect(executorCalls, 1);
    expect(blockedCalls, 0);
  });

  test('blocked favorites never reaches executor', () async {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: true,
      allowFavorites: false,
      allowDownloads: true,
    );
    var legacyCalls = 0;
    var executorCalls = 0;
    var blockedCalls = 0;

    final decision = await routeFavoritesReadOpen(
      controller: controller,
      input: favoriteInput(folderName: 'A'),
      artifact: artifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async {
        legacyCalls += 1;
      },
      openReaderNext: (_) async {
        executorCalls += 1;
      },
      onBlocked: (_) async {
        blockedCalls += 1;
      },
    );

    expect(decision, FavoritesRouteDecision.blocked);
    expect(legacyCalls, 0);
    expect(executorCalls, 0);
    expect(blockedCalls, 1);
  });
}
