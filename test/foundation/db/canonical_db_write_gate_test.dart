import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/db/canonical_db_write_gate.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/sources/source_ref.dart';

class _FakeSqliteException implements Exception {
  _FakeSqliteException(this.resultCode, [this.extendedResultCode]);

  final int resultCode;
  final int? extendedResultCode;

  @override
  String toString() =>
      'Fake sqlite exception ($resultCode/$extendedResultCode)';
}

void main() {
  setUp(AppDiagnostics.resetForTesting);

  test('retries SQLITE_LOCKED_SHAREDCACHE (517) and succeeds', () async {
    var calls = 0;
    await CanonicalDbWriteGate.run<void>(
      dbPath: '/tmp/venera.db',
      domain: 'test',
      operation: 'retry_517',
      callback: () async {
        calls += 1;
        if (calls < 3) {
          throw _FakeSqliteException(5, 517);
        }
      },
    );
    expect(calls, 3);
  });

  test('does not retry non-lock sqlite errors', () async {
    var calls = 0;
    await expectLater(
      CanonicalDbWriteGate.run<void>(
        dbPath: '/tmp/venera.db',
        domain: 'test',
        operation: 'no_retry',
        callback: () async {
          calls += 1;
          throw _FakeSqliteException(1, 1);
        },
      ),
      throwsA(isA<_FakeSqliteException>()),
    );
    expect(calls, 1);
  });

  test(
    'final lock failure emits db.write.locked without SQL details',
    () async {
      await expectLater(
        CanonicalDbWriteGate.run<void>(
          dbPath: '/tmp/venera.db',
          domain: 'test',
          operation: 'final_lock',
          callback: () async => throw _FakeSqliteException(5),
        ),
        throwsA(isA<_FakeSqliteException>()),
      );

      final events = AppDiagnostics.recent(channel: 'db.write');
      final lockEvent = events.lastWhere(
        (event) => event.message == 'db.write.locked',
      );
      expect(lockEvent.data['domain'], 'test');
      expect(lockEvent.data['operation'], 'final_lock');
      expect(lockEvent.data['sqliteCode'], 5);
      expect(lockEvent.data['errorType'], '_FakeSqliteException');
      expect(lockEvent.message.contains('INSERT'), isFalse);
      expect(lockEvent.message.contains('/'), isFalse);
    },
  );

  test(
    'concurrent reader session upsert + active tab update do not throw',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'venera-gate-reader-',
      );
      final store = UnifiedComicsStore(
        p.join(tempDir.path, 'data', 'venera.db'),
      );
      await store.init();
      try {
        await store.upsertComic(
          const ComicRecord(
            id: 'comic-1',
            title: 'Comic 1',
            normalizedTitle: 'comic 1',
          ),
        );
        await store.upsertReaderSession(
          const ReaderSessionRecord(id: 'session-1', comicId: 'comic-1'),
        );
        await store.upsertReaderTab(
          const ReaderTabRecord(
            id: 'tab-1',
            sessionId: 'session-1',
            comicId: 'comic-1',
            chapterId: 'chapter-1',
            pageIndex: 0,
            sourceRefJson: '{}',
          ),
        );

        await Future.wait([
          store.upsertReaderSession(
            const ReaderSessionRecord(
              id: 'session-1',
              comicId: 'comic-1',
              activeTabId: 'tab-1',
            ),
          ),
          store.setReaderSessionActiveTab(
            sessionId: 'session-1',
            activeTabId: 'tab-1',
          ),
        ]);
        final session = await store.loadReaderSessionByComic('comic-1');
        expect(session?.activeTabId, 'tab-1');
      } finally {
        await store.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'concurrent Appdata.saveData + reader session write do not throw',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'venera-gate-appdata-',
      );
      final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
      await store.init();
      try {
        App.dataPath = tempDir.path;
        final appdata = Appdata.createForTest(settingsStore: store);
      appdata.settings['reader_next_enabled'] = true;
        await store.upsertComic(
          const ComicRecord(
            id: 'comic-2',
            title: 'Comic 2',
            normalizedTitle: 'comic 2',
          ),
        );

      await Future.wait([
        appdata.saveData(false),
        store.upsertReaderSession(
          const ReaderSessionRecord(
            id: 'reader-session:comic-2',
            comicId: 'comic-2',
          ),
        ),
      ]);

      await store.upsertReaderTab(
        const ReaderTabRecord(
          id: 'tab-2',
          sessionId: 'reader-session:comic-2',
          comicId: 'comic-2',
          chapterId: 'chapter-2',
          pageIndex: 0,
          sourceRefJson: '{}',
        ),
      );
      await Future.wait([
        appdata.saveData(false),
        store.upsertReaderSession(
          const ReaderSessionRecord(
            id: 'reader-session:comic-2',
            comicId: 'comic-2',
            activeTabId: 'tab-2',
          ),
        ),
        store.setReaderSessionActiveTab(
          sessionId: 'reader-session:comic-2',
          activeTabId: 'tab-2',
        ),
      ]);
      } finally {
        await store.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test('Appdata.saveData does not issue full-table app_settings delete', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-appdata-no-full-delete-',
    );
    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    try {
      App.dataPath = tempDir.path;
      final appdata = Appdata.createForTest(settingsStore: store);
      appdata.settings['deviceId'] = 'db-no-delete-device';
      await store.customStatement('''
        CREATE TRIGGER IF NOT EXISTS app_settings_no_delete
        BEFORE DELETE ON app_settings
        BEGIN
          SELECT RAISE(ABORT, 'no delete from app_settings');
        END;
      ''');

      await appdata.saveData(false);
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('unchanged reader session progress is not written twice', () async {
    AppDiagnostics.resetForTesting();
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-dedupe-',
    );
    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    try {
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-dedupe',
          title: 'Comic Dedupe',
          normalizedTitle: 'comic dedupe',
        ),
      );
      final repository = ReaderSessionRepository(store: store);
      final sourceRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-dedupe',
        chapterId: 'chapter-1',
      );

      await repository.upsertCurrentLocation(
        comicId: 'comic-dedupe',
        chapterId: 'chapter-1',
        pageIndex: 1,
        sourceRef: sourceRef,
      );
      final firstWriteCount = AppDiagnostics.recent(
        channel: 'db.write',
      ).where((event) => event.message == 'db.write.start').length;

      await repository.upsertCurrentLocation(
        comicId: 'comic-dedupe',
        chapterId: 'chapter-1',
        pageIndex: 1,
        sourceRef: sourceRef,
      );
      final secondWriteCount = AppDiagnostics.recent(
        channel: 'db.write',
      ).where((event) => event.message == 'db.write.start').length;

      expect(secondWriteCount, firstWriteCount);
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
