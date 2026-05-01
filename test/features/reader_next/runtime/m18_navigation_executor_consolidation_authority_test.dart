import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M18 authority guard: pages do not import navigation implementation', () {
    final files = <String>[
      'lib/pages/history_page.dart',
      'lib/pages/favorites/favorites_page.dart',
      'lib/pages/favorites/local_favorites_page.dart',
      'lib/pages/downloading_page.dart',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'features/reader_next/presentation/approved_reader_next_navigation_executor.dart',
      'features/reader_next/presentation/history_reader_next_navigation_executor.dart',
      'ReaderNextOpenRequest(',
      'SourceRef.',
    ];
    final violations = <String, List<String>>{};
    for (final path in files) {
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
