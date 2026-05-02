import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M11 production wiring authority guards', () {
    test('no production file constructs ReaderNextOpenRequest directly', () {
      final violations = _scanForPattern(
        root: Directory('lib'),
        include: (file) =>
            file.path.endsWith('.dart') &&
            !file.path.startsWith('lib/features/reader_next/'),
        pattern: RegExp(r'ReaderNextOpenRequest\('),
      );

      expect(violations, isEmpty);
    });

    test('only approved production file references ReaderNextOpenBridge', () {
      final matches = _scanForPattern(
        root: Directory('lib'),
        include: (file) =>
            file.path.endsWith('.dart') &&
            !file.path.startsWith('lib/features/reader_next/'),
        pattern: RegExp(r'ReaderNextOpenBridge'),
      );

      final files = matches.map((entry) => entry.$1).toSet().toList()..sort();
      expect(files, <String>['lib/pages/comic_detail_page.dart']);
    });

    test('production pages must not call ReaderNextOpenBridge.fromLegacy directly', () {
      final matches = _scanForPattern(
        root: Directory('lib/pages'),
        include: (file) => file.path.endsWith('.dart'),
        pattern: RegExp(r'ReaderNextOpenBridge\.fromLegacy\('),
      );

      expect(matches, isEmpty);
    });

    test(
      'no production file references ReaderNext presentation classes directly',
      () {
        final matches = _scanForPattern(
          root: Directory('lib'),
          include: (file) =>
              file.path.endsWith('.dart') &&
              !file.path.startsWith('lib/features/reader_next/'),
          pattern: RegExp(
            r'ReaderNext.*Page|ReaderNext.*Screen|OpenReaderController',
          ),
        );

        expect(matches, isEmpty);
      },
    );

    test(
      'legacy page/foundation/component directories do not import reader_next runtime/presentation',
      () {
        final scopedRoots = <Directory>[
          Directory('lib/pages'),
          Directory('lib/foundation'),
          Directory('lib/components'),
        ];
        final violations = <(String, int, String)>[];
        final forbidden = <RegExp>[
          RegExp(r"import\s+'package:venera/features/reader_next/runtime/"),
          RegExp(
            r"import\s+'package:venera/features/reader_next/presentation/",
          ),
        ];
        for (final root in scopedRoots) {
          if (!root.existsSync()) {
            continue;
          }
          for (final entity in root.listSync(recursive: true)) {
            if (entity is! File || !entity.path.endsWith('.dart')) {
              continue;
            }
            final normalized = entity.path.replaceAll('\\', '/');
            final lines = entity.readAsLinesSync();
            for (int i = 0; i < lines.length; i++) {
              final line = lines[i];
              if (forbidden.any((pattern) => pattern.hasMatch(line))) {
                violations.add((normalized, i + 1, line.trim()));
              }
            }
          }
        }

        expect(violations, isEmpty);
      },
    );
  });
}

List<(String, int, String)> _scanForPattern({
  required Directory root,
  required bool Function(File file) include,
  required RegExp pattern,
}) {
  final matches = <(String, int, String)>[];
  if (!root.existsSync()) {
    return matches;
  }
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !include(entity)) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    final lines = entity.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (pattern.hasMatch(line)) {
        matches.add((path, i + 1, line.trim()));
      }
    }
  }
  return matches;
}
