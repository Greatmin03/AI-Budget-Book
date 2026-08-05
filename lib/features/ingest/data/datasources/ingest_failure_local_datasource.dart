import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';

class IngestFailureLocalDataSource {
  IngestFailureLocalDataSource(this._db);

  final Database _db;

  Future<void> insert(Map<String, Object?> row) async {
    await _db.insert(DbSchema.tableIngestFailures, row);
  }

  Future<List<Map<String, Object?>>> recent(int limit) {
    return _db.query(
      DbSchema.tableIngestFailures,
      orderBy: '${DbSchema.fCreatedAt} DESC',
      limit: limit,
    );
  }

  Future<int> clear() => _db.delete(DbSchema.tableIngestFailures);
}
