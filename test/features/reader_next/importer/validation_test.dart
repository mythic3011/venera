import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/legacy_import_validation.dart';

void main() {
  group('LegacyImportValidationService', () {
    late Directory tempDir;
    late String legacyDbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'reader_next_import_validation_',
      );
      legacyDbPath = p.join(tempDir.path, 'legacy.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('accepts valid history/comics rows', () async {
      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute(
        'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h1', 1, 1000, 0, 1);",
      );
      db.execute('CREATE TABLE comics (id TEXT, title TEXT, comic_type INTEGER);');
      db.execute(
        "INSERT INTO comics (id, title, comic_type) VALUES ('c1', 'Title', 1);",
      );
      db.dispose();

      final report = await const LegacyImportValidationService().validate(
        legacyDbPath: legacyDbPath,
      );

      expect(report.totalRowsScanned, 2);
      expect(report.rowsAccepted, 2);
      expect(report.rowsSkipped, 0);
      expect(report.diagnostics, isEmpty);
      expect(report.skippedByCode, isEmpty);
    });

    test('skips malformed rows with diagnostic codes', () async {
      final db = sqlite.sqlite3.open(legacyDbPath);
      db.execute(
        'CREATE TABLE history (id TEXT, type INTEGER, time INTEGER, ep INTEGER, page INTEGER);',
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('', 1, 1000, 0, 1);",
      );
      db.execute(
        "INSERT INTO history (id, type, time, ep, page) VALUES ('h2', 1, -1, 0, 1);",
      );
      db.execute('CREATE TABLE comics (id TEXT, title TEXT, comic_type INTEGER);');
      db.execute(
        "INSERT INTO comics (id, title, comic_type) VALUES ('c1', '', 1);",
      );
      db.execute(
        "INSERT INTO comics (id, title, comic_type) VALUES ('c2', 'ok', 'x');",
      );
      db.dispose();

      final report = await const LegacyImportValidationService().validate(
        legacyDbPath: legacyDbPath,
      );

      expect(report.totalRowsScanned, 4);
      expect(report.rowsAccepted, 0);
      expect(report.rowsSkipped, 4);
      expect(report.diagnostics, hasLength(4));
      expect(report.skippedByCode['LEGACY_HISTORY_MISSING_ID'], 1);
      expect(report.skippedByCode['LEGACY_HISTORY_INVALID_TIME'], 1);
      expect(report.skippedByCode['LEGACY_COMICS_MISSING_TITLE'], 1);
      expect(report.skippedByCode['LEGACY_COMICS_INVALID_TYPE'], 1);
    });
  });
}
