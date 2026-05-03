import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/bridge/downloads_route_cutover_controller.dart';
import 'package:venera/features/reader_next/bridge/favorites_route_cutover_controller.dart';
import 'package:venera/features/reader_next/bridge/history_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/downloads_route_readiness_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/foundation/sources/source_ref.dart';

void main() {
  const historyController = HistoryRouteCutoverController(
    readinessArtifactProvider: _readyArtifactProvider,
  );
  const favoritesController = FavoritesRouteCutoverController();
  const downloadsController = DownloadsRouteCutoverController();

  ReaderActivityItem historyRow({
    String comicId = '646922',
    String sourceKey = 'nhentai',
    String chapterId = '1',
  }) {
    return ReaderActivityItem(
      comicId: comicId,
      title: 'History',
      subtitle: 'History',
      cover: 'cover',
      sourceKey: sourceKey,
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
      ),
      chapterId: chapterId,
      pageIndex: 1,
      lastReadAt: DateTime.utc(2026, 5, 2),
    );
  }

  IdentityCoverageInput favoritesInput({
    String folderName = 'Folder-A',
    String recordId = '646922',
    String sourceKey = 'nhentai',
    String upstreamId = '646922',
  }) {
    return IdentityCoverageInput.favorite(
      recordId: recordId,
      sourceKey: sourceKey,
      folderName: folderName,
      canonicalComicId: 'remote:$sourceKey:$upstreamId',
      sourceRef: ExplicitSourceRefSnapshot(
        sourceKey: sourceKey,
        upstreamComicRefId: upstreamId,
        chapterRefId: '1',
      ),
      explicitSnapshotAlreadyPersisted: true,
    );
  }

  DownloadsPreflightInput downloadsInput({
    String recordId = 'dl-646922',
    String sourceKey = 'nhentai',
    String upstreamId = '646922',
  }) {
    return DownloadsPreflightInput(
      recordId: recordId,
      sourceKey: sourceKey,
      canonicalComicId: 'remote:$sourceKey:$upstreamId',
      sourceRef: DownloadsSourceRefSnapshot(
        sourceKey: sourceKey,
        upstreamComicRefId: upstreamId,
        chapterRefId: '1',
      ),
      downloadSessionId: 'session-1',
      localPath: '/downloads/$sourceKey/$recordId/1.cbz',
      cachePath: '/cache/$sourceKey/$recordId/1',
      archivePath: '/archive/$sourceKey/$recordId/1.cbz',
      filename: '1.cbz',
      sourceUrl: 'https://example.invalid/$sourceKey/$recordId/1',
    );
  }

  testWidgets('M19 flag-off matrix uses explicit legacy route only', (
    tester,
  ) async {
    var legacy = 0;
    var executor = 0;
    var blocked = 0;
    final approved = resolveApprovedReaderNextExecutor(
      injectedExecutor: (_) async => executor += 1,
    );

    await routeHistoryReadOpen(
      controller: historyController,
      row: historyRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: false,
      openLegacy: () async => legacy += 1,
      openReaderNext: (request) async =>
          dispatchApprovedReaderNextExecutor(request: request, executor: approved),
      onBlocked: (_) async => blocked += 1,
    );
    await routeFavoritesReadOpen(
      controller: favoritesController,
      input: favoritesInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: false,
      openLegacy: () async => legacy += 1,
      openReaderNext: (request) async =>
          dispatchApprovedReaderNextExecutor(request: request, executor: approved),
      onBlocked: (_) async => blocked += 1,
    );
    await routeDownloadsReadOpen(
      controller: downloadsController,
      input: downloadsInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: false,
      openLegacy: () async => legacy += 1,
      onBlocked: (_) async => blocked += 1,
      onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
        result: result,
        executor: approved,
      ),
    );

    expect(legacy, 3);
    expect(executor, 0);
    expect(blocked, 0);
  });

  testWidgets('M19 eligible matrix dispatches approved executor exactly once', (
    tester,
  ) async {
    var legacy = 0;
    var executor = 0;
    var blocked = 0;
    final approved = resolveApprovedReaderNextExecutor(
      injectedExecutor: (_) async => executor += 1,
    );

    await routeHistoryReadOpen(
      controller: historyController,
      row: historyRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (request) async =>
          dispatchApprovedReaderNextExecutor(request: request, executor: approved),
      onBlocked: (_) async => blocked += 1,
    );
    await routeFavoritesReadOpen(
      controller: favoritesController,
      input: favoritesInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (request) async =>
          dispatchApprovedReaderNextExecutor(request: request, executor: approved),
      onBlocked: (_) async => blocked += 1,
    );
    await routeDownloadsReadOpen(
      controller: downloadsController,
      input: downloadsInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacy += 1,
      onBlocked: (_) async => blocked += 1,
      onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
        result: result,
        executor: approved,
      ),
    );

    expect(legacy, 0);
    expect(executor, 3);
    expect(blocked, 0);
  });

  testWidgets('M19 blocked matrix is terminal for every entrypoint', (
    tester,
  ) async {
    var legacy = 0;
    var executor = 0;
    var blocked = 0;
    final approved = resolveApprovedReaderNextExecutor(
      injectedExecutor: (_) async => executor += 1,
    );
    const blockedArtifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: true,
      allowFavorites: true,
      allowDownloads: true,
    );

    final blockedHistoryController = HistoryRouteCutoverController(
      readinessArtifactProvider: () => blockedArtifact,
    );
    await routeHistoryReadOpen(
      controller: blockedHistoryController,
      row: historyRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (request) async =>
          dispatchApprovedReaderNextExecutor(request: request, executor: approved),
      onBlocked: (_) async => blocked += 1,
    );
    await routeFavoritesReadOpen(
      controller: favoritesController,
      input: favoritesInput(),
      artifact: blockedArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async => legacy += 1,
      openReaderNext: (request) async =>
          dispatchApprovedReaderNextExecutor(request: request, executor: approved),
      onBlocked: (_) async => blocked += 1,
    );
    await routeDownloadsReadOpen(
      controller: downloadsController,
      input: downloadsInput(upstreamId: 'remote:nhentai:646922'),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacy += 1,
      onBlocked: (_) async => blocked += 1,
      onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
        result: result,
        executor: approved,
      ),
    );

    expect(legacy, 0);
    expect(executor, 0);
    expect(blocked, 3);
  });

  test('M19 rollback matrix keeps entrypoint kill-switches independent', () async {
    final historyOff = await routeHistoryReadOpen(
      controller: historyController,
      row: historyRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: false,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );
    final favoritesOn = await routeFavoritesReadOpen(
      controller: favoritesController,
      input: favoritesInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );
    final downloadsOn = await routeDownloadsReadOpen(
      controller: downloadsController,
      input: downloadsInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (_) async {},
    );

    expect(historyOff, HistoryRouteDecision.legacyExplicit);
    expect(favoritesOn, FavoritesRouteDecision.readerNextEligible);
    expect(downloadsOn, DownloadsRouteDecision.readerNextEligible);
  });

  test('M19 rollback does not mutate readiness or identity state', () async {
    final history = historyRow();
    final favorites = favoritesInput();
    final downloads = downloadsInput();
    final beforeHistoryCanonical = history.sourceRef.canonicalId;
    final beforeFavoritesCanonical = favorites.canonicalComicId;
    final beforeDownloadsCanonical = downloads.canonicalComicId;
    final beforeReadinessSchema = _readyArtifact.readinessArtifactSchemaVersion;
    final beforeAllowHistory = _readyArtifact.allowHistory;
    final beforeAllowFavorites = _readyArtifact.allowFavorites;
    final beforeAllowDownloads = _readyArtifact.allowDownloads;

    await routeHistoryReadOpen(
      controller: historyController,
      row: history,
      readerNextEnabled: true,
      readerNextHistoryEnabled: false,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );
    await routeFavoritesReadOpen(
      controller: favoritesController,
      input: favorites,
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: false,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
    );
    await routeDownloadsReadOpen(
      controller: downloadsController,
      input: downloads,
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: false,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (_) async {},
    );

    expect(history.sourceRef.canonicalId, beforeHistoryCanonical);
    expect(favorites.canonicalComicId, beforeFavoritesCanonical);
    expect(downloads.canonicalComicId, beforeDownloadsCanonical);
    expect(_readyArtifact.readinessArtifactSchemaVersion, beforeReadinessSchema);
    expect(_readyArtifact.allowHistory, beforeAllowHistory);
    expect(_readyArtifact.allowFavorites, beforeAllowFavorites);
    expect(_readyArtifact.allowDownloads, beforeAllowDownloads);
  });

  test('M19 diagnostics are redacted for all entrypoints and decisions', () async {
    final packets = <Object>[];
    await routeHistoryReadOpen(
      controller: historyController,
      row: historyRow(),
      readerNextEnabled: true,
      readerNextHistoryEnabled: true,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
      onDiagnostic: packets.add,
    );
    await routeFavoritesReadOpen(
      controller: favoritesController,
      input: favoritesInput(upstreamId: 'remote:nhentai:646922'),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextFavoritesEnabled: true,
      openLegacy: () async {},
      openReaderNext: (_) async {},
      onBlocked: (_) async {},
      onDiagnostic: packets.add,
    );
    await routeDownloadsReadOpen(
      controller: downloadsController,
      input: downloadsInput(),
      artifact: _readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (_) async {},
      onDiagnostic: packets.add,
    );

    expect(packets.length, 3);
    for (final packet in packets) {
      final raw = packet.toString();
      expect(raw.contains('646922'), isFalse);
      expect(raw.contains('/downloads/'), isFalse);
      expect(raw.contains('remote:nhentai'), isFalse);
      expect(raw.contains('session-1'), isFalse);
    }
  });

  test('M19 pages do not own route authority or identity construction', () {
    final pagePaths = <String>[
      'lib/pages/history_page.dart',
      'lib/pages/favorites/favorites_page.dart',
      'lib/pages/favorites/local_favorites_page.dart',
      'lib/pages/downloading_page.dart',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'ReaderNextOpenRequest(',
      'SourceRef.',
      'features/reader_next/runtime',
      'features/reader_next/presentation',
      'IdentityCoverageReport',
      'BackfillApplyPlan',
    ];
    final violations = <String, List<String>>{};
    for (final path in pagePaths) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final content = file.readAsStringSync();
      final found = forbidden.where(content.contains).toList();
      if (found.isNotEmpty) {
        violations[path] = found;
      }
    }
    expect(violations, isEmpty);
  });
}

ReadinessArtifact _readyArtifactProvider() => _readyArtifact;

const ReadinessArtifact _readyArtifact = ReadinessArtifact(
  readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
  sourceSchemaVersion: 1,
  postApplyVerified: true,
  allowHistory: true,
  allowFavorites: true,
  allowDownloads: true,
);
