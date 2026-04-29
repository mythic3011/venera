import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';

void main() {
  test('source key ids are deterministic and do not use string hashCode', () {
    final nhentai = ComicType.fromKey('nhentai');

    expect(nhentai.value, stableSourceKeyId('nhentai'));
    expect(nhentai.value, isNot('nhentai'.hashCode));
  });

  test('local source key remains reserved as zero', () {
    expect(ComicType.fromKey('local'), ComicType.local);
    expect(ComicType.local.value, 0);
  });

  test('unknown source ids preserve original integer for diagnostics', () {
    final unknown = ComicType.fromKey('Unknown:122396838');

    expect(unknown.value, 122396838);
    expect(unknown.sourceKey, 'Unknown:122396838');
  });
}
