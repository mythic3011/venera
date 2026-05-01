import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M17.4 authority guard: downloads has no actual ReaderNext navigation wiring', () {
    final guardedFiles = <String>[
      'lib/pages/downloading_page.dart',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'features/reader_next/runtime',
      'features/reader_next/presentation',
      'ReaderNextShellPage',
      'ReaderNext.*Screen',
      'DownloadsReaderNextNavigation',
      'OpenReaderController',
    ];
    final violations = <String, List<String>>{};

    for (final path in guardedFiles) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final content = file.readAsStringSync();
      final found = forbidden
          .where((token) => token.contains('*') ? RegExp(token).hasMatch(content) : content.contains(token))
          .toList();
      if (found.isNotEmpty) {
        violations[path] = found;
      }
    }

    expect(violations, isEmpty);
  });

  test('M17.4 regression guard: history/favorites route behavior unchanged', () {
    final guardedFiles = <String>[
      'lib/pages/history_page.dart',
      'lib/pages/favorites/favorites_page.dart',
      'lib/pages/favorites/local_favorites_page.dart',
      'lib/features/reader_next/bridge/history_route_cutover_controller.dart',
      'lib/features/reader_next/bridge/favorites_route_cutover_controller.dart',
    ];
    final forbidden = <String>[
      'reader_next_downloads_enabled',
      'DownloadsRouteCutoverController',
      'routeDownloadsReadOpen',
      'resolveDownloadsReaderNextExecutor',
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
