import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'authority guard: favorites/download routes remain ReaderNext-disabled',
    () {
      final guardedPaths = <String>[
        'lib/pages/favorites',
        'lib/pages/local_comics_page.dart',
      ];
      final forbidden = <String>[
        'ReaderNextOpenBridge',
        'ReaderNextOpenRequest(',
        'ReaderNextShellPage',
        'OpenReaderController',
        'features/reader_next/presentation/',
        'features/reader_next/runtime/',
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
    },
  );
}
