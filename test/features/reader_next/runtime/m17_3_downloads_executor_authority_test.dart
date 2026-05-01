import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'M17.3 authority guard: downloads page has no runtime/screen/executor implementation imports',
    () {
      final guardedPaths = <String>[
        'lib/pages/downloading_page.dart',
        'lib/pages/local_comics_page.dart',
      ];
      final forbidden = <String>[
        'features/reader_next/runtime',
        'features/reader_next/presentation',
        'DownloadsReaderNextNavigation',
        'DownloadsReaderNext',
        'ReaderNextOpenRequest(',
        'SourceRef.',
      ];
      final violations = <String, List<String>>{};

      for (final path in guardedPaths) {
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
    },
  );

  test('M17.3 regression guard: history/favorites unchanged', () {
    final guardedFiles = <String>[
      'lib/pages/history_page.dart',
      'lib/pages/favorites/favorites_page.dart',
      'lib/pages/favorites/local_favorites_page.dart',
    ];
    final forbidden = <String>[
      'resolveDownloadsReaderNextExecutor',
      'DownloadsRouteCutoverController',
      'routeDownloadsReadOpen',
    ];
    final violations = <String, List<String>>{};
    for (final path in guardedFiles) {
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
