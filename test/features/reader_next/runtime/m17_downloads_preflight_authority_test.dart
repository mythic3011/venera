import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M17-T6 authority guard: downloads has no ReaderNext route wiring', () {
    final guardedPaths = <String>[
      'lib/pages/downloads',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'ReaderNextOpenBridge',
      'OpenReaderController',
      'ReaderNextOpenRequest(',
      'HistoryRouteCutoverController',
      'FavoritesRouteCutoverController',
      'ReaderNextHistoryOpenExecutor',
      'ReaderNextFavoritesOpenExecutor',
      'features/reader_next/runtime',
      'features/reader_next/presentation',
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

  test('M17-T7 guard: history/favorites behavior remains unchanged', () {
    final guardedFiles = <String>[
      'lib/pages/history_page.dart',
      'lib/pages/favorites/favorites_page.dart',
      'lib/pages/favorites/local_favorites_page.dart',
      'lib/features/reader_next/bridge/history_route_cutover_controller.dart',
      'lib/features/reader_next/bridge/favorites_route_cutover_controller.dart',
    ];
    final forbidden = <String>[
      'downloads_route_readiness_preflight',
      'DownloadsRouteReadinessPreflightPolicy',
      'ReaderNextEntrypoint.downloads',
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
