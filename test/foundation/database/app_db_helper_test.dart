import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/database/app_db_helper.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  test('AppDbHelper.write serializes concurrent writes', () async {
    final events = <String>[];
    final firstGate = Completer<void>();

    final first = AppDbHelper.instance.write<void>('test.first', () async {
      events.add('first:start');
      await firstGate.future;
      events.add('first:end');
    });

    final second = AppDbHelper.instance.write<void>('test.second', () async {
      events.add('second:start');
      events.add('second:end');
    });

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, ['first:start']);
    firstGate.complete();

    await Future.wait([first, second]);
    expect(events, ['first:start', 'first:end', 'second:start', 'second:end']);
  });

  test('AppDbHelper.transaction uses the same write lock queue', () async {
    final db = UnifiedComicsStore(':memory:');
    await db.init();
    addTearDown(db.close);

    final events = <String>[];
    final firstGate = Completer<void>();

    final tx = AppDbHelper.instance.transaction<void>('test.tx', db, () async {
      events.add('tx:start');
      await firstGate.future;
      events.add('tx:end');
    });

    final write = AppDbHelper.instance.write<void>('test.write', () async {
      events.add('write:start');
      events.add('write:end');
    });

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, ['tx:start']);
    firstGate.complete();

    await Future.wait([tx, write]);
    expect(events, ['tx:start', 'tx:end', 'write:start', 'write:end']);
  });

  test('nested customWrite in transaction rolls back as one atomic unit', () async {
    final db = UnifiedComicsStore(':memory:');
    await db.init();
    addTearDown(db.close);

    expect(AppDbHelper.pendingWrites, 0);

    await expectLater(
      AppDbHelper.instance.transaction<void>('source.test.atomicity', db, () async {
        expect(AppDbHelper.pendingWrites, 1);
        await AppDbHelper.instance.customWrite(
          'source.test.atomicity.insert',
          db,
          '''
          INSERT INTO source_repositories (
            id, name, index_url, enabled, user_added, trust_level, created_at_ms, updated_at_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
          ''',
          [
            'repo-atomic',
            'Atomic Repo',
            'https://example.com/index.json',
            1,
            0,
            'trusted',
            1,
            1,
          ],
        );
        await AppDbHelper.instance.customWrite(
          'source.test.atomicity.fail',
          db,
          'INSERT INTO source_packages (source_key) VALUES (?);',
          const ['invalid-row'],
        );
      }),
      throwsA(isA<Object>()),
    );

    final row = await db.loadSourceRepositoryById('repo-atomic');
    expect(row, isNull, reason: 'outer transaction should rollback nested writes');
    expect(AppDbHelper.pendingWrites, 0);
  });
}
