import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/backfill/explicit_identity_backfill_apply.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';

void main() {
  const scanner = HistoryFavoritesIdentityCoverageScanner();
  const builder = BackfillApplyPlanBuilder();
  const executor = BackfillApplyExecutionService();
  const verifier = BackfillPostApplyVerifier();

  IdentityCoverageReport buildEligibleReport() {
    return scanner.buildReport(<IdentityCoverageInput>[
      IdentityCoverageInput.history(
        recordId: 'h-1',
        sourceKey: 'nhentai',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
          chapterRefId: '1',
        ),
      ),
      IdentityCoverageInput.favorite(
        recordId: 'fav-1',
        sourceKey: 'nhentai',
        folderName: 'F1',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: '777',
          chapterRefId: '2',
        ),
      ),
      IdentityCoverageInput.history(
        recordId: 'h-2',
        sourceKey: 'nhentai',
        canonicalComicId: 'remote:nhentai:123',
        sourceRef: null,
      ),
    ]);
  }

  test('M13-T1 derive apply candidates from valid + eligible rows only', () {
    final plan = builder.fromReport(
      report: buildEligibleReport(),
      backupId: 'bkp-1',
    );
    expect(plan.candidates.length, 2);
    expect(
      plan.candidates.every((c) => c.upstreamComicRefId.startsWith('remote:')),
      isFalse,
    );
  });

  test('M13-T2 rejects non dry-run report and stale schema', () {
    final valid = buildEligibleReport();
    final nonDry = IdentityCoverageReport(
      schemaVersion: valid.schemaVersion,
      dryRun: false,
      aggregate: valid.aggregate,
      results: valid.results,
    );
    expect(
      () => builder.fromReport(report: nonDry, backupId: 'bkp-1'),
      throwsA(
        isA<BackfillApplyRejected>().having(
          (e) => e.code,
          'code',
          BackfillApplyRejectCode.nonDryRunReport,
        ),
      ),
    );

    final staleSchema = IdentityCoverageReport(
      schemaVersion: 999,
      dryRun: true,
      aggregate: valid.aggregate,
      results: valid.results,
    );
    expect(
      () => builder.fromReport(report: staleSchema, backupId: 'bkp-1'),
      throwsA(
        isA<BackfillApplyRejected>().having(
          (e) => e.code,
          'code',
          BackfillApplyRejectCode.staleSchemaVersion,
        ),
      ),
    );
  });

  test('M13-T2 favorites candidates require folderName', () {
    final report = scanner.buildReport(<IdentityCoverageInput>[
      IdentityCoverageInput.favorite(
        recordId: 'fav-1',
        sourceKey: 'nhentai',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: '777',
          chapterRefId: '2',
        ),
      ),
    ]);
    expect(
      () => builder.fromReport(report: report, backupId: 'bkp-1'),
      throwsA(
        isA<BackfillApplyRejected>().having(
          (e) => e.code,
          'code',
          BackfillApplyRejectCode.missingFavoritesFolderName,
        ),
      ),
    );
  });

  test('M13 canonical dry-run artifact hash is stable across input order', () {
    final reportA = buildEligibleReport();
    final reordered = IdentityCoverageReport(
      schemaVersion: reportA.schemaVersion,
      dryRun: reportA.dryRun,
      aggregate: reportA.aggregate,
      results: reportA.results.reversed.toList(),
    );

    final hashA = canonicalDryRunArtifactHash(reportA);
    final hashReordered = canonicalDryRunArtifactHash(reordered);
    expect(hashA, hashReordered);
  });

  test(
    'M13-T4 apply execution is compare-and-set and resumable by candidateId checkpoint',
    () async {
      final report = buildEligibleReport();
      final plan = builder.fromReport(report: report, backupId: 'bkp-1');
      final sink = InMemoryBackfillApplySink();
      for (final c in plan.candidates) {
        sink.seed(
          InMemoryBackfillApplySinkRow(
            recordKind: c.recordKind,
            folderName: c.folderName,
            recordId: c.recordId,
            sourceKey: c.sourceKey,
            canonicalComicId: c.canonicalComicId,
            upstreamComicRefId: c.upstreamComicRefId,
            chapterRefId: c.chapterRefId,
          ),
        );
      }

      final firstRun = await executor.execute(
        plan: plan,
        report: report,
        sink: sink,
        backupId: 'bkp-1',
      );
      expect(firstRun.appliedCount, 2);
      expect(firstRun.skippedStaleRowCount, 0);
      expect(firstRun.checkpoint.appliedCandidateIds.length, 2);

      final resumed = await executor.execute(
        plan: plan,
        report: report,
        sink: sink,
        backupId: 'bkp-1',
        checkpoint: firstRun.checkpoint,
      );
      expect(resumed.appliedCount, 0);
      expect(resumed.checkpoint.appliedCandidateIds.length, 2);
    },
  );

  test(
    'apply skips stale row instead of overwriting changed identity',
    () async {
      final report = buildEligibleReport();
      final plan = builder.fromReport(report: report, backupId: 'bkp-1');
      final sink = InMemoryBackfillApplySink();
      final first = plan.candidates.first;
      sink.seed(
        InMemoryBackfillApplySinkRow(
          recordKind: first.recordKind,
          folderName: first.folderName,
          recordId: first.recordId,
          sourceKey: first.sourceKey,
          canonicalComicId: first.canonicalComicId,
          upstreamComicRefId: first.upstreamComicRefId,
          chapterRefId: first.chapterRefId,
        ),
      );
      sink.mutateRowForTest(
        recordKind: first.recordKind,
        folderName: first.folderName,
        recordId: first.recordId,
        sourceKey: first.sourceKey,
        canonicalComicId: 'remote:nhentai:mutated',
        upstreamComicRefId: 'mutated',
        chapterRefId: '9',
      );

      final result = await executor.execute(
        plan: BackfillApplyPlan(
          reportSchemaVersion: plan.reportSchemaVersion,
          dryRunArtifactHash: plan.dryRunArtifactHash,
          backupId: plan.backupId,
          candidates: <BackfillApplyCandidate>[first],
        ),
        report: report,
        sink: sink,
        backupId: 'bkp-1',
      );

      expect(result.skippedStaleRowCount, 1);
      expect(result.appliedCount, 0);
      expect(result.diagnostics.any((d) => d['code'] == 'STALE_ROW'), isTrue);
    },
  );

  test('M13-T5 post-apply verifier confirms applied rows', () async {
    final report = buildEligibleReport();
    final plan = builder.fromReport(report: report, backupId: 'bkp-1');
    final sink = InMemoryBackfillApplySink();
    for (final c in plan.candidates) {
      sink.seed(
        InMemoryBackfillApplySinkRow(
          recordKind: c.recordKind,
          folderName: c.folderName,
          recordId: c.recordId,
          sourceKey: c.sourceKey,
          canonicalComicId: c.canonicalComicId,
          upstreamComicRefId: c.upstreamComicRefId,
          chapterRefId: c.chapterRefId,
        ),
      );
    }
    final applied = await executor.execute(
      plan: plan,
      report: report,
      sink: sink,
      backupId: 'bkp-1',
    );
    final verify = await verifier.verify(
      plan: plan,
      checkpoint: applied.checkpoint,
      sink: sink,
    );
    expect(verify.invalidAppliedCount, 0);
    expect(verify.validAppliedCount, applied.appliedCount);
  });
}
