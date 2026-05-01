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
      archivePath: '/archive/$sourceKey/$recordId/$chapterRefId.cbz',
      filename: '$chapterRefId.cbz',
      sourceUrl: 'https://example.invalid/$sourceKey/$recordId/$chapterRefId',
    );
  }

  testWidgets(
    'downloads executor smoke: flag off uses explicit legacy route',
    (tester) async {
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
    },
  );

  testWidgets(
    'downloads executor smoke: flag on eligible dispatches executor once',
    (tester) async {
      var legacyCalls = 0;
      var blockedCalls = 0;
      var executorCalls = 0;
      DownloadsRouteCutoverResult? executorInput;

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
          executorInput = result;
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
      expect(executorInput, isNotNull);
      expect(executorInput!.preflightResult, isNotNull);
      expect(executorInput!.preflightResult!.candidate, isNotNull);
      expect(
        executorInput!.diagnostic.currentSourceRefValidationCode,
        DownloadsSourceRefValidationCode.valid,
      );
    },
  );

  testWidgets(
    'downloads executor smoke: blocked row does not fallback',
    (tester) async {
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
    },
  );

  test(
    'downloads kill-switch does not mutate readiness or identity state after executor injection',
    () async {
      final input = buildInput();
      final beforeSchema = readyArtifact.readinessArtifactSchemaVersion;
      final beforeAllowDownloads = readyArtifact.allowDownloads;
      final beforeRecordId = input.recordId;
      final beforeCanonical = input.canonicalComicId;
      final beforeUpstream = input.sourceRef!.upstreamComicRefId;
      final beforeChapter = input.sourceRef!.chapterRefId;
      final beforeSession = input.downloadSessionId;

      final resolved = resolveDownloadsReaderNextExecutor(
        injectedExecutor: (_) async {},
      );
      await routeDownloadsReadOpen(
        controller: controller,
        input: input,
        artifact: readyArtifact,
        isRowStale: false,
        readerNextEnabled: true,
        readerNextDownloadsEnabled: true,
        openLegacy: () async {},
        onBlocked: (_) async {},
        onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
          result: result,
          executor: resolved!,
        ),
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
        onEligible: (result) async => dispatchDownloadsEligibleToExecutor(
          result: result,
          executor: resolved!,
        ),
      );

      expect(readyArtifact.readinessArtifactSchemaVersion, beforeSchema);
      expect(readyArtifact.allowDownloads, beforeAllowDownloads);
      expect(input.recordId, beforeRecordId);
      expect(input.canonicalComicId, beforeCanonical);
      expect(input.sourceRef!.upstreamComicRefId, beforeUpstream);
      expect(input.sourceRef!.chapterRefId, beforeChapter);
      expect(input.downloadSessionId, beforeSession);
    },
  );

  test(
    'downloads diagnostics are redacted for all executor-enabled route decisions',
    () async {
      final packets = <DownloadsRouteDecisionDiagnosticPacket>[];

      for (final run in <Future<void> Function()>[
        () => routeDownloadsReadOpen(
          controller: controller,
          input: buildInput(recordId: 'dl-646922', downloadSessionId: 'session-raw-1'),
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
          input: buildInput(recordId: 'dl-646922', downloadSessionId: 'session-raw-1'),
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
          input: buildInput(upstreamComicRefId: 'remote:nhentai:646922'),
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
        expect(packet.downloadSessionIdRedacted?.contains('session-raw-1'), isFalse);
        expect(packet.sourceKey.contains('remote:'), isFalse);
        expect(packet.blockedReason.contains('/downloads/'), isFalse);
        expect(packet.blockedReason.contains('/cache/'), isFalse);
      }
    },
  );

  test('downloads executor input is bridge produced and redacted', () async {
    DownloadsRouteCutoverResult? executorInput;
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
        executorInput = result;
        await dispatchDownloadsEligibleToExecutor(
          result: result,
          executor: resolved!,
        );
      },
    );

    expect(executorInput, isNotNull);
    expect(executorInput!.preflightResult, isNotNull);
    final candidate = executorInput!.preflightResult!.candidate;
    expect(candidate, isNotNull);
    expect(candidate!.recordId, 'dl-646922');
    expect(candidate.sourceKey, 'nhentai');
    expect(candidate.canonicalComicId, 'remote:nhentai:646922');
    expect(candidate.upstreamComicRefId, '646922');
    expect(candidate.chapterRefId, '1');
    expect(executorInput!.diagnostic.recordIdRedacted.contains('646922'), isFalse);
  });
}
