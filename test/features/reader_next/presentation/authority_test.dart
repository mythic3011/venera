import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reader_next presentation authority', () {
    test('presentation layer does not import legacy reader runtime', () {
      final presentationFiles = Directory('lib/features/reader_next/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final violations = <String, List<String>>{};
      for (final file in presentationFiles) {
        final text = file.readAsStringSync();
        final matches = <String>[
          'package:venera/features/reader/presentation/',
          'package:venera/features/reader/data/',
          'package:venera/foundation/reader/',
          'package:venera/foundation/history.dart',
          'package:venera/foundation/favorites.dart',
          'package:venera/foundation/sources/source_ref.dart',
        ].where(text.contains).toList();
        if (matches.isNotEmpty) {
          violations[file.path] = matches;
        }
      }

      expect(violations, isEmpty);
    });
  });
}
