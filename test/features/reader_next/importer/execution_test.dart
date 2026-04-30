import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/legacy_import_execution.dart';
import 'package:venera/features/reader_next/importer/models.dart';

class _RecordingSink implements LegacyImportApplySink {
  final List<LegacyHistoryImportRow> historyRows = <LegacyHistoryImportRow>[];
  final List<LegacyComicsImportRow> comicsRows = <LegacyComicsImportRow>[];
  bool failOnFirstHistory = false;

  @override
  Future<void> importHistoryRow(LegacyHistoryImportRow row) async {
    if (failOnFirstHistory && historyRows.isEmpty) {
      throw StateError('history import failed');
    }
    historyRows.add(row);
  }

  @override
  Future<void> importComicsRow(LegacyComicsImportRow row) async {
    comicsRows.add(row);
  }
}

class _PassthroughTransactionRunner implements LegacyImportTransactionRunner {
  const _PassthroughTransactionRunner();

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();
}

void main() {
  group('LegacyImportExecutionService', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String runtimeDbPath;
    late String backupDirPath;
    late String checkpointDirPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'reader_next_import_execution_',
      );
      legacyDbPath = p.join(tempDir.path, 'legacy.db');
      runtimeDbPath = p.join(tempDir.path, 'runtime', 'venera.db');
      backupDirPath = p.join(tempDir.path, 'backup');
      checkpointDirPath = p.join(tempDir.path, 'checkpoint');

      final runtimeDbFile = File(runtimeDbPath);
      runtimeDbFile.parent.createSync(recursive: true);
      runtimeDbFile.writeAsBytesSync(<int>[0, 1, 2, 3]);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('dry-run writes artifact and does not call sink', () async {
      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute(
        'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h1', 1, 1, 0, 1);",
      );
      db.dispose();

      final sink = _RecordingSink();
      final service = LegacyImportExecutionService(
        sink: sink,
        transactionRunner: const _PassthroughTransactionRunner(),
      );
      final report = await service.run(
        mode: LegacyImportExecutionMode.dryRun,
        legacyDbPath: legacyDbPath,
        runtimeDbPath: runtimeDbPath,
        backupDirectoryPath: backupDirPath,
        checkpointDirectoryPath: checkpointDirPath,
        now: DateTime.utc(2026, 5, 1, 2, 0, 0),
      );

      expect(report.completed, isTrue);
      expect(report.appliedHistoryRows, 0);
      expect(report.appliedComicsRows, 0);
      expect(sink.historyRows, isEmpty);
      expect(sink.comicsRows, isEmpty);
      expect(report.dryRunArtifactPath, isNotNull);
      final artifactFile = File(report.dryRunArtifactPath!);
      expect(artifactFile.existsSync(), isTrue);
      final payload = jsonDecode(artifactFile.readAsStringSync());
      expect(payload['mode'], 'dry_run');
      expect(payload['validation']['rowsAccepted'], 1);
    });

    test(
      'apply imports valid rows, skips malformed rows, and saves checkpoint',
      () async {
        final db = sqlite.sqlite3.open(legacyDbPath);
        db.execute(
          'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
        );
        db.execute(
          "INSERT INTO history (id, type, time, ep, page) VALUES ('h1', 1, 10, 0, 1);",
        );
        db.execute(
          "INSERT INTO history (id, type, time, ep, page) VALUES ('', 1, 10, 0, 1);",
        );
        db.execute(
          'CREATE TABLE comics (id TEXT, title TEXT, comic_type INTEGER);',
        );
        db.execute(
          "INSERT INTO comics (id, title, comic_type) VALUES ('c1', 'Title 1', 1);",
        );
        db.execute(
          "INSERT INTO comics (id, title, comic_type) VALUES ('c2', '', 1);",
        );
        db.dispose();

        final sink = _RecordingSink();
        final service = LegacyImportExecutionService(sink: sink);
        final report = await service.run(
          mode: LegacyImportExecutionMode.apply,
          legacyDbPath: legacyDbPath,
          runtimeDbPath: runtimeDbPath,
          backupDirectoryPath: backupDirPath,
          checkpointDirectoryPath: checkpointDirPath,
        );

        expect(report.completed, isTrue);
        expect(report.appliedHistoryRows, 1);
        expect(report.appliedComicsRows, 1);
        expect(sink.historyRows, hasLength(1));
        expect(sink.comicsRows, hasLength(1));
        expect(report.checkpoint.historyRowId, 2);
        expect(report.checkpoint.comicsRowId, 2);
        final checkpointFile = File(report.checkpointPath!);
        expect(checkpointFile.existsSync(), isTrue);
        final checkpointJson =
            jsonDecode(checkpointFile.readAsStringSync())
                as Map<String, dynamic>;
        expect(checkpointJson['historyRowId'], 2);
        expect(checkpointJson['comicsRowId'], 2);
      },
    );

    test('resume from checkpoint processes only remaining rows', () async {
      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute(
        'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h1', 1, 10, 0, 1);",
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h2', 1, 11, 0, 2);",
      );
      db.execute(
        'CREATE TABLE comics (id TEXT, title TEXT, comic_type INTEGER);',
      );
      db.execute(
        "INSERT INTO comics (id, title, comic_type) VALUES ('c1', 'Title 1', 1);",
      );
      db.execute(
        "INSERT INTO comics (id, title, comic_type) VALUES ('c2', 'Title 2', 1);",
      );
      db.dispose();

      final checkpointFile = File(
        p.join(checkpointDirPath, 'legacy-import-checkpoint.json'),
      );
      checkpointFile.parent.createSync(recursive: true);
      checkpointFile.writeAsStringSync(
        jsonEncode(<String, dynamic>{'historyRowId': 1, 'comicsRowId': 1}),
      );

      final sink = _RecordingSink();
      final service = LegacyImportExecutionService(sink: sink);
      final report = await service.run(
        mode: LegacyImportExecutionMode.apply,
        legacyDbPath: legacyDbPath,
        runtimeDbPath: runtimeDbPath,
        backupDirectoryPath: backupDirPath,
        checkpointDirectoryPath: checkpointDirPath,
      );

      expect(report.completed, isTrue);
      expect(report.appliedHistoryRows, 1);
      expect(report.appliedComicsRows, 1);
      expect(sink.historyRows.single.id, 'h2');
      expect(sink.comicsRows.single.id, 'c2');
      expect(report.checkpoint.historyRowId, 2);
      expect(report.checkpoint.comicsRowId, 2);
    });

    test('reports apply failure as non-completed with failure code', () async {
      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute(
        'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h1', 1, 1, 0, 1);",
      );
      db.dispose();

      final sink = _RecordingSink()..failOnFirstHistory = true;
      final service = LegacyImportExecutionService(
        sink: sink,
        transactionRunner: const _PassthroughTransactionRunner(),
      );
      final report = await service.run(
        mode: LegacyImportExecutionMode.apply,
        legacyDbPath: legacyDbPath,
        runtimeDbPath: runtimeDbPath,
        backupDirectoryPath: backupDirPath,
        checkpointDirectoryPath: checkpointDirPath,
      );

      expect(report.completed, isFalse);
      expect(report.failureCode, 'LEGACY_IMPORT_APPLY_FAILED');
      expect(report.failureMessage, contains('history import failed'));
    });
  });
}
