import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reader_next preflight authority guards', () {
    test(
      'history favorites preflight does not import ReaderNext open path',
      () async {
        final files = Directory('lib/features/reader_next')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.contains('/backfill/') ||
                  file.path.contains('/preflight/'),
            );
        for (final file in files) {
          final content = await file.readAsString();
          expect(content, isNot(contains('ReaderNextOpenBridge')));
          expect(content, isNot(contains('ReaderNextOpenRequest')));
          expect(content, isNot(contains('/presentation/')));
        }
      },
    );

    test('favorites/download pages still cannot open ReaderNext directly', () {
      final guardedPaths = <String>[
        'lib/pages/favorites',
        'lib/pages/local_comics_page.dart',
      ];
      final forbiddenSnippets = <String>[
        'ReaderNextOpenBridge',
        'ReaderNextOpenRequest(',
        'ReaderNextShellPage',
        'OpenReaderController',
        'features/reader_next/presentation/',
        'features/reader_next/runtime/',
      ];

      final violations = <String, List<String>>{};
      for (final path in guardedPaths) {
        final entity = FileSystemEntity.typeSync(path);
        if (entity == FileSystemEntityType.notFound) {
          continue;
        }
        final files = entity == FileSystemEntityType.directory
            ? Directory(path)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((file) => file.path.endsWith('.dart'))
            : <File>[File(path)];
        for (final file in files) {
          final content = file.readAsStringSync();
          final found = forbiddenSnippets
              .where((token) => content.contains(token))
              .toList();
          if (found.isNotEmpty) {
            violations[file.path] = found;
          }
        }
      }

      expect(violations, isEmpty);
    });
  });
}
