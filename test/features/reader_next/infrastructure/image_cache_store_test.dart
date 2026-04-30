import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/features/reader_next/infrastructure/image_cache_store.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  group('CacheManagerImageCacheStore', () {
    test('write and read round trip with runtime cache key tuple', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reader_next_cache_store_',
      );
      final fileMap = <String, String>{};

      Future<File?> findCache(String key) async {
        final path = fileMap[key];
        if (path == null) return null;
        final file = File(path);
        return file.existsSync() ? file : null;
      }

      Future<void> writeCache(String key, List<int> bytes) async {
        final filePath = p.join(tempDir.path, key.hashCode.toString());
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        fileMap[key] = filePath;
      }

      final store = CacheManagerImageCacheStore(
        findCache: findCache,
        writeCache: writeCache,
      );
      const runtimeKey = 'nhentai@remote:nhentai:646922@646922@ch-1@img-1';

      await store.write(cacheKey: runtimeKey, bytes: <int>[1, 3, 3, 7]);
      final read = await store.read(cacheKey: runtimeKey);

      expect(read, <int>[1, 3, 3, 7]);
      tempDir.deleteSync(recursive: true);
    });

    test('rejects malformed runtime cache key', () async {
      final store = CacheManagerImageCacheStore(
        findCache: (_) async => null,
        writeCache: (_, __) async {},
      );

      expect(
        () => store.read(cacheKey: 'bad-key'),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CACHE_KEY_INVALID'),
        ),
      );
    });
  });
}
