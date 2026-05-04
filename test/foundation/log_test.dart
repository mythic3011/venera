import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/diagnostics/log_diagnostics.dart';
import 'package:venera/foundation/diagnostics/log_export_bundle.dart';

void main() {
  setUp(() {
    Log.clear();
    AppDiagnostics.resetForTesting();
  });

  tearDown(() async {
    await Log.closeFileSink();
    AppDiagnostics.resetForTesting();
  });

  test('Log.serialize returns level title content time', () {
    final item = LogItem(LogLevel.error, 'T', 'C');
    final serialized = Log.serialize(item);

    expect(serialized['level'], 'error');
    expect(serialized['title'], 'T');
    expect(serialized['content'], 'C');
    expect(DateTime.tryParse(serialized['time'] as String), isNotNull);
  });

  test('buildExportFileName is descriptive and stable', () {
    final filename = Log.buildExportFileName(
      timestamp: DateTime.parse('2026-04-30T12:34:56.789Z'),
    );
    expect(filename, 'venera_logs_export_2026-04-30_12-34-56-789Z.txt');
  });

  test('Log.newest returns newest matching logs first', () {
    Log.info('i1', 'i1');
    Log.error('e1', 'e1');
    Log.error('e2', 'e2');

    final newestErrors = Log.newest(level: 'error', limit: 2);
    expect(newestErrors.length, 2);
    expect(newestErrors[0].title, 'e2');
    expect(newestErrors[1].title, 'e1');
  });

  test('Log.newest limit is not hard-capped by Log API', () {
    for (var i = 0; i < 10; i++) {
      Log.info('i$i', 'c$i');
    }

    final logs = Log.newest(limit: 999999);
    expect(logs.length, 10);
  });

  test('Log.logFilePath follows initialization state', () {
    final oldInitialized = App.isInitialized;
    final oldDataPath = oldInitialized ? App.dataPath : null;
    final oldExternal = App.externalStoragePath;

    App.isInitialized = false;
    expect(Log.logFilePath, isNull);

    App.dataPath = Directory.systemTemp.path;
    App.externalStoragePath = Directory.systemTemp.path;
    App.isInitialized = true;
    expect(Log.logFilePath, isNotNull);

    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath;
    }
    App.externalStoragePath = oldExternal;
    App.isInitialized = oldInitialized;
  });

  test('Log.exportToFile writes current in-memory logs', () async {
    final oldInitialized = App.isInitialized;
    final oldDataPath = oldInitialized ? App.dataPath : null;
    final oldExternal = App.externalStoragePath;

    final dir = await Directory.systemTemp.createTemp(
      'venera_log_export_test_',
    );
    App.dataPath = dir.path;
    App.externalStoragePath = dir.path;
    App.isInitialized = true;

    Log.info('i1', 'content 1');
    Log.error('e1', 'content 2');
    final exported = await Log.exportToFile();
    expect(exported, isNotNull);
    expect(await exported!.exists(), isTrue);

    final text = await exported.readAsString();
    final builtText = await Log.buildExportText();
    expect(text.contains('Current Session Logs'), isTrue);
    expect(text.contains('Persisted Log File'), isTrue);
    expect(text.contains('i1'), isTrue);
    expect(text.contains('content 2'), isTrue);
    expect(builtText.contains('Current Session Logs'), isTrue);
    expect(builtText.contains('Persisted Log File'), isTrue);
    expect(builtText.contains('i1'), isTrue);
    expect(builtText.contains('content 2'), isTrue);

    await dir.delete(recursive: true);
    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath;
    }
    App.externalStoragePath = oldExternal;
    App.isInitialized = oldInitialized;
  });

  test(
    'buildExportText includes persisted logs when logs.txt exists',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_log_export_persisted_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      final persistedFile = File(Log.logFilePath!);
      await persistedFile.parent.create(recursive: true);
      await persistedFile.writeAsString('persisted-line-1\npersisted-line-2\n');
      Log.info('memory-title', 'memory-content');

      final exportText = await Log.buildExportText();
      expect(exportText.contains('memory-title'), isTrue);
      expect(exportText.contains('persisted-line-1'), isTrue);
      expect(exportText.contains('persisted-line-2'), isTrue);

      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );

  test(
    'LogDiagnostics parses log file entries after memory is cleared',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_persisted_log_parse_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      final persistedFile = File(Log.logFilePath!);
      await persistedFile.parent.create(recursive: true);
      await persistedFile.writeAsString(
        'error Image Loading 2026-04-30 01:47:32.082278 \n'
        'Bad state: Cannot load relative thumbnail URL without a valid absolute source URL.\n\n'
        'info Reader 2026-04-30 01:48:00.000000 \n'
        'pageList.load.start\n\n',
      );

      Log.clear();
      final logs = await LogDiagnostics.persistedLogs();

      expect(logs.length, 2);
      expect(logs.first.level, LogLevel.error);
      expect(logs.first.title, 'Image Loading');
      expect(logs.first.source, 'persisted');
      expect(logs.first.content.contains('relative thumbnail URL'), isTrue);

      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );

  test('buildExportText handles uninitialized app state', () async {
    final oldInitialized = App.isInitialized;
    final oldDataPath = oldInitialized ? App.dataPath : null;
    final oldExternal = App.externalStoragePath;

    App.isInitialized = false;
    final exportText = await Log.buildExportText();
    expect(exportText.contains('Current Session Logs'), isTrue);
    expect(exportText.contains('Persisted Log File'), isTrue);
    expect(exportText.contains('app not initialized'), isTrue);

    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath;
    }
    App.externalStoragePath = oldExternal;
    App.isInitialized = oldInitialized;
  });

  test(
    'diagnosticSnapshot groups projected legacy duplicates across sources',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_grouped_diagnostics_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      const body =
          '[error] ui.error: ui.error.visible errorType=LoadError {"routeHash":123,"sanitizedMessage":"LOCAL_COMIC_MISSING","exceptionType":"LoadError","diagnosticCode":"LOCAL_COMIC_MISSING","pageOwner":"ComicPage"}';
      final persistedFile = File(Log.logFilePath!);
      await persistedFile.parent.create(recursive: true);
      await persistedFile.writeAsString(
        'error ui.error 2026-05-04 12:34:56.123456 \n$body\n\n',
      );
      Log.projectedError('ui.error', body);

      final snapshot = await LogDiagnostics.diagnosticSnapshot(
        level: 'error',
        limit: 20,
      );
      expect(snapshot.groupedIssues.length, 1);
      final issue = snapshot.groupedIssues.first;
      expect(issue['occurrenceCount'] as int, greaterThanOrEqualTo(2));
      final sources = (issue['sources'] as Map).cast<String, dynamic>();
      expect(
        (sources['session'] as Map)['count'] as int,
        greaterThanOrEqualTo(1),
      );
      expect(
        (sources['persisted'] as Map)['count'] as int,
        greaterThanOrEqualTo(1),
      );

      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );

  test(
    'diagnosticSnapshot fallback groups unparseable legacy by title/content',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_grouped_diagnostics_fallback_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;
      Log.clear();

      final persistedFile = File(Log.logFilePath!);
      await persistedFile.parent.create(recursive: true);
      await persistedFile.writeAsString(
        'error ui.error 2026-05-04 12:34:56.123456 \nnot parseable payload\n\n'
        'error ui.error 2026-05-04 12:34:57.123456 \nnot parseable payload\n\n',
      );

      final snapshot = await LogDiagnostics.diagnosticSnapshot(
        level: 'error',
        limit: 20,
      );
      expect(snapshot.groupedIssues.length, 1);
      expect(snapshot.groupedIssues.first['occurrenceCount'], 2);

      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );

  test('closeFileSink is safe on repeated calls', () async {
    final oldInitialized = App.isInitialized;
    final oldDataPath = oldInitialized ? App.dataPath : null;
    final oldExternal = App.externalStoragePath;

    final dir = await Directory.systemTemp.createTemp(
      'venera_log_close_sink_test_',
    );
    App.dataPath = dir.path;
    App.externalStoragePath = dir.path;
    App.isInitialized = true;

    Log.info('sink', 'first');
    await Log.closeFileSink();
    await Log.closeFileSink();

    final path = Log.logFilePath;
    expect(path, isNotNull);
    final persistedFile = File(path!);
    expect(await persistedFile.exists(), isTrue);

    await dir.delete(recursive: true);
    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath;
    }
    App.externalStoragePath = oldExternal;
    App.isInitialized = oldInitialized;
  });

  test(
    'buildDiagnosticsExportText includes structured diagnostics even when legacy log is empty',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_diagnostics_export_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      Log.clear();
      AppDiagnostics.error(
        'ui.error',
        StateError('failed'),
        message: 'ui.error.visible',
      );

      final exportText = await buildDiagnosticsExportText();
      expect(
        exportText.contains('=== Structured Diagnostics (NDJSON) ==='),
        isTrue,
      );
      expect(exportText.contains('"channel":"ui.error"'), isTrue);
      expect(exportText.contains('=== Current Session Logs ==='), isTrue);

      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );

  test('persistedLevel filters structured file writes independently', () async {
    final oldInitialized = App.isInitialized;
    final oldDataPath = oldInitialized ? App.dataPath : null;
    final oldExternal = App.externalStoragePath;

    final dir = await Directory.systemTemp.createTemp(
      'venera_persisted_level_filter_test_',
    );
    App.dataPath = dir.path;
    App.externalStoragePath = dir.path;
    App.isInitialized = true;

    AppDiagnostics.resetForTesting();
    AppDiagnostics.setRuntimeLevel(DiagnosticLevel.trace);
    AppDiagnostics.setPersistedLevel(DiagnosticLevel.warn);

    AppDiagnostics.info('storage.filter', 'info-not-persisted');
    AppDiagnostics.warn('storage.filter', 'warn-persisted');
    AppDiagnostics.error(
      'storage.filter',
      StateError('error-persisted'),
      message: 'error-persisted',
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await Log.closeFileSink();
    AppDiagnostics.resetForTesting();

    final structuredFile = File('${App.dataPath}/logs/diagnostics.ndjson');
    expect(await structuredFile.exists(), isTrue);
    final text = await structuredFile.readAsString();
    expect(text.contains('info-not-persisted'), isFalse);
    expect(text.contains('warn-persisted'), isTrue);
    expect(text.contains('error-persisted'), isTrue);

    await dir.delete(recursive: true);
    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath;
    }
    App.externalStoragePath = oldExternal;
    App.isInitialized = oldInitialized;
  });

  test(
    'buildDiagnosticsExportText includes manifest and structured archives',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_diagnostics_manifest_archive_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      final logsDir = Directory('${App.dataPath}/logs');
      await logsDir.create(recursive: true);
      await File(
        '${logsDir.path}/diagnostics.ndjson',
      ).writeAsString('{"level":"error","message":"current"}\n');
      final archivedBytes = gzip.encode(
        utf8.encode('{"level":"warn","message":"archived"}\n'),
      );
      await File(
        '${logsDir.path}/diagnostics.ndjson.1.gz',
      ).writeAsBytes(archivedBytes);

      final exportText = await buildDiagnosticsExportText();
      expect(
        exportText.contains('=== Diagnostics Export Manifest (JSON) ==='),
        isTrue,
      );
      expect(exportText.contains('"includedArchives":1'), isTrue);
      expect(exportText.contains('--- diagnostics.ndjson ---'), isTrue);
      expect(exportText.contains('--- diagnostics.ndjson.1.gz ---'), isTrue);
      expect(exportText.contains('"message":"current"'), isTrue);
      expect(exportText.contains('"message":"archived"'), isTrue);

      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );
}
