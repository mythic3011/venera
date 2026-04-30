import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/features/reader_next/infrastructure/session_store.dart';
import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/features/reader_next/runtime/session.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  group('DriftReaderSessionStore', () {
    late Directory tempDir;
    late UnifiedComicsStore store;
    late DriftReaderSessionStore sessionStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reader_next_session_');
      store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
      sessionStore = DriftReaderSessionStore(store: store);
    });

    tearDown(() async {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('save/load round trip keeps canonical and upstream identities', () async {
      final sourceRef = SourceRef.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
        chapterRefId: 'ch-4',
      );
      final session = ReaderResumeSession(
        canonicalComicId: 'remote:nhentai:646922',
        sourceRef: sourceRef,
        chapterRefId: 'ch-4',
        page: 8,
      );

      await sessionStore.save(session);
      final loaded = await sessionStore.load(
        canonicalComicId: 'remote:nhentai:646922',
      );

      expect(loaded, isNotNull);
      expect(loaded!.canonicalComicId, 'remote:nhentai:646922');
      expect(loaded.sourceRef.sourceKey, 'nhentai');
      expect(loaded.sourceRef.upstreamComicRefId, '646922');
      expect(loaded.chapterRefId, 'ch-4');
      expect(loaded.page, 8);
    });

    test('save rejects malformed resume session', () async {
      final session = ReaderResumeSession(
        canonicalComicId: 'not-namespaced',
        sourceRef: SourceRef.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
        ),
        chapterRefId: 'ch-1',
        page: 1,
      );

      await expectLater(
        () => sessionStore.save(session),
        throwsA(
          isA<ReaderRuntimeException>()
              .having((e) => e.code, 'code', 'CANONICAL_ID_INVALID'),
        ),
      );
    });
  });
}
