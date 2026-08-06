import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/card_account_link.dart';
import '../../domain/repositories/card_account_link_repository.dart';

/// 카드 이름 -> 계좌 연결.
///
/// 알림으로 수집된 거래를 계좌 잔액에 반영하기 위한 다리다.
/// 거래에는 `account_id` 가 있어야 잔액에 잡히는데, 알림은 카드 이름만 준다.
class CardAccountLinkRepositoryImpl implements CardAccountLinkRepository {
  CardAccountLinkRepositoryImpl(this._db);

  final Database _db;

  static const String _table = DbSchema.tableCardAccountLinks;

  @override
  Future<int?> accountIdFor(String cardName) async {
    final String key = cardName.trim();
    if (key.isEmpty) return null;

    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      columns: <String>[DbSchema.calAccountId],
      where: '${DbSchema.calCardName} = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first[DbSchema.calAccountId] as int?;
  }

  /// 거래에 실제로 등장한 카드 이름 + 연결 상태.
  ///
  /// 고정 목록을 보여 주지 않는다. **사용자가 실제로 쓴 카드만** 나열해야
  /// 고를 것이 명확하다.
  @override
  Future<List<CardAccountLink>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery('''
      SELECT t.${DbSchema.tCardName} AS card_name,
             COUNT(*) AS cnt,
             l.${DbSchema.calAccountId} AS account_id,
             a.${DbSchema.acName} AS account_name
      FROM ${DbSchema.tableTransactions} t
      LEFT JOIN $_table l
        ON l.${DbSchema.calCardName} = t.${DbSchema.tCardName}
      LEFT JOIN ${DbSchema.tableAccounts} a
        ON a.${DbSchema.acId} = l.${DbSchema.calAccountId}
      WHERE t.${DbSchema.tCardName} IS NOT NULL
        AND TRIM(t.${DbSchema.tCardName}) != ''
      GROUP BY t.${DbSchema.tCardName}
      ORDER BY cnt DESC
    ''');

    return rows
        .map(
          (Map<String, Object?> row) => CardAccountLink(
            cardName: (row['card_name'] as String?) ?? '',
            accountId: row['account_id'] as int?,
            accountName: row['account_name'] as String?,
            transactionCount: (row['cnt'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// 연결하고 **과거 거래에도 소급 적용**한다.
  ///
  /// 소급 적용이 없으면 이미 쌓인 거래는 영영 잔액에 반영되지 않는다.
  /// 사용자 입장에서는 "연결했는데 잔액이 그대로" 로 보인다.
  ///
  /// 이미 계좌가 지정된 거래는 건드리지 않는다. 사용자가 개별로 고른 것을
  /// 일괄 작업이 덮으면 안 된다.
  @override
  Future<int> link({
    required String cardName,
    required int accountId,
  }) async {
    final String key = cardName.trim();
    if (key.isEmpty) return 0;

    final int now = DateTime.now().millisecondsSinceEpoch;
    int updated = 0;

    await _db.transaction((DatabaseExecutor txn) async {
      await txn.insert(
        _table,
        <String, Object?>{
          DbSchema.calCardName: key,
          DbSchema.calAccountId: accountId,
          DbSchema.calCreatedAt: now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      updated = await txn.update(
        DbSchema.tableTransactions,
        <String, Object?>{
          DbSchema.tAccountId: accountId,
          DbSchema.tUpdatedAt: now,
        },
        where: '${DbSchema.tCardName} = ? '
            'AND ${DbSchema.tAccountId} IS NULL',
        whereArgs: <Object?>[key],
      );
    });

    AppLogger.i('카드 연결: $key -> 계좌 $accountId (과거 거래 $updated건 반영)');
    return updated;
  }

  /// 연결을 해제하고 소급 적용도 되돌린다.
  ///
  /// 되돌리지 않으면 "연결을 껐는데 잔액은 그대로" 가 된다.
  @override
  Future<int> unlink(String cardName) async {
    final String key = cardName.trim();
    if (key.isEmpty) return 0;

    final int? accountId = await accountIdFor(key);
    if (accountId == null) return 0;

    final int now = DateTime.now().millisecondsSinceEpoch;
    int reverted = 0;

    await _db.transaction((DatabaseExecutor txn) async {
      await txn.delete(
        _table,
        where: '${DbSchema.calCardName} = ?',
        whereArgs: <Object?>[key],
      );

      // 이 연결로 붙었던 거래만 되돌린다.
      reverted = await txn.update(
        DbSchema.tableTransactions,
        <String, Object?>{
          DbSchema.tAccountId: null,
          DbSchema.tUpdatedAt: now,
        },
        where: '${DbSchema.tCardName} = ? AND ${DbSchema.tAccountId} = ?',
        whereArgs: <Object?>[key, accountId],
      );
    });

    AppLogger.i('카드 연결 해제: $key (거래 $reverted건 되돌림)');
    return reverted;
  }
}
