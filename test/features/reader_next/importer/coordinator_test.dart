import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/importer_coordinator.dart';
import 'package:venera/features/reader_next/importer/legacy_import_execution.dart';
import 'package:venera/features/reader_next/importer/models.dart';

class _CoordinatorSink implements LegacyImportApplySink {
  int historyCount = 0;
  int comicsCount = 0;

  @override
  Future<void> importComicsRow(LegacyComicsImportRow row) async {
    comicsCount += 1;
  }

  @override
  Future<void> importHistoryRow(LegacyHistoryImportRow row) async {
    historyCount += 1;
  }
}

void main() {
  group('LegacyImporterCoordinator', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String runtimeDbPath;
    late String backupDirPath;
    late String checkpointDirPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'reader_next_importer_coordinator_',
      );
      legacyDbPath = p.join(tempDir.path, 'legacy.db');
      runtimeDbPath = p.join(tempDir.path, 'runtime', 'venera.db');
      backupDirPath = p.join(tempDir.path, 'backup');
      checkpointDirPath = p.join(tempDir.path, 'checkpoint');

      final runtimeDbFile = File(runtimeDbPath);
      runtimeDbFile.parent.createSync(recursive: true);
      runtimeDbFile.writeAsBytesSync(<int>[1, 2, 3]);

      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute(
        'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h1', 1, 100, 0, 1);",
      );
      db.execute(
        'CREATE TABLE comics (id TEXT, title TEXT, comic_type INTEGER);',
      );
      db.execute(
        "INSERT INTO comics (id, title, comic_type) VALUES ('c1', 'Title', 1);",
      );
      db.dispose();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('dry-run mode returns report without applying rows', () async {
      final sink = _CoordinatorSink();
      final coordinator = LegacyImporterCoordinator(
        executionService: LegacyImportExecutionService(sink: sink),
      );

      final report = await coordinator.run(
        LegacyImporterRunRequest(
          mode: LegacyImportExecutionMode.dryRun,
          legacyDbPath: legacyDbPath,
          runtimeDbPath: runtimeDbPath,
          backupDirectoryPath: backupDirPath,
          checkpointDirectoryPath: checkpointDirPath,
          now: DateTime.utc(2026, 5, 1, 4),
        ),
      );

      expect(report.mode, LegacyImportExecutionMode.dryRun);
      expect(report.completed, isTrue);
      expect(report.dryRunArtifactPath, isNotNull);
      expect(sink.historyCount, 0);
      expect(sink.comicsCount, 0);
    });

    test('apply mode uses execution service and applies rows', () async {
      final sink = _CoordinatorSink();
      final coordinator = LegacyImporterCoordinator(
        executionService: LegacyImportExecutionService(sink: sink),
      );

      final report = await coordinator.run(
        LegacyImporterRunRequest(
          mode: LegacyImportExecutionMode.apply,
          legacyDbPath: legacyDbPath,
          runtimeDbPath: runtimeDbPath,
          backupDirectoryPath: backupDirPath,
          checkpointDirectoryPath: checkpointDirPath,
        ),
      );

      expect(report.mode, LegacyImportExecutionMode.apply);
      expect(report.completed, isTrue);
      expect(report.appliedHistoryRows, 1);
      expect(report.appliedComicsRows, 1);
      expect(sink.historyCount, 1);
      expect(sink.comicsCount, 1);
    });
  });
}
