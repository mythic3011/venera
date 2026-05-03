import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _CallsiteMeta {
  const _CallsiteMeta({
    required this.pattern,
    required this.category,
    required this.owner,
    required this.migrationLane,
  });

  final String pattern;
  final String category;
  final String owner;
  final String migrationLane;
}

void main() {
  test('global context callsites are fully classified', () {
    const baselineByCallsite = <String, _CallsiteMeta>{
      'lib/main.dart:107': _CallsiteMeta(
        pattern: 'App.rootContext',
        category: 'allowed_bootstrap',
        owner: 'bootstrap',
        migrationLane: 'none',
      ),
      'lib/main.dart:112': _CallsiteMeta(
        pattern: 'App.rootContext',
        category: 'allowed_bootstrap',
        owner: 'bootstrap',
        migrationLane: 'none',
      ),
      'lib/main.dart:122': _CallsiteMeta(
        pattern: 'App.rootContext',
        category: 'allowed_bootstrap',
        owner: 'bootstrap',
        migrationLane: 'none',
      ),
      'lib/main.dart:125': _CallsiteMeta(
        pattern: 'App.rootContext',
        category: 'allowed_bootstrap',
        owner: 'bootstrap',
        migrationLane: 'none',
      ),
      'lib/main.dart:198': _CallsiteMeta(
        pattern: 'App.rootContext',
        category: 'allowed_bootstrap',
        owner: 'bootstrap',
        migrationLane: 'none',
      ),
    };
    const searchPattern =
        r'App\.rootContext|App\.rootNavigatorKey\.currentContext|App\.mainNavigatorKey\?\.currentContext';

    final rg = Process.runSync(
      'rg',
      ['-n', searchPattern, 'lib'],
      runInShell: false,
    );

    expect(rg.exitCode, 0, reason: 'rg failed: ${rg.stderr}');

    final stdout = (rg.stdout as String).trim();
    final foundCallsites = <String, _CallsiteMeta>{};
    if (stdout.isNotEmpty) {
      for (final line in stdout.split('\n')) {
        final parts = line.split(':');
        if (parts.length < 3) {
          continue;
        }
        final file = parts[0];
        final lineNo = int.tryParse(parts[1]);
        if (lineNo == null || lineNo <= 0) {
          continue;
        }
        final sourceLine = parts.sublist(2).join(':');
        final pattern = _detectPattern(sourceLine);
        if (pattern == null) {
          continue;
        }
        final key = '$file:$lineNo';
        foundCallsites[key] = _CallsiteMeta(
          pattern: pattern,
          category: '<unknown>',
          owner: '<unknown>',
          migrationLane: '<unknown>',
        );
      }
    }

    final missingClassification = foundCallsites.keys
        .where((key) => !baselineByCallsite.containsKey(key))
        .toList()
      ..sort();
    final staleClassification = baselineByCallsite.keys
        .where((key) => !foundCallsites.containsKey(key))
        .toList()
      ..sort();

    expect(
      missingClassification,
      isEmpty,
      reason:
          'New global-context callsite(s) must be classified first:\n${missingClassification.join('\n')}',
    );

    expect(
      staleClassification,
      isEmpty,
      reason:
          'Callsite baseline contains stale entry(s):\n${staleClassification.join('\n')}',
    );

    final invalidCategory = <String>[];
    const validCategories = <String>{
      'allowed_bootstrap',
      'allowed_emergency',
      'ui_navigation',
      'ui_message',
      'dialog_popup',
      'background_service',
      'unknown',
    };

    for (final entry in baselineByCallsite.entries) {
      if (!validCategories.contains(entry.value.category)) {
        invalidCategory.add('${entry.key} -> ${entry.value.category}');
      }
    }

    expect(
      invalidCategory,
      isEmpty,
      reason: 'Invalid global-context category values:\n${invalidCategory.join('\n')}',
    );

    final missingMetadata = <String>[];
    final patternMismatch = <String>[];
    const alwaysAllowed = <String>{'allowed_bootstrap', 'allowed_emergency'};
    for (final entry in baselineByCallsite.entries) {
      final key = entry.key;
      final expected = entry.value;
      final found = foundCallsites[key];
      if (found != null && found.pattern != expected.pattern) {
        patternMismatch.add('$key expected=${expected.pattern} actual=${found.pattern}');
      }

      if (expected.owner.trim().isEmpty || expected.migrationLane.trim().isEmpty) {
        missingMetadata.add(key);
      }

      if (alwaysAllowed.contains(expected.category)) {
        continue;
      }
      if (expected.migrationLane == 'none') {
        missingMetadata.add(key);
      }
    }

    expect(
      patternMismatch,
      isEmpty,
      reason: 'Global-context callsite pattern mismatch:\n${patternMismatch.join('\n')}',
    );

    expect(
      missingMetadata,
      isEmpty,
      reason:
          'Every callsite must have owner + migration lane; non-allowed callsites must have a real lane:\n${missingMetadata.join('\n')}',
    );
  });
}

String? _detectPattern(String sourceLine) {
  if (sourceLine.contains('App.rootContext')) {
    return 'App.rootContext';
  }
  if (sourceLine.contains('App.rootNavigatorKey.currentContext')) {
    return 'App.rootNavigatorKey.currentContext';
  }
  if (sourceLine.contains('App.mainNavigatorKey?.currentContext')) {
    return 'App.mainNavigatorKey?.currentContext';
  }
  return null;
}
