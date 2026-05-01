import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'no history/favorites/download surface constructs ReaderNextOpenRequest directly',
    () {
      final roots = <String>[
        'lib/pages/history_page.dart',
        'lib/pages/favorites',
        'lib/pages/local_comics_page.dart',
      ];
      final violations = <String, int>{};
      for (final root in roots) {
        final type = FileSystemEntity.typeSync(root);
        if (type == FileSystemEntityType.notFound) {
          continue;
        }
        final files = type == FileSystemEntityType.directory
            ? Directory(root)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart'))
            : <File>[File(root)];
        for (final file in files) {
          final text = file.readAsStringSync();
          final count = RegExp(r'ReaderNextOpenRequest\(')
              .allMatches(text)
              .length;
          if (count > 0) {
            violations[file.path] = count;
          }
        }
      }

      expect(violations, isEmpty);
    },
  );

  test(
    'M14 authority guard blocks direct SourceRef.remote(item.id) patterns in history/favorites/download surfaces',
    () {
      final roots = <String>[
        'lib/pages/history_page.dart',
        'lib/pages/favorites',
        'lib/pages/local_comics_page.dart',
      ];
      final violations = <String, List<String>>{};
      final strongPattern = RegExp(
        r'SourceRef\.remote\([\s\S]{0,220}upstreamComicRefId\s*:\s*(item|c|comic)\.id',
      );
      final weakPatterns = <String>[
        'SourceRef.remote(',
        'upstreamComicRefId: item.id',
        'upstreamComicRefId: c.id',
        'upstreamComicRefId: comic.id',
      ];

      for (final root in roots) {
        final type = FileSystemEntity.typeSync(root);
        if (type == FileSystemEntityType.notFound) {
          continue;
        }
        final files = type == FileSystemEntityType.directory
            ? Directory(root)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart'))
            : <File>[File(root)];
        for (final file in files) {
          final text = file.readAsStringSync();
          final found = <String>[];
          if (strongPattern.hasMatch(text)) {
            found.add('SourceRef.remote(... upstreamComicRefId: <var>.id)');
          }
          for (final token in weakPatterns) {
            if (text.contains(token)) {
              found.add(token);
            }
          }
          if (found.isNotEmpty) {
            violations[file.path] = found;
          }
        }
      }

      expect(violations, isEmpty);
    },
  );

  test(
    'grep guard: no SourceRef.remote(... upstreamComicRefId: history|favorite|item|comic.id) pattern in lib/test',
    () {
      final roots = <String>['lib', 'test'];
      final pattern = RegExp(
        r'SourceRef\.remote\([\s\S]{0,240}upstreamComicRefId:\s*(history|favorite|item|comic)\.id',
      );
      final violations = <String, int>{};
      for (final root in roots) {
        final dir = Directory(root);
        if (!dir.existsSync()) {
          continue;
        }
        for (final file
            in dir
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))
                .where(
                  (f) => !f.path.endsWith(
                    'test/features/reader_next/runtime/m14_route_guard_authority_test.dart',
                  ),
                )) {
          final content = file.readAsStringSync();
          if (pattern.hasMatch(content)) {
            violations[file.path] = pattern.allMatches(content).length;
          }
        }
      }
      expect(violations, isEmpty);
    },
  );

  test('M14 route readiness code does not read raw M13 apply report authority', () {
    final path =
        'lib/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
    final content = File(path).readAsStringSync();
    final forbidden = <String>[
      'BackfillApplyPlan',
      'BackfillApplyCandidate',
      'BackfillApplyExecutionResult',
      'BackfillApplyPlanBuilder',
      'IdentityCoverageReport',
      'report.',
    ];
    final found = forbidden.where(content.contains).toList();
    expect(found, isEmpty);
  });
}
