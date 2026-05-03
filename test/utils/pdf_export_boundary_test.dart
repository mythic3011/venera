import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pdf export helper does not depend on legacy local root bridge', () async {
    final content = await File('lib/utils/pdf.dart').readAsString();
    expect(content.contains('local_comics_legacy_bridge.dart'), isFalse);
    expect(content.contains('legacyReadLocalComicsRootPath'), isFalse);
  });
}
