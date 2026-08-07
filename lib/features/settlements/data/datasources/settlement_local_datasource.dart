import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';

class SettlementLocalDataSource {
  SettlementLocalDataSource(this._db);

  final Database _db;

  Future<List<Map<String, Object?>>> findByTransaction(int transactionId) {
    return _db.query(
      DbSchema.tableSettlements,
      where: '${DbSchema.stTransactionId} = ?',
      whereArgs: <Object?>[transactionId],
      orderBy: '${DbSchema.stSettledAt} ASC',
    );
  }

  /// 여러 거래의 정산을 한 번에. (거래별로 쿼리하면 N+1 이 된다)
  Future<List<Map<String, Object?>>> findByTransactions(
    List<int> transactionIds,
  ) {
    if (transactionIds.isEmpty) {
      return Future<List<Map<String, Object?>>>.value(
        const <Map<String, Object?>>[],
      );
    }
    // id 는 정수이므로 직접 넣어도 인젝션 위험이 없다.
    // (문자열이라면 반드시 placeholder 를 써야 한다)
    final String placeholders =
        List<String>.filled(transactionIds.length, '?').join(',');
    return _db.rawQuery(
      'SELECT * FROM ${DbSchema.tableSettlements} '
      'WHERE ${DbSchema.stTransactionId} IN ($placeholders) '
      'ORDER BY ${DbSchema.stSettledAt} ASC',
      transactionIds,
    );
  }

  Future<int> insert(Map<String, Object?> row) {
    return _db.insert(DbSchema.tableSettlements, row);
  }

  Future<List<Map<String, Object?>>> findByDeposit(int depositId) {
    return _db.query(
      DbSchema.tableSettlements,
      where: '${DbSchema.stDepositId} = ?',
      whereArgs: <Object?>[depositId],
      orderBy: '${DbSchema.stSettledAt} ASC',
    );
  }

  Future<int> deleteByDeposit(int depositId) {
    return _db.delete(
      DbSchema.tableSettlements,
      where: '${DbSchema.stDepositId} = ?',
      whereArgs: <Object?>[depositId],
    );
  }

  Future<int> delete(int id) {
    return _db.delete(
      DbSchema.tableSettlements,
      where: '${DbSchema.stId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> totalInRange(int fromMillis, int toExclusiveMillis) async {
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COALESCE(SUM(${DbSchema.stAmount}), 0) '
            'FROM ${DbSchema.tableSettlements} '
            'WHERE ${DbSchema.stSettledAt} >= ? AND ${DbSchema.stSettledAt} < ?',
            <Object?>[fromMillis, toExclusiveMillis],
          ),
        ) ??
        0;
  }
}

class DepositLocalDataSource {
  DepositLocalDataSource(this._db);

  final Database _db;

  /// 중복이면 0 을 반환한다.
  Future<int> insert(Map<String, Object?> row) {
    return _db.insert(
      DbSchema.tableDeposits,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, Object?>>> findByStatus(
    String status,
    int limit,
  ) {
    return _db.query(
      DbSchema.tableDeposits,
      where: '${DbSchema.dpStatus} = ?',
      whereArgs: <Object?>[status],
      orderBy: '${DbSchema.dpDepositedAt} DESC',
      limit: limit,
    );
  }

  Future<int> countByStatus(String status) async {
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM ${DbSchema.tableDeposits} '
            'WHERE ${DbSchema.dpStatus} = ?',
            <Object?>[status],
          ),
        ) ??
        0;
  }

  Future<Map<String, Object?>?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      DbSchema.tableDeposits,
      where: '${DbSchema.dpId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> updateStatus(int id, String status) {
    return _db.update(
      DbSchema.tableDeposits,
      <String, Object?>{DbSchema.dpStatus: status},
      where: '${DbSchema.dpId} = ?',
      whereArgs: <Object?>[id],
    );
  }
}
