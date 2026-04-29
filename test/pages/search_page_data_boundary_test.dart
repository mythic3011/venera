import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/search_page.dart';

void main() {
  test('resolveConfiguredSearchSources keeps only available configured keys', () {
    final sources = resolveConfiguredSearchSources(
      availableSourceKeys: const ['a', 'b', 'c'],
      configuredSources: const ['b', 'x', 1, 'a'],
    );

    expect(sources, const ['b', 'a']);
  });

  test('resolveSearchTarget falls back to first source when current missing', () {
    final target = resolveSearchTarget(
      currentSearchTarget: 'x',
      searchSources: const ['b', 'a'],
    );

    expect(target, 'b');
  });

  test('resolveInitialSearchSelection returns aggregated mode when configured', () {
    final selection = resolveInitialSearchSelection(
      defaultSearchTarget: '_aggregated_',
      searchSources: const ['b', 'a'],
    );

    expect(selection.aggregatedSearch, isTrue);
    expect(selection.searchTarget, isEmpty);
  });

  test('resolveInitialSearchSelection picks configured source target', () {
    final selection = resolveInitialSearchSelection(
      defaultSearchTarget: 'a',
      searchSources: const ['b', 'a'],
    );

    expect(selection.aggregatedSearch, isFalse);
    expect(selection.searchTarget, 'a');
  });
}
