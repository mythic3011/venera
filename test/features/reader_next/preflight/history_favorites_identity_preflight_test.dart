import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';

void main() {
  const scanner = HistoryFavoritesIdentityCoverageScanner();

  test(
    'scanner does not infer upstream id from recordId even when it looks valid',
    () {
      final record = IdentityCoverageInput.history(
        recordId: '646922',
        sourceKey: 'nhentai',
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: null,
      );
      final result = scanner.scan(record);
      expect(result.sourceRefValidationCode, SourceRefValidationCode.missing);
      expect(
        result.remediationAction,
        RemediationAction.requiresUserReopenFromDetail,
      );
    },
  );

  test(
    'scanner classifies canonical id inside upstream field as canonical leak',
    () {
      final record = IdentityCoverageInput.favorite(
        recordId: 'fav-1',
        sourceKey: 'nhentai',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: 'remote:nhentai:646922',
          chapterRefId: '1',
        ),
      );
      final result = scanner.scan(record);
      expect(
        result.sourceRefValidationCode,
        SourceRefValidationCode.canonicalLeakAsUpstream,
      );
      expect(
        result.remediationAction,
        RemediationAction.blockedMalformedIdentity,
      );
    },
  );

  test(
    'requiresLegacyImporterData only when importer-owned explicit snapshot exists',
    () {
      final importerBacked = IdentityCoverageInput.history(
        recordId: 'h-1',
        sourceKey: 'nhentai',
        sourceRef: null,
        hasImporterOwnedExplicitSnapshot: true,
      );
      final idOnly = IdentityCoverageInput.history(
        recordId: '646922',
        sourceKey: 'nhentai',
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: null,
        hasImporterOwnedExplicitSnapshot: false,
      );

      expect(
        scanner.scan(importerBacked).remediationAction,
        RemediationAction.requiresLegacyImporterData,
      );
      expect(
        scanner.scan(idOnly).remediationAction,
        isNot(RemediationAction.requiresLegacyImporterData),
      );
    },
  );

  test(
    'eligibleForFutureExplicitBackfill only with validated explicit source ref',
    () {
      final valid = IdentityCoverageInput.favorite(
        recordId: 'fav-2',
        sourceKey: 'nhentai',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
          chapterRefId: '1',
        ),
        explicitSnapshotAlreadyPersisted: false,
      );
      final idOnly = IdentityCoverageInput.favorite(
        recordId: '646922',
        sourceKey: 'nhentai',
        canonicalComicId: 'remote:nhentai:646922',
      );

      expect(
        scanner.scan(valid).remediationAction,
        RemediationAction.eligibleForFutureExplicitBackfill,
      );
      expect(
        scanner.scan(idOnly).remediationAction,
        isNot(RemediationAction.eligibleForFutureExplicitBackfill),
      );
    },
  );

  test('dry-run report aggregates counts without mutation instructions', () {
    final report = scanner.buildReport(<IdentityCoverageInput>[
      IdentityCoverageInput.history(
        recordId: 'h-1',
        sourceKey: 'nhentai',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
          chapterRefId: '1',
        ),
        explicitSnapshotAlreadyPersisted: false,
      ),
      IdentityCoverageInput.history(
        recordId: 'h-2',
        sourceKey: 'nhentai',
        sourceRef: null,
      ),
      IdentityCoverageInput.favorite(
        recordId: 'f-1',
        sourceKey: 'nhentai',
        sourceRef: const ExplicitSourceRefSnapshot(
          sourceKey: 'nhentai',
          upstreamComicRefId: 'remote:nhentai:646922',
          chapterRefId: '2',
        ),
      ),
    ]);

    expect(report.dryRun, isTrue);
    expect(report.aggregate.total, 3);
    expect(report.aggregate.valid, 1);
    expect(report.aggregate.missing, 1);
    expect(report.aggregate.canonicalLeakAsUpstream, 1);
    expect(report.aggregate.malformed, 0);
  });
}
