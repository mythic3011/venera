part of '../unified_comics_store.dart';

extension _UnifiedComicsStoreMigrations on UnifiedComicsStore {
  Future<void> _createLatestSchema() async {
    await _ensureVersion1Baseline();
    await _ensureV2Schema();
    await _ensureV3Schema();
  }

  Future<void> _upgradeToV2() async {
    await _ensureVersion1Baseline();
    await _ensureV2Schema();
  }

  Future<void> _upgradeToV3() async {
    await _ensureV3Schema();
  }

  Future<void> _ensureTextColumn(String tableName, String columnName) async {
    final columns = await listColumns(tableName);
    if (columns.contains(columnName)) {
      return;
    }
    await customStatement(
      'ALTER TABLE $tableName ADD COLUMN $columnName TEXT;',
    );
  }
}
