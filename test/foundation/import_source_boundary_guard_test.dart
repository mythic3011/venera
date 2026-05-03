import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local import storage avoids LocalManager and legacy bridge imports',
    () async {
      final content = await File(
        'lib/utils/local_import_storage.dart',
      ).readAsString();
      expect(content.contains('LocalManager('), isFalse);
      expect(content.contains('local_comics_legacy_bridge.dart'), isFalse);
      expect(content.contains('legacyRegisterLocalComic'), isFalse);
    },
  );

  test(
    'local comic sync avoids LocalManager and LocalComic.baseDir access',
    () async {
      final content = await File(
        'lib/foundation/db/local_comic_sync.dart',
      ).readAsString();
      expect(content.contains('LocalManager('), isFalse);
      expect(content.contains('.baseDir'), isFalse);
    },
  );

  test('import comic does not use legacy register path', () async {
    final content = await File('lib/utils/import_comic.dart').readAsString();
    expect(content.contains('legacyRegisterLocalComic'), isFalse);
  });
}
