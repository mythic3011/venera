import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M15 authority guard: favorites/downloads remain ReaderNext-blocked', () {
    final guardedPaths = <String>[
      'lib/pages/favorites',
      'lib/pages/local_comics_page.dart',
    ];
    final forbidden = <String>[
      'HistoryRouteCutoverController',
      'ReaderNextOpenBridge',
      'ReaderNextOpenRequest(',
      'OpenReaderController',
      'ReaderNextShellPage',
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

  test('M15.2 guard: blocked branch must not call legacy callback', () {
    final file = File(
      'lib/features/reader_next/bridge/history_route_cutover_controller.dart',
    );
    final content = file.readAsStringSync();
    final guarded = RegExp(
      r'case HistoryRouteDecision\.blocked:\s+await onBlocked\(result\);\s+return HistoryRouteDecision\.blocked;',
      multiLine: true,
    );
    expect(guarded.hasMatch(content), isTrue);
    final forbidden = RegExp(
      r'case HistoryRouteDecision\.blocked:[\s\S]{0,220}openLegacy\(',
      multiLine: true,
    );
    expect(forbidden.hasMatch(content), isFalse);
  });

  test('M15.2 guard: diagnostic packet does not expose raw recordId field', () {
    final file = File(
      'lib/features/reader_next/bridge/history_route_cutover_controller.dart',
    );
    final content = file.readAsStringSync();
    expect(content, contains('recordIdRedacted'));
    expect(content, isNot(contains('final String recordId;')));
  });

  test('M15.2 guard: route authority code does not consume raw M12/M13 artifacts', () {
    final roots = <String>[
      'lib/pages/history_page.dart',
      'lib/features/reader_next/bridge/history_route_cutover_controller.dart',
      'lib/features/reader_next/presentation/history_reader_next_navigation_executor.dart',
    ];
    final forbidden = <String>[
      'IdentityCoverageReport',
      'BackfillApplyPlan',
      'explicit_identity_backfill',
      'backfill/explicit_identity_backfill',
    ];
    final violations = <String, List<String>>{};
    for (final path in roots) {
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

  test('favorites page does not build identity or SourceRef', () {
    final guardedPaths = <String>[
      'lib/pages/favorites',
      'lib/pages/favorites_page.dart',
    ];
    final forbiddenPatterns = <RegExp>[
      RegExp(r'ReaderNextOpenRequest\('),
      RegExp(r'SourceRef\.(from|remote|local)'),
      RegExp(r'new\s+SourceRef\('),
      RegExp(r'upstreamComicRefId'),
      RegExp(r'canonicalComicId\s*\.\s*(split|substring|replaceAll|contains)\('),
    ];
    final violations = <String, int>{};
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
        final count = forbiddenPatterns
            .map((pattern) => pattern.allMatches(content).length)
            .fold<int>(0, (a, b) => a + b);
        if (count > 0) {
          violations[file.path] = count;
        }
      }
    }
    expect(violations, isEmpty);
  });
}
