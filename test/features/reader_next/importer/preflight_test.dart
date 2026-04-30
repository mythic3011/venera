import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/legacy_import_preflight.dart';

void main() {
  group('LegacyImportPreflightService', () {
    late Directory tempDir;
    late String runtimeDbPath;
    late String backupDirPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reader_next_importer_');
      runtimeDbPath = p.join(tempDir.path, 'data', 'venera.db');
      backupDirPath = p.join(tempDir.path, 'backup');
      final runtimeDbFile = File(runtimeDbPath);
      runtimeDbFile.parent.createSync(recursive: true);
      runtimeDbFile.writeAsBytesSync(<int>[1, 2, 3, 4]);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates runtime backup even when legacy db is missing', () async {
      final service = LegacyImportPreflightService();
      final report = await service.run(
        legacyDbPath: p.join(tempDir.path, 'missing-legacy.db'),
        runtimeDbPath: runtimeDbPath,
        backupDirectoryPath: backupDirPath,
        now: DateTime.utc(2026, 5, 1, 1, 2, 3),
      );

      expect(report.runtimeBackupCreated, isTrue);
      expect(report.legacyDbExists, isFalse);
      expect(File(report.backupPath).existsSync(), isTrue);
      expect(report.legacySchemaWarnings, contains('legacy_db_missing'));
    });

    test('reports tables and schema warnings for malformed legacy schema', () async {
      final legacyDbPath = p.join(tempDir.path, 'legacy.db');
      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute('CREATE TABLE history (id TEXT, type INTEGER, ep INTEGER);');
      db.execute('CREATE TABLE comics (id TEXT, title TEXT);');
      db.dispose();

      final service = LegacyImportPreflightService();
      final report = await service.run(
        legacyDbPath: legacyDbPath,
        runtimeDbPath: runtimeDbPath,
        backupDirectoryPath: backupDirPath,
      );

      expect(report.legacyDbExists, isTrue);
      expect(report.legacyTables, containsAll(<String>['history', 'comics']));
      expect(report.legacySchemaWarnings, contains('history_missing_column:time'));
      expect(report.legacySchemaWarnings, contains('history_missing_column:page'));
      expect(
        report.legacySchemaWarnings,
        contains('comics_missing_column:comic_type'),
      );
    });
  });
}
