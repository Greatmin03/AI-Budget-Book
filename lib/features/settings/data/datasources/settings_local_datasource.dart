import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';

/// `settings` 테이블(key-value) 접근.
class SettingsLocalDataSource {
  SettingsLocalDataSource(this._db);

  final Database _db;

  Future<Map<String, String>> readAll() async {
    final List<Map<String, Object?>> rows =
        await _db.query(DbSchema.tableSettings);
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        (row[DbSchema.sKey] as String? ?? ''):
            (row[DbSchema.sValue] as String? ?? ''),
    };
  }

  Future<void> writeAll(Map<String, String> values) async {
    final Batch batch = _db.batch();
    values.forEach((String key, String value) {
      batch.insert(
        DbSchema.tableSettings,
        <String, Object?>{DbSchema.sKey: key, DbSchema.sValue: value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}
