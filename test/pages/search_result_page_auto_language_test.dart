import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/pages/search_result_page.dart';

SearchPageData searchDataWithOptions(List<SearchOptions> options) {
  return SearchPageData(options, null, null);
}

void main() {
  test('no-op when setting is none', () {
    final query = applyAutoLanguageFilter(
      query: 'tag:abc',
      searchPageData: searchDataWithOptions([
        SearchOptions(
          LinkedHashMap.from({'a': 'A'}),
          'Language',
          'select',
          null,
        ),
      ]),
      setting: 'none',
    );
    expect(query, 'tag:abc');
  });

  test('no-op when search page data does not support language filter', () {
    final query = applyAutoLanguageFilter(
      query: 'tag:abc',
      searchPageData: searchDataWithOptions([
        SearchOptions(
          LinkedHashMap.from({'a': 'A'}),
          'Sort',
          'select',
          null,
        ),
      ]),
      setting: 'english',
    );
    expect(query, 'tag:abc');
  });

  test('appends language filter when language option label exists', () {
    final query = applyAutoLanguageFilter(
      query: 'tag:abc',
      searchPageData: searchDataWithOptions([
        SearchOptions(
          LinkedHashMap.from({'all': 'All'}),
          'Language',
          'select',
          null,
        ),
      ]),
      setting: 'english',
    );
    expect(query, 'tag:abc language:english');
  });

  test('appends language filter when language namespace keys exist', () {
    final query = applyAutoLanguageFilter(
      query: 'tag:abc',
      searchPageData: searchDataWithOptions([
        SearchOptions(
          LinkedHashMap.from({'language:english': 'English'}),
          'Tags',
          'select',
          null,
        ),
      ]),
      setting: 'english',
    );
    expect(query, 'tag:abc language:english');
  });

  test('does not append duplicate language filter tokens', () {
    final query = applyAutoLanguageFilter(
      query: 'tag:abc Language : japanese',
      searchPageData: searchDataWithOptions([
        SearchOptions(
          LinkedHashMap.from({'a': 'A'}),
          'Language',
          'select',
          null,
        ),
      ]),
      setting: 'english',
    );
    expect(query, 'tag:abc Language : japanese');
  });

  test('empty query becomes a language-only query', () {
    final query = applyAutoLanguageFilter(
      query: '   ',
      searchPageData: searchDataWithOptions([
        SearchOptions(
          LinkedHashMap.from({'a': 'A'}),
          'Language',
          'select',
          null,
        ),
      ]),
      setting: 'chinese',
    );
    expect(query, 'language:chinese');
  });
}
