import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reader_next authority import guard', () {
    test('ReaderNext presentation/runtime deny legacy reader/runtime imports', () {
      final guardedRoots = <String>[
        'lib/features/reader_next/runtime',
        'lib/features/reader_next/presentation',
      ];
      final forbiddenImportSnippets = <String>[
        "package:venera/features/reader/",
        "package:venera/foundation/reader/",
        "package:venera/pages/reader",
      ];

      final violations = <String, List<String>>{};
      for (final rootPath in guardedRoots) {
        final root = Directory(rootPath);
        if (!root.existsSync()) {
          continue;
        }
        final files = root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'));
        for (final file in files) {
          final text = file.readAsStringSync();
          final lines = text
              .split('\n')
              .where(
                (line) =>
                    line.trimLeft().startsWith('import ') ||
                    line.trimLeft().startsWith('export '),
              )
              .toList();
          final matched = forbiddenImportSnippets
              .where((token) => lines.any((line) => line.contains(token)))
              .toList();
          if (matched.isNotEmpty) {
            violations[file.path] = matched;
          }
        }
      }

      expect(violations, isEmpty);
    });
  });
}
