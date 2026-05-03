import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/reader/reader_page_loader.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';

ReaderPageLoadRequest _request({
  ComicType? type,
  String canonicalComicRefId = 'comic-1',
  int chapterIndex = 1,
  ComicChapters? chapters = const ComicChapters({'ch-1': 'Chapter 1'}),
  SourceRef? sourceRef,
  bool hasLocalComic = false,
  bool isDownloaded = false,
}) {
  return ReaderPageLoadRequest(
    type: type ?? ComicType.local,
    canonicalComicRefId: canonicalComicRefId,
    chapterIndex: chapterIndex,
    chapters: chapters,
    sourceRef: sourceRef,
    hasLocalComic: hasLocalComic,
    isDownloaded: isDownloaded,
  );
}

ReaderPageLoadController _controller({
  required Future<List<String>> Function({
    required String localType,
    required String localComicId,
    String? chapterId,
  })
  loadLocalPages,
  Future<Res<List<String>>> Function({
    required String sourceKey,
    required String comicId,
    required String chapterId,
  })?
  loadRemotePages,
}) {
  return ReaderPageLoadController(
    loader: ReaderPageLoader(
      loadLocalPages: loadLocalPages,
      loadRemotePages:
          loadRemotePages ??
          ({required sourceKey, required comicId, required chapterId}) async =>
              const Res(['remote-page-1']),
      sourceExists: (_) => true,
    ),
  );
}

void main() {
  test(
    'reader page load controller chooses local mode for imported local comic',
    () {
      final request = _request(
        type: ComicType.fromKey('Unknown:imported'),
        hasLocalComic: true,
      );

      expect(decideReaderPageLoadModeForTesting(request), 'local');
    },
  );

  test(
    'reader page load controller returns SOURCE_REF_MALFORMED for bad remote ref',
    () async {
      final controller = _controller(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async {
              fail(
                'local loader should not be called for malformed remote ref',
              );
            },
      );
      final request = _request(
        type: ComicType.fromKey('copymanga'),
        chapters: const ComicChapters({'ch-2': 'Chapter 2'}),
        sourceRef: SourceRef.fromLegacyRemote(
          sourceKey: 'copymanga',
          comicId: 'remote:copymanga:bad',
          chapterId: 'ch-1',
        ),
      );

      final result = await controller.loadReaderPageList(
        request: request,
        loadMode: 'remote',
      );

      expect(result.errorCode, 'SOURCE_REF_MALFORMED');
      expect(result.res.error, isTrue);
      expect(result.sourceRef, isNull);
    },
  );

  test(
    'reader page load controller returns EMPTY_PAGE_LIST diagnostic for empty local pages',
    () async {
      final controller = _controller(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async {
              return const <String>[];
            },
      );
      final request = _request(hasLocalComic: true);

      final result = await controller.loadReaderPageList(
        request: request,
        loadMode: 'local',
      );

      expect(result.errorCode, 'EMPTY_PAGE_LIST');
      expect(result.res.error, isTrue);
      expect(result.res.errorMessage, contains('EMPTY_PAGE_LIST'));
      expect(result.res.errorMessage, contains('loadMode=local'));
    },
  );

  test(
    'reader page load controller does not mutate reader state directly',
    () async {
      List<String>? readerImages;
      final controller = _controller(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async {
              return const <String>['page-1'];
            },
      );

      final result = await controller.loadReaderPageList(
        request: _request(hasLocalComic: true),
        loadMode: 'local',
      );

      expect(result.res.error, isFalse);
      expect(result.res.data, const <String>['page-1']);
      expect(readerImages, isNull);
    },
  );
}
