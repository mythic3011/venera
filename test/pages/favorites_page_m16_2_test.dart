import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/bridge/favorites_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/favorites_route_cutover_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

void main() {
  const readyArtifact = ReadinessArtifact(
    readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
    sourceSchemaVersion: 1,
    postApplyVerified: true,
    allowHistory: true,
    allowFavorites: true,
    allowDownloads: true,
  );

  IdentityCoverageInput favoriteInput({
    required String folderName,
    String recordId = '646922',
    String sourceKey = 'nhentai',
  }) {
    return IdentityCoverageInput.favorite(
      recordId: recordId,
      sourceKey: sourceKey,
      folderName: folderName,
      canonicalComicId: 'remote:$sourceKey:$recordId',
      sourceRef: ExplicitSourceRefSnapshot(
        sourceKey: sourceKey,
        upstreamComicRefId: recordId,
        chapterRefId: '1',
      ),
      explicitSnapshotAlreadyPersisted: true,
    );
  }

  testWidgets('M16.2-T1 favorites smoke: flag off uses explicit legacy route', (
    tester,
  ) async {
    const controller = FavoritesRouteCutoverController();
    var legacy = 0;
    var executor = 0;
    var blocked = 0;

    final decision = await routeFavoritesReadOpen(
      controller: controller,
      input: favoriteInput(folderName: 'Folder-A'),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: false,
      openLegacy: () async => legacy += 1,
      openReaderNext: (_) async => executor += 1,
      onBlocked: (_) async => blocked += 1,
    );

    expect(decision, FavoritesRouteDecision.legacyExplicit);
    expect(legacy, 1);
    expect(executor, 0);
    expect(blocked, 0);
  });

  testWidgets(
    'M16.2-T2 favorites smoke: flag on eligible dispatches executor once',
    (tester) async {
      const controller = FavoritesRouteCutoverController();
      var legacy = 0;
      var executor = 0;
      var blocked = 0;

      final decision = await routeFavoritesReadOpen(
        controller: controller,
        input: favoriteInput(folderName: 'Folder-A'),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextFavoritesEnabled: true,
        openLegacy: () async => legacy += 1,
        openReaderNext: (_) async => executor += 1,
        onBlocked: (_) async => blocked += 1,
      );

      expect(decision, FavoritesRouteDecision.readerNextEligible);
      expect(legacy, 0);
      expect(executor, 1);
      expect(blocked, 0);
    },
  );

  testWidgets('M16.2-T3 favorites smoke: blocked row does not fallback', (
    tester,
  ) async {
    const controller = FavoritesRouteCutoverController();
    var legacy = 0;
    var executor = 0;
    var blocked = 0;

    final decision = await routeFavoritesReadOpen(
      controller: controller,
      input: favoriteInput(folderName: ''),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (_) async => executor += 1,
      onBlocked: (_) async => blocked += 1,
    );

    expect(decision, FavoritesRouteDecision.blocked);
    expect(legacy, 0);
    expect(executor, 0);
    expect(blocked, 1);
  });

  test('M16.2-T4 kill-switch does not mutate readiness or identity state', () async {
    const controller = FavoritesRouteCutoverController();
    final input = favoriteInput(folderName: 'Folder-A');
    final beforeArtifactSchema = readyArtifact.readinessArtifactSchemaVersion;
    final beforeAllowFavorites = readyArtifact.allowFavorites;
    final beforeRecordId = input.recordId;
    final beforeSourceKey = input.sourceKey;
    final beforeFolderName = input.folderName;

    await routeFavoritesReadOpen(
      controller: controller,
      input: input,
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );

    await routeFavoritesReadOpen(
      controller: controller,
      input: input,
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: false,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );

    expect(readyArtifact.readinessArtifactSchemaVersion, beforeArtifactSchema);
    expect(readyArtifact.allowFavorites, beforeAllowFavorites);
    expect(input.recordId, beforeRecordId);
    expect(input.sourceKey, beforeSourceKey);
    expect(input.folderName, beforeFolderName);
  });

  testWidgets(
    'M16.2-T5 duplicate favorites in different folders remain independently decided',
    (tester) async {
      const controller = FavoritesRouteCutoverController();
      var executor = 0;
      var blocked = 0;

      final decisionA = await routeFavoritesReadOpen(
        controller: controller,
        input: favoriteInput(folderName: 'Folder-A'),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextFavoritesEnabled: true,
        openLegacy: () async {},
        openReaderNext: (_) async => executor += 1,
        onBlocked: (_) async => blocked += 1,
      );

      final decisionB = await routeFavoritesReadOpen(
        controller: controller,
        input: favoriteInput(folderName: 'Folder-B'),
        artifact: readyArtifact,
        isRowStale: true,
        readerNextEnabled: true,
        readerNextFavoritesEnabled: true,
        openLegacy: () async {},
        openReaderNext: (_) async => executor += 1,
        onBlocked: (_) async => blocked += 1,
      );

      expect(decisionA, FavoritesRouteDecision.readerNextEligible);
      expect(decisionB, FavoritesRouteDecision.blocked);
      expect(executor, 1);
      expect(blocked, 1);
    },
  );

  test('M16.2-T6 favorites diagnostics are redacted for all decisions', () async {
    const controller = FavoritesRouteCutoverController();
    final packets = <FavoritesRouteDecisionDiagnosticPacket>[];

    for (final run in <Future<void> Function()>[
      () => routeFavoritesReadOpen(
        controller: controller,
        input: favoriteInput(folderName: 'Folder-A'),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextFavoritesEnabled: false,
        openLegacy: () async {},
        openReaderNext: (_) async {},
        onBlocked: (_) async {},
        onDiagnostic: packets.add,
      ),
      () => routeFavoritesReadOpen(
        controller: controller,
        input: favoriteInput(folderName: 'Folder-A'),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextFavoritesEnabled: true,
        openLegacy: () async {},
        openReaderNext: (_) async {},
        onBlocked: (_) async {},
        onDiagnostic: packets.add,
      ),
      () => routeFavoritesReadOpen(
        controller: controller,
        input: favoriteInput(folderName: ''),
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextFavoritesEnabled: true,
        openLegacy: () async {},
        openReaderNext: (_) async {},
        onBlocked: (_) async {},
        onDiagnostic: packets.add,
      ),
    ]) {
      await run();
    }

    expect(packets.length, 3);
    for (final packet in packets) {
      expect(packet.folderName, isNotNull);
      expect(packet.readinessArtifactSchemaVersion, isNotNull);
      expect(packet.currentSourceRefValidationCode, isNotEmpty);
      expect(packet.recordIdRedacted.contains('646922'), isFalse);
      expect(packet.recordIdRedacted, isNotEmpty);
      expect(packet.sourceKey.contains('remote:'), isFalse);
    }
  });
}
