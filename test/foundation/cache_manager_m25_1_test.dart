import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('venera-cache-m25-1-');
    final dataPath = '${tempDir.path}/data';
    final cachePath = '${tempDir.path}/cache_root';
    Directory(dataPath).createSync(recursive: true);
    Directory(cachePath).createSync(recursive: true);

    App.dataPath = dataPath;
    App.cachePath = cachePath;
    store = UnifiedComicsStore.atCanonicalPath(dataPath);
    await store.init();
    await App.initRuntimeComponents(
      canonicalStore: store,
      initAppData: () async {},
      initCanonicalStore: () async {},
      seedSourcePlatforms: () async {},
    );
    CacheManager.instance = null;
  });

  tearDown(() async {
    CacheManager.instance = null;
    await store.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('missing legacy cache db does not crash startup', () async {
    final legacy = File('${App.dataPath}/cache.db');
    if (legacy.existsSync()) {
      legacy.deleteSync();
    }

    final manager = CacheManager();
    await manager.writeCache('https://example.com/a.jpg@copy_manga@comic', [1, 2, 3]);
    final file = await manager.findCache('https://example.com/a.jpg@copy_manga@comic');
    expect(file, isNotNull);
  });

  test('corrupt legacy cache db does not crash startup', () async {
    final legacy = File('${App.dataPath}/cache.db');
    legacy.writeAsStringSync('not a sqlite database');

    final manager = CacheManager();
    await manager.writeCache('https://example.com/b.jpg@copy_manga@comic', [4, 5, 6]);
    final file = await manager.findCache('https://example.com/b.jpg@copy_manga@comic');
    expect(file, isNotNull);
  });

  test('legacy cache db is not required for cache lookup', () async {
    final manager = CacheManager();
    await manager.writeCache('https://example.com/c.jpg@copy_manga@comic', [7, 8, 9]);
    final legacy = File('${App.dataPath}/cache.db');
    if (legacy.existsSync()) {
      legacy.deleteSync();
    }
    final file = await manager.findCache('https://example.com/c.jpg@copy_manga@comic');
    expect(file, isNotNull);
  });

  test('new cache entry does not use raw url as primary key', () async {
    final key = 'https://sw.mangafunb.fun/w/wueyxingxuanlv/cover/a.jpg@copy_manga@wueyxingxuanlv';
    final manager = CacheManager();
    await manager.writeCache(key, List<int>.generate(16, (index) => Random(1).nextInt(255)));

    final rows = await store.customSelect(
      'SELECT cache_key, remote_url_hash, namespace FROM cache_entries LIMIT 1;',
    ).get();
    expect(rows, hasLength(1));
    final cacheKey = rows.first.read<String>('cache_key');
    final remoteUrlHash = rows.first.read<String?>('remote_url_hash');
    final namespace = rows.first.read<String>('namespace');
    expect(cacheKey, isNot(key));
    expect(cacheKey.length, 64);
    expect(remoteUrlHash, isNotNull);
    expect(remoteUrlHash!.length, 64);
    expect(namespace, 'other');
  });

  test('cache cleanup removes only cache files and cache metadata', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'remote:copy_manga:keep-user-data',
        title: 'Keep',
        normalizedTitle: 'keep',
      ),
    );
    await store.customStatement(
      '''
      INSERT OR REPLACE INTO favorites (comic_id, source_key)
      VALUES (?, ?);
      ''',
      ['remote:copy_manga:keep-user-data', 'copy_manga'],
    );
    await store.customStatement(
      '''
      INSERT OR REPLACE INTO history_events (
        id, comic_id, source_type_value, source_key, title, subtitle, cover,
        event_time, chapter_index, page_index, chapter_group, read_episode, max_page
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        'hist-1',
        'remote:copy_manga:keep-user-data',
        0,
        'copy_manga',
        'Keep',
        '',
        '',
        DateTime.now().toIso8601String(),
        0,
        0,
        null,
        '0',
        0,
      ],
    );

    final manager = CacheManager();
    await manager.writeCache('https://example.com/d.jpg@copy_manga@comic', [1, 2, 3, 4]);
    await manager.clear();

    final cacheRows = await store.customSelect(
      'SELECT COUNT(*) AS c FROM cache_entries;',
    ).getSingle();
    expect(cacheRows.read<int>('c'), 0);
    expect(Directory(CacheManager.cachePath).existsSync(), isTrue);

    final favoritesRows = await store.customSelect(
      'SELECT COUNT(*) AS c FROM favorites;',
    ).getSingle();
    final historyRows = await store.customSelect(
      'SELECT COUNT(*) AS c FROM history_events;',
    ).getSingle();
    expect(favoritesRows.read<int>('c'), 1);
    expect(historyRows.read<int>('c'), 1);
  });
}
