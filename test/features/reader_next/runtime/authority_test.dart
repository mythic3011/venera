import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reader_next runtime authority', () {
    test('uses a single runtime namespace', () {
      final duplicateRuntimeFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.contains('venera_next'))
          .map((file) => file.path)
          .toList();

      expect(duplicateRuntimeFiles, isEmpty);
    });

    test('does not import legacy reader or UI layers', () {
      final runtimeFiles = Directory('lib/features/reader_next/runtime')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final forbiddenImports = <String, List<String>>{};
      for (final file in runtimeFiles) {
        final text = file.readAsStringSync();
        final matches = <String>[
          'package:venera/features/reader/',
          'package:venera/foundation/reader/',
          'package:venera/venera_next/',
          'package:venera/pages/',
          'package:venera/components/',
          'package:flutter/',
        ].where(text.contains).toList();
        if (matches.isNotEmpty) {
          forbiddenImports[file.path] = matches;
        }
      }

      expect(forbiddenImports, isEmpty);
    });
  });
}
