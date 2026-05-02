import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/features/reader_next/runtime/local_resolver.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

class _FakeChapterCollection {
  _FakeChapterCollection(this.allChapters);
  final Map<String, Object> allChapters;
}

class _FakeLocalComic {
  _FakeLocalComic({
    required this.hasChapters,
    required this.chapters,
  });

  final bool hasChapters;
  final _FakeChapterCollection? chapters;
}

void main() {
  group('LegacyLocalReaderPageResolver', () {
    test('maps legacy late failure to LOCAL_STORAGE_UNAVAILABLE', () async {
      final resolver = LegacyLocalReaderPageResolver(
        ensureInitialized: () async {},
        findComicBySourceKey: (_, __) {
          throw StateError('LateInitializationError: LocalManager not ready');
        },
      );
      final identity = ComicIdentity(
        canonicalComicId: 'local:comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'comic-1',
          chapterRefId: '1',
        ),
      );

      await expectLater(
        () => resolver.loadReaderPageImages(
          identity: identity,
          chapterRefId: '1',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'LOCAL_STORAGE_UNAVAILABLE'),
        ),
      );
    });

    test('local resolver throws LOCAL_PAGE_FILE_MISSING when page file is absent', () async {
      final resolver = LegacyLocalReaderPageResolver(
        ensureInitialized: () async {},
        findComicBySourceKey: (_, __) => _FakeLocalComic(
          hasChapters: true,
          chapters: _FakeChapterCollection({'1': Object()}),
        ),
        loadImagesBySourceKey: (_, __, ___) async => <String>[
          '/tmp/definitely-missing-reader-next-image.jpg',
        ],
      );
      final identity = ComicIdentity(
        canonicalComicId: 'local:comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'comic-1',
          chapterRefId: '1',
        ),
      );

      await expectLater(
        () => resolver.loadReaderPageImages(
          identity: identity,
          chapterRefId: '1',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'LOCAL_PAGE_FILE_MISSING'),
        ),
      );
    });

    test('local resolver returns renderable local file path when file exists', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'reader-next-local-resolver-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final file = File(FilePath.join(tempDir.path, 'page-1.jpg'));
      file.writeAsBytesSync(<int>[0, 1, 2, 3]);

      final resolver = LegacyLocalReaderPageResolver(
        ensureInitialized: () async {},
        findComicBySourceKey: (_, __) => _FakeLocalComic(
          hasChapters: true,
          chapters: _FakeChapterCollection({'1': Object()}),
        ),
        loadImagesBySourceKey: (_, __, ___) async => <String>[file.path],
      );
      final identity = ComicIdentity(
        canonicalComicId: 'local:comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'comic-1',
          chapterRefId: '1',
        ),
      );

      final refs = await resolver.loadReaderPageImages(
        identity: identity,
        chapterRefId: '1',
        page: 1,
      );

      expect(refs, hasLength(1));
      expect(refs.first.imageUrl, file.path);
    });
  });
}
