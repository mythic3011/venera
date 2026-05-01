import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';

void main() {
  const scanner = HistoryFavoritesIdentityCoverageScanner();

  test('IdentityCoverageReport toJson keeps dry-run schema contract', () {
    final report = scanner.buildReport(<IdentityCoverageInput>[
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
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: null,
      ),
    ]);

    final json = report.toJson();
    expect(json['schemaVersion'], 1);
    expect(json['dryRun'], isTrue);

    final aggregate = json['aggregate'] as Map<String, Object?>;
    expect(aggregate['valid'], isA<int>());
    expect(aggregate['missing'], isA<int>());
    expect(aggregate['malformed'], isA<int>());
    expect(aggregate['canonicalLeakAsUpstream'], isA<int>());

    final results = (json['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(results, isNotEmpty);
    for (final row in results) {
      expect(
        row.keys,
        containsAll(<String>[
          'recordKind',
          'recordId',
          'sourceKey',
          'hasSourceRef',
          'sourceRefValidationCode',
          'canonicalComicIdRedacted',
          'upstreamComicRefIdRedacted',
          'chapterRefIdRedacted',
          'proposalAction',
        ]),
      );

      expect(row['recordKind'], anyOf('history', 'favorite'));
      expect(
        row['sourceRefValidationCode'],
        anyOf('valid', 'missing', 'malformed', 'canonicalLeakAsUpstream'),
      );
      expect(
        row['proposalAction'],
        anyOf(
          'none',
          'eligibleForFutureExplicitBackfill',
          'requiresUserReopenFromDetail',
          'requiresLegacyImporterData',
          'blockedMalformedIdentity',
        ),
      );
    }

    final encoded = jsonEncode(json);
    expect(encoded, isNot(contains('UPDATE ')));
    expect(encoded, isNot(contains('INSERT ')));
    expect(encoded, isNot(contains('DELETE ')));
    expect(encoded, isNot(contains('ALTER ')));
  });
}
