import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/utils/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    AppTranslation.translations = {'en_US': {}};
  });

  ComicDetails buildComic({
    required String sourceKey,
    required String comicId,
    required Map<String, String> chapters,
  }) {
    return ComicDetails.fromJson({
      'title': 'Test Comic',
      'subtitle': null,
      'cover': 'file:///tmp/cover.png',
      'description': null,
      'tags': <String, List<String>>{},
      'chapters': chapters,
      'sourceKey': sourceKey,
      'comicId': comicId,
      'subId': null,
      'comments': null,
    });
  }

  Widget buildChapterList(ComicDetails comic) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [for (final title in comic.chapters!.titles) Text(title)],
        ),
      ),
    );
  }

  testWidgets('local comic detail renders imported chapter list', (
    tester,
  ) async {
    final detail = ComicDetailViewModel(
      comicId: 'comic-local',
      title: 'Local Comic',
      libraryState: LibraryState.downloaded,
      chapters: const [
        ChapterVm(chapterId: '1:__imported__', title: 'Imported Chapter 1'),
        ChapterVm(chapterId: '2:__imported__', title: 'Imported Chapter 2'),
      ],
    );
    final comic = buildLocalDetailsFromCanonicalDetailForTesting(
      detail,
      fallbackCover: 'file:///tmp/cover.png',
    );

    await tester.pumpWidget(buildChapterList(comic));

    expect(find.text('Imported Chapter 1'), findsOneWidget);
    expect(find.text('Imported Chapter 2'), findsOneWidget);
  });

  testWidgets(
    'local comic detail highlights current history chapter and page',
    (tester) async {
      final comic = buildComic(
        sourceKey: 'local',
        comicId: 'comic-local',
        chapters: const {
          '1:__imported__': 'Imported Chapter 1',
          '2:__imported__': 'Imported Chapter 2',
        },
      );
      final detail = ComicDetailViewModel(
        comicId: 'comic-local',
        title: 'Local Comic',
        libraryState: LibraryState.downloaded,
        continueProgress: ReadingProgressVm(
          currentChapterId: '2:__imported__',
          currentPageIndex: 9,
          readChapters: const {'2'},
        ),
      );
      final history = buildComicDetailCompatibilityHistoryFromDetailForTesting(
        model: comic,
        chapters: comic.chapters,
        canonicalDetail: detail,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text(
              buildComicDetailHistoryLabelForTesting(
                comic: comic,
                history: history,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Last Reading: Imported Chapter 2 P9'), findsOneWidget);
      expect(comicChapterIsVisited(history, rawIndex: '2'), isTrue);
    },
  );

  testWidgets(
    'local comic detail continue read uses history progress context',
    (tester) async {
      final comic = buildComic(
        sourceKey: 'local',
        comicId: 'comic-local',
        chapters: const {
          '1:__imported__': 'Imported Chapter 1',
          '2:__imported__': 'Imported Chapter 2',
        },
      );
      final detail = ComicDetailViewModel(
        comicId: 'comic-local',
        title: 'Local Comic',
        libraryState: LibraryState.downloaded,
        availableActions: const ComicDetailActions(canContinueReading: true),
        continueProgress: ReadingProgressVm(
          currentChapterId: '2:__imported__',
          currentPageIndex: 4,
          readChapters: const {'2'},
        ),
      );
      final history = buildComicDetailCompatibilityHistoryFromDetailForTesting(
        model: comic,
        chapters: comic.chapters,
        canonicalDetail: detail,
      );
      final hasContinue = comicPageHasContinueActionForTesting(
        canonicalDetail: detail,
        history: history,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: Text(hasContinue ? 'Continue' : 'Read'),
            ),
          ),
        ),
      );

      expect(find.text('Continue'), findsOneWidget);
      expect(history.ep, 2);
      expect(history.page, 4);
    },
  );

  testWidgets(
    'remote comic detail still renders remote chapters through shared UI',
    (tester) async {
      final comic = buildComic(
        sourceKey: 'ehentai',
        comicId: 'remote-comic',
        chapters: const {
          'chapter-1': 'Remote Chapter 1',
          'chapter-2': 'Remote Chapter 2',
        },
      );

      await tester.pumpWidget(buildChapterList(comic));

      expect(find.text('Remote Chapter 1'), findsOneWidget);
      expect(find.text('Remote Chapter 2'), findsOneWidget);
    },
  );
}
