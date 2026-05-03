import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local.dart';

void main() {
  test(
    'LocalManager legacy path access throws clear error when uninitialized',
    () {
      expect(
        () => LocalManager().requireLegacyPathForModelAccess(
          operation: 'test.guard',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('legacy-only'),
          ),
        ),
      );
    },
  );
}
