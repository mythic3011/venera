import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:venera/features/reader_next/preflight/favorites_route_cutover_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

void main() {
  const policy = FavoritesRoutePreflightPolicy();

  IdentityCoverageInput buildFavorite({
    required String folderName,
    String recordId = '646922',
    String sourceKey = 'nhentai',
    String upstream = '646922',
    String chapter = '1',
  }) {
    return IdentityCoverageInput.favorite(
      recordId: recordId,
      sourceKey: sourceKey,
      folderName: folderName,
      canonicalComicId: 'remote:$sourceKey:$upstream',
      sourceRef: ExplicitSourceRefSnapshot(
        sourceKey: sourceKey,
        upstreamComicRefId: upstream,
        chapterRefId: chapter,
      ),
      explicitSnapshotAlreadyPersisted: true,
    );
  }

  test('same favorite recordId in different folders produces distinct candidate ids', () {
    final a = policy.buildCandidate(input: buildFavorite(folderName: 'A'));
    final b = policy.buildCandidate(input: buildFavorite(folderName: 'B'));
    expect(a.candidateId, isNot(equals(b.candidateId)));
    expect(a.observedIdentityFingerprint, isNot(equals(b.observedIdentityFingerprint)));
  });

  test('favorite without folderName is always blocked', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: false,
      allowFavorites: true,
      allowDownloads: false,
    );
    final result = policy.evaluate(
      input: IdentityCoverageInput.favorite(
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
      ),
      artifact: artifact,
      isRowStale: false,
    );
    expect(result.decision, FavoritesPreflightDecision.blocked);
    expect(result.diagnostic.blockedReason, ReadinessBlockedReason.missingFavoritesFolderName.name);
  });

  test('move or copy stale fingerprint blocks route even if SourceRef shape is valid', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: false,
      allowFavorites: true,
      allowDownloads: false,
    );
    final result = policy.evaluate(
      input: buildFavorite(folderName: 'A'),
      artifact: artifact,
      isRowStale: true,
    );
    expect(result.decision, FavoritesPreflightDecision.blocked);
    expect(result.diagnostic.blockedReason, ReadinessBlockedReason.staleIdentity.name);
  });

  test('stale M14 readiness artifact blocks favorites even when favoritesReady is true', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: 999,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: false,
      allowFavorites: true,
      allowDownloads: false,
    );
    final result = policy.evaluate(
      input: buildFavorite(folderName: 'A'),
      artifact: artifact,
      isRowStale: false,
    );
    expect(result.decision, FavoritesPreflightDecision.blocked);
    expect(result.diagnostic.blockedReason, ReadinessBlockedReason.schemaVersionMismatch.name);
  });

  test('favorites diagnostic packet includes folderName and redacted record id', () {
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: false,
      allowFavorites: true,
      allowDownloads: false,
    );
    final result = policy.evaluate(
      input: buildFavorite(folderName: 'F-A', recordId: '646922'),
      artifact: artifact,
      isRowStale: false,
    );
    expect(result.diagnostic.recordKind, 'favorites');
    expect(result.diagnostic.folderName, 'F-A');
    expect(result.diagnostic.recordIdRedacted, isNot(contains('646922')));
    expect(result.diagnostic.readinessArtifactSchemaVersion, isNonZero);
    expect(result.diagnostic.currentSourceRefValidationCode, isNotEmpty);
  });

  test('favorites candidate builder requires folderName', () {
    expect(
      () => policy.buildCandidate(
        input: IdentityCoverageInput.favorite(
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
        ),
      ),
      throwsA(isA<FavoritesPreflightBoundaryException>()),
    );
  });

  test('favorites preflight does not enable route wiring', () {
    final guardedPaths = <String>[
      'lib/pages/favorites',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'ReaderNextOpenBridge',
      'ReaderNextOpenRequest(',
      'ReaderNextHistoryOpenExecutor',
      'HistoryRouteCutoverController',
    ];
    final violations = <String, List<String>>{};
    for (final path in guardedPaths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.notFound) {
        continue;
      }
      final files = type == FileSystemEntityType.directory
          ? Directory(path)
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))
          : <File>[File(path)];
      for (final file in files) {
        final content = file.readAsStringSync();
        final found = forbidden.where(content.contains).toList();
        if (found.isNotEmpty) {
          violations[file.path] = found;
        }
      }
    }
    expect(violations, isEmpty);
  });
}
