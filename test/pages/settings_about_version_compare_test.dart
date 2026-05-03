import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/settings/settings_page.dart';

void main() {
  test('isVersionGreater treats missing segments as zero', () {
    expect(isVersionGreater('1.6', '1.6.0'), isFalse);
    expect(isVersionGreater('1.6.0', '1.6'), isFalse);
    expect(isVersionGreater('1.6.1', '1.6'), isTrue);
    expect(isVersionGreater('1.6', '1.6.1'), isFalse);
  });

  test('isVersionGreater compares semantic numeric order', () {
    expect(isVersionGreater('1.6.10', '1.6.3'), isTrue);
    expect(isVersionGreater('1.6.3', '1.6.10'), isFalse);
    expect(isVersionGreater('2.0.0', '1.99.99'), isTrue);
    expect(isVersionGreater('1.0.0', '1.0.0'), isFalse);
  });
}
