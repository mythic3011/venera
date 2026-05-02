import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/local_storage_legacy_bridge.dart';

class _LatePathHolder {
  late final String path;
}

void main() {
  test('legacy local comics path safe getter returns null when path is uninitialized', () {
    final holder = _LatePathHolder();
    final result = tryReadLocalComicsStoragePath(reader: () => holder.path);
    expect(result, isNull);
  });

  test('local comic lookup returns unavailable when LocalManager database is uninitialized', () {
    final result = legacyLookupLocalComicByName(
      'comic-a',
      finder: (_) => throw StateError(
        "LateInitializationError: Field '_db' has not been initialized.",
      ),
    );

    expect(result, isA<LegacyLocalComicLookupUnavailable>());
  });
}
