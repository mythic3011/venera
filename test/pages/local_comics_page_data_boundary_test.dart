import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/pages/local_comics_page.dart';

LocalComic _localComic({required String id, required ComicType type}) {
  return LocalComic(
    id: id,
    title: id,
    subtitle: '',
    tags: const [],
    directory: id,
    chapters: null,
    cover: '',
    comicType: type,
    downloadedChapters: const [],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  test('canReorderLocalComicPages checks comic root ownership', () {
    expect(
      canReorderLocalComicPages(
        comicBaseDir: '/data/local/comic-a',
        localRootPath: '/data/local',
      ),
      isTrue,
    );
    expect(
      canReorderLocalComicPages(
        comicBaseDir: '/external/comic-a',
        localRootPath: '/data/local',
      ),
      isFalse,
    );
  });

  test('buildChapterMergeCandidates excludes target comic identity only', () {
    final target = _localComic(id: 'a', type: ComicType.local);
    final sameIdOtherType = _localComic(id: 'a', type: ComicType(99));
    final sameIdentity = _localComic(id: 'a', type: ComicType.local);
    final other = _localComic(id: 'b', type: ComicType.local);

    final candidates = buildChapterMergeCandidates(
      targetComic: target,
      allComics: [sameIdOtherType, sameIdentity, other],
    );

    expect(candidates, [sameIdOtherType, other]);
  });

  test('reorderChapterIds moves entry with flutter reorder semantics', () {
    final reordered = reorderChapterIds(
      chapterIds: const ['c1', 'c2', 'c3', 'c4'],
      oldIndex: 1,
      newIndex: 4,
    );
    expect(reordered, const ['c1', 'c3', 'c4', 'c2']);
  });

  test('resolveLocalChapterPageTarget maps chapter mode and single mode', () {
    expect(
      resolveLocalChapterPageTarget(
        hasChapters: true,
        selectedChapterId: 'ep-1',
      ),
      'ep-1',
    );
    expect(
      resolveLocalChapterPageTarget(
        hasChapters: false,
        selectedChapterId: null,
      ),
      0,
    );
  });

  test('localImageUriToPath strips file URI prefix only', () {
    expect(localImageUriToPath('file:///tmp/a b.jpg'), '/tmp/a b.jpg');
    expect(
      localImageUriToPath('https://example.com/a.jpg'),
      'https://example.com/a.jpg',
    );
  });

  test('applyCanonicalLocalLibraryView respects reconcile visibility set', () {
    final comics = [
      _localComic(id: 'show', type: ComicType.local),
      _localComic(id: 'hide', type: ComicType.local),
    ];
    final result = applyCanonicalLocalLibraryView(
      comics: comics,
      browseRecords: const [],
      visibleComicIds: const {'show'},
      sortType: LocalSortType.name,
    );
    expect(result.map((comic) => comic.id).toList(), ['show']);
  });
}
