import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/db/canonical_db_write_gate.dart';
import 'package:venera/foundation/diagnostics/app_lifecycle_guard.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

class _FakeSqliteException implements Exception {
  _FakeSqliteException(this.resultCode, [this.extendedResultCode]);

  final int resultCode;
  final int? extendedResultCode;

  @override
  String toString() => 'database is locked';
}

void main() {
  late bool oldInitialized;
  late String? oldDataPath;

  setUp(() async {
    oldInitialized = App.isInitialized;
    oldDataPath = oldInitialized ? App.dataPath : null;
    AppDiagnostics.resetForTesting();
    await AppLifecycleGuard.instance.resetForTesting();
  });

  tearDown(() async {
    await AppLifecycleGuard.instance.resetForTesting();
    AppDiagnostics.resetForTesting();
    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath!;
    }
    App.isInitialized = oldInitialized;
  });

  test(
    'startup after missing cleanShutdown marker emits previousUncleanExit',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'venera_lifecycle_unclean_',
      );
      App.dataPath = dir.path;
      App.isInitialized = true;

      final marker = File('${dir.path}/runtime/lifecycle_marker.json');
      await marker.parent.create(recursive: true);
      await marker.writeAsString(
        jsonEncode({
          'pid': 123,
          'appVersion': '1.0.0',
          'platform': 'macos',
          'startedAt': '2026-05-01T00:00:00Z',
          'lastHeartbeatAt': '2026-05-01T00:01:00Z',
        }),
      );

      await AppLifecycleGuard.instance.start(
        heartbeatInterval: const Duration(days: 1),
      );

      final events = AppDiagnostics.recent(channel: 'app.lifecycle');
      expect(
        events.any((e) => e.message == 'app.lifecycle.previousUncleanExit'),
        isTrue,
      );

      await dir.delete(recursive: true);
    },
  );

  test('clean shutdown marker suppresses false unclean-exit warning', () async {
    final dir = await Directory.systemTemp.createTemp(
      'venera_lifecycle_clean_',
    );
    App.dataPath = dir.path;
    App.isInitialized = true;

    final marker = File('${dir.path}/runtime/lifecycle_marker.json');
    await marker.parent.create(recursive: true);
    await marker.writeAsString(
      jsonEncode({
        'pid': 123,
        'appVersion': '1.0.0',
        'platform': 'macos',
        'startedAt': '2026-05-01T00:00:00Z',
        'lastHeartbeatAt': '2026-05-01T00:01:00Z',
        'cleanShutdown': {
          'pid': 123,
          'reason': 'user_requested_close',
          'timestamp': '2026-05-01T00:02:00Z',
        },
      }),
    );

    await AppLifecycleGuard.instance.start(
      heartbeatInterval: const Duration(days: 1),
    );

    final events = AppDiagnostics.recent(channel: 'app.lifecycle');
    expect(
      events.any((e) => e.message == 'app.lifecycle.previousUncleanExit'),
      isFalse,
    );

    await dir.delete(recursive: true);
  });

  test(
    'uncaught SQLite code 5 and 517 classified as app.fatal.dbLocked',
    () async {
      final code5 = classifyFatal(_FakeSqliteException(5));
      final code517 = classifyFatal(_FakeSqliteException(5, 517));

      expect(code5.kind, 'app.fatal.dbLocked');
      expect(code5.sqliteCode, 5);
      expect(code517.kind, 'app.fatal.dbLocked');
      expect(code517.sqliteCode, 517);
    },
  );

  test(
    'shutdown requested with pending DB writes emits pending count',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'venera_lifecycle_pending_',
      );
      App.dataPath = dir.path;
      App.isInitialized = true;

      final write = CanonicalDbWriteGate.run<void>(
        dbPath: '/tmp/venera_pending.db',
        domain: 'test',
        operation: 'hold',
        callback: () async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 15));
      await AppLifecycleGuard.instance.shutdownRequested(
        reason: 'test_close',
        timeout: const Duration(milliseconds: 1),
      );
      await write;

      final events = AppDiagnostics.recent(channel: 'app.lifecycle');
      final event = events.lastWhere(
        (e) => e.message == 'app.lifecycle.shutdownRequested',
      );
      expect((event.data['pendingDbWrites'] as int) >= 1, isTrue);

      await dir.delete(recursive: true);
    },
  );

  test('shutdown timeout emits shutdownWithPendingWrites', () async {
    final dir = await Directory.systemTemp.createTemp(
      'venera_lifecycle_timeout_',
    );
    App.dataPath = dir.path;
    App.isInitialized = true;

    final write = CanonicalDbWriteGate.run<void>(
      dbPath: '/tmp/venera_timeout.db',
      domain: 'test',
      operation: 'hold',
      callback: () async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    await AppLifecycleGuard.instance.shutdownRequested(
      reason: 'test_close',
      timeout: const Duration(milliseconds: 2),
    );
    await write;

    final events = AppDiagnostics.recent(channel: 'app.lifecycle');
    expect(
      events.any((e) => e.message == 'app.lifecycle.shutdownWithPendingWrites'),
      isTrue,
    );

    await dir.delete(recursive: true);
  });
}
