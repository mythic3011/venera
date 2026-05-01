import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/preflight/downloads_route_readiness_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

void main() {
  const policy = DownloadsRouteReadinessPreflightPolicy();
  const readyArtifact = ReadinessArtifact(
    readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
    sourceSchemaVersion: 1,
    postApplyVerified: true,
    allowHistory: false,
    allowFavorites: false,
    allowDownloads: true,
  );

  DownloadsPreflightInput input({
    String recordId = 'dl-646922',
    String sourceKey = 'nhentai',
    String canonicalComicId = 'remote:nhentai:646922',
    String upstreamComicRefId = '646922',
    String chapterRefId = '1',
    String? downloadSessionId = 's-1',
    DownloadsSourceRefSnapshot? sourceRef,
    String? localPath = '/downloads/nhentai/646922/chapter-1.cbz',
    String? filename = 'chapter-1.cbz',
    bool hasImporterOwnedExplicitSnapshot = false,
  }) {
    return DownloadsPreflightInput(
      recordId: recordId,
      sourceKey: sourceKey,
      canonicalComicId: canonicalComicId,
      sourceRef:
          sourceRef ??
          DownloadsSourceRefSnapshot(
            sourceKey: sourceKey,
            upstreamComicRefId: upstreamComicRefId,
            chapterRefId: chapterRefId,
          ),
      downloadSessionId: downloadSessionId,
      localPath: localPath,
      filename: filename,
      hasImporterOwnedExplicitSnapshot: hasImporterOwnedExplicitSnapshot,
    );
  }

  test('downloads preflight does not infer upstream id from local path', () {
    final result = policy.evaluate(
      input: const DownloadsPreflightInput(
        recordId: 'dl-1',
        sourceKey: 'nhentai',
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: null,
        localPath: '/downloads/nhentai/646922/chapter-1.cbz',
      ),
      artifact: readyArtifact,
      isRowStale: false,
    );
    expect(result.decision, DownloadsPreflightDecision.blocked);
    expect(
      result.validationCode,
      DownloadsSourceRefValidationCode.missingSourceRef,
    );
    expect(
      result.remediationAction,
      DownloadsRemediationAction.requiresUserReopenFromDetail,
    );
  });

  test('downloads candidate id excludes local path and filename', () {
    final a = policy.buildCandidate(
      input: input(
        localPath: '/downloads/one/chapter-1.cbz',
        filename: 'chapter-1.cbz',
      ),
    );
    final b = policy.buildCandidate(
      input: input(
        localPath: '/downloads/two/chapter-a.cbz',
        filename: 'chapter-a.cbz',
      ),
    );
    expect(a.candidateId, b.candidateId);
    expect(a.observedIdentityFingerprint, b.observedIdentityFingerprint);
  });

  test('downloads candidate id changes when explicit upstream identity changes', () {
    final a = policy.buildCandidate(input: input(upstreamComicRefId: '646922'));
    final b = policy.buildCandidate(input: input(upstreamComicRefId: '777777'));
    expect(a.candidateId, isNot(equals(b.candidateId)));
  });

  test('downloads classifies canonical id inside upstream field as canonical leak', () {
    final result = policy.evaluate(
      input: input(upstreamComicRefId: 'remote:nhentai:646922'),
      artifact: readyArtifact,
      isRowStale: false,
    );
    expect(
      result.validationCode,
      DownloadsSourceRefValidationCode.canonicalLeakAsUpstream,
    );
    expect(
      result.remediationAction,
      DownloadsRemediationAction.blockedMalformedIdentity,
    );
  });

  test('downloads stale identity is blocked even when SourceRef shape is valid', () {
    final result = policy.evaluate(
      input: input(),
      artifact: readyArtifact,
      isRowStale: true,
    );
    expect(result.validationCode, DownloadsSourceRefValidationCode.staleIdentity);
    expect(
      result.remediationAction,
      DownloadsRemediationAction.blockedStaleIdentity,
    );
  });

  test('downloads diagnostic packet is redacted', () {
    final result = policy.evaluate(
      input: input(),
      artifact: readyArtifact,
      isRowStale: false,
    );
    final diagnostic = result.diagnostic;
    expect(diagnostic.recordKind, 'downloads');
    expect(diagnostic.recordIdRedacted.contains('646922'), isFalse);
    expect(diagnostic.downloadSessionIdRedacted?.contains('s-1'), isFalse);
    expect(diagnostic.candidateId, isNotEmpty);
    expect(diagnostic.observedIdentityFingerprint, isNotEmpty);
    expect(diagnostic.currentSourceRefValidationCode, isNotNull);
    expect(diagnostic.readinessArtifactSchemaVersion, isNonZero);
  });

  test('downloads stale/unknown readiness artifact schema blocks preflight', () {
    const staleArtifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: 999,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: false,
      allowFavorites: false,
      allowDownloads: true,
    );
    final result = policy.evaluate(
      input: input(),
      artifact: staleArtifact,
      isRowStale: false,
    );
    expect(result.decision, DownloadsPreflightDecision.blocked);
    expect(
      result.diagnostic.blockedReason,
      ReadinessBlockedReason.schemaVersionMismatch.name,
    );
  });

  test('downloads page does not build ReaderNext identity or route request', () {
    final guardedPaths = <String>[
      'lib/pages/downloads',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'ReaderNextOpenRequest(',
      'SourceRef.',
      'features/reader_next/runtime',
      'features/reader_next/presentation',
      'upstreamComicRefId',
      'fromLegacyRemote',
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
