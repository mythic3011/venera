import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local_metadata/local_metadata.dart';
import 'package:venera/utils/io.dart';

LocalComic _buildComic() {
  return LocalComic(
    id: '1',
    title: 'Series',
    subtitle: 'Author',
    tags: const ['tag'],
    directory: 'series',
    chapters: const ComicChapters({'c1': 'Chapter 1', 'c2': 'Chapter 2'}),
    cover: 'cover.jpg',
    comicType: ComicType.local,
    downloadedChapters: const ['c1', 'c2'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  group('LocalMetadataRepository', () {
    test('corrupt sidecar falls back to empty document', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_corrupt_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      await file.writeAsString('{broken json');

      final repository = LocalMetadataRepository(file.path);
      await repository.init();

      expect(repository.document.series, isEmpty);
      expect(repository.document.version, LocalMetadataDocument.currentVersion);
    });

    test('persist uses replace flow and roundtrips', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_write_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));

      final repository = LocalMetadataRepository(file.path);
      await repository.init();
      await repository.upsertSeries(
        LocalSeriesMeta(
          seriesKey: '0:1',
          groups: const [
            LocalChapterGroup(id: 'g1', label: 'Season 1', sortOrder: 0),
          ],
          chapters: const {
            'c1': LocalChapterMeta(
              chapterId: 'c1',
              displayTitle: 'Ep 1',
              groupId: 'g1',
              sortOrder: 0,
            ),
          },
        ),
      );

      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);

      final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(payload['version'], LocalMetadataDocument.currentVersion);
      expect((payload['series'] as Map<String, dynamic>).containsKey('0:1'), isTrue);

      final reloaded = LocalMetadataRepository(file.path);
      await reloaded.init();
      final series = reloaded.getSeries('0:1');
      expect(series, isNotNull);
      expect(series!.groups.single.label, 'Season 1');
      expect(series.chapters['c1']!.displayTitle, 'Ep 1');
    });
  });

  group('LocalManager metadata overlay', () {
    test('no sidecar keeps legacy render identical', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_overlay_1_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      final repository = LocalMetadataRepository(file.path);
      await repository.init();

      final manager = LocalManager();
      manager.setMetadataRepositoryForTest(repository);
      final comic = _buildComic();

      final effective = manager.readEffectiveChapters(comic);
      expect(effective, isNotNull);
      expect(effective!.groupedChapters.length, 1);
      expect(effective.groupedChapters.keys.single, LocalSeriesMeta.defaultGroupLabel);
      expect(
        effective.groupedChapters[LocalSeriesMeta.defaultGroupLabel],
        LinkedHashMap<String, String>.from({'c1': 'Chapter 1', 'c2': 'Chapter 2'}),
      );
      expect(comic.chapters!.allChapters, {'c1': 'Chapter 1', 'c2': 'Chapter 2'});
    });

    test('group and chapter overlays apply in read model only', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_overlay_2_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      final repository = LocalMetadataRepository(file.path);
      await repository.init();

      final manager = LocalManager();
      manager.setMetadataRepositoryForTest(repository);
      final comic = _buildComic();

      await manager.createGroup(comic, groupId: 's1', label: 'Season 1');
      await manager.assignChapterToGroup(comic, chapterId: 'c1', groupId: 's1');
      await manager.renameChapter(comic, chapterId: 'c1', newTitle: 'Episode One');
      await manager.reorderChapters(
        comic,
        groupId: LocalSeriesMeta.defaultGroupId,
        orderedChapterIds: const ['c2'],
      );

      final effective = manager.readEffectiveChapters(comic);
      expect(effective, isNotNull);
      expect(effective!.groupedChapters.keys.toList(), ['Chapters', 'Season 1']);
      expect(effective.groupedChapters['Season 1']!['c1'], 'Episode One');
      expect(effective.groupedChapters['Chapters']!['c2'], 'Chapter 2');

      expect(comic.chapters!.allChapters['c1'], 'Chapter 1');
      expect(comic.chapters!.allChapters['c2'], 'Chapter 2');
    });
  });
}
