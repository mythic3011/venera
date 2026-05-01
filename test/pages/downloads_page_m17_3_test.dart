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
      localPath: '/downloads/$sourceKey/$recordId/$chapterRefId.cbz',
      cachePath: '/cache/$sourceKey/$recordId/$chapterRefId',
    );
  }

  testWidgets('eligible downloads dispatches injected executor exactly once', (
    tester,
  ) async {
    var legacyCalls = 0;
    var blockedCalls = 0;
    var executorCalls = 0;
    DownloadsRouteCutoverResult? seen;

    final resolved = resolveDownloadsReaderNextExecutor(
      injectedExecutor: (_) async {
        executorCalls += 1;
      },
    );

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacyCalls += 1,
      onBlocked: (_) async => blockedCalls += 1,
      onEligible: (result) async {
        seen = result;
        await dispatchDownloadsEligibleToExecutor(
          result: result,
          executor: resolved!,
        );
      },
    );

    expect(decision, DownloadsRouteDecision.readerNextEligible);
    expect(legacyCalls, 0);
    expect(blockedCalls, 0);
    expect(executorCalls, 1);
    expect(seen?.preflightResult?.candidate, isNotNull);
  });

  testWidgets('blocked downloads never reaches executor or legacy fallback', (
    tester,
  ) async {
    var legacyCalls = 0;
    var blockedCalls = 0;
    var executorCalls = 0;

    final resolved = resolveDownloadsReaderNextExecutor(
      injectedExecutor: (_) async {
        executorCalls += 1;
      },
    );

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(upstreamComicRefId: 'remote:nhentai:646922'),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async => legacyCalls += 1,
      onBlocked: (_) async => blockedCalls += 1,
      onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
        result: result,
        executor: resolved!,
      ),
    );

    expect(decision, DownloadsRouteDecision.blocked);
    expect(legacyCalls, 0);
    expect(blockedCalls, 1);
    expect(executorCalls, 0);
  });

  testWidgets('flag off downloads calls explicit legacy only', (tester) async {
    var legacyCalls = 0;
    var blockedCalls = 0;
    var executorCalls = 0;

    final resolved = resolveDownloadsReaderNextExecutor(
      injectedExecutor: (_) async {
        executorCalls += 1;
      },
    );

    final decision = await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: false,
      openLegacy: () async => legacyCalls += 1,
      onBlocked: (_) async => blockedCalls += 1,
      onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
        result: result,
        executor: resolved!,
      ),
    );

    expect(decision, DownloadsRouteDecision.legacyExplicit);
    expect(legacyCalls, 1);
    expect(blockedCalls, 0);
    expect(executorCalls, 0);
  });

  test('downloads eligible executor input is bridge/controller-produced only', () async {
    DownloadsRouteCutoverResult? seen;
    final resolved = resolveDownloadsReaderNextExecutor(
      injectedExecutor: (_) async {},
    );

    await routeDownloadsReadOpen(
      controller: controller,
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      readerNextEnabled: true,
      readerNextDownloadsEnabled: true,
      openLegacy: () async {},
      onBlocked: (_) async {},
      onEligible: (result) async {
        seen = result;
        await dispatchDownloadsEligibleToExecutor(
          result: result,
          executor: resolved!,
        );
      },
    );

    expect(seen, isNotNull);
    expect(seen!.preflightResult, isNotNull);
    expect(seen!.preflightResult!.candidate, isNotNull);
    expect(
      seen!.diagnostic.currentSourceRefValidationCode,
      DownloadsSourceRefValidationCode.valid,
    );
  });

  test('downloads resolver prefers injected executor over factory', () async {
    var factoryCalls = 0;
    var injectedCalls = 0;
    final result = controller.evaluate(
      input: buildInput(),
      artifact: readyArtifact,
      isRowStale: false,
      featureFlagEnabled: true,
    );

    final resolved = resolveDownloadsReaderNextExecutor(
      injectedExecutor: (_) async {
        injectedCalls += 1;
      },
      injectedFactory: () {
        factoryCalls += 1;
        return (_) async {};
      },
    );
    await dispatchDownloadsEligibleToExecutor(
      result: result,
      executor: resolved!,
    );
    expect(injectedCalls, 1);
    expect(factoryCalls, 0);
  });
}
