import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/asset_transfer.dart';
import '../../domain/repositories/asset_repository.dart';

class AssetRepositoryImpl implements AssetRepository {
  AssetRepositoryImpl(this._db);

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<AssetTransfer> markTransaction({
    required int transactionId,
    required String fromAccount,
    required String toAccount,
    required int amount,
    required DateTime transferredAt,
    String? note,
    AssetKind kind = AssetKind.saving,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;

    // 플래그와 상세를 한 트랜잭션으로 묶는다.
    // 둘 중 하나만 반영되면 통계와 상세가 어긋난다.
    await _db.transaction((DatabaseExecutor txn) async {
      // 기존 기록이 있으면 교체한다(중복 방지).
      await txn.delete(
        DbSchema.tableAssetTransfers,
        where: '${DbSchema.atTransactionId} = ?',
        whereArgs: <Object?>[transactionId],
      );

      await txn.insert(DbSchema.tableAssetTransfers, <String, Object?>{
        DbSchema.atTransactionId: transactionId,
        DbSchema.atFromAccount: fromAccount.trim(),
        DbSchema.atToAccount: toAccount.trim(),
        DbSchema.atAmount: amount,
        DbSchema.atTransferredAt: transferredAt.millisecondsSinceEpoch,
        DbSchema.atNote: note,
        DbSchema.atCreatedAt: now,
      });

      await txn.update(
        DbSchema.tableTransactions,
        <String, Object?>{
          DbSchema.tIsAssetTransfer: 1,
          // 종류는 거래 행에 둔다. 자산 통계가 조인 없이 나눠 집계할 수 있다.
          DbSchema.tAssetKind: kind.code,
          DbSchema.tUpdatedAt: now,
        },
        where: '${DbSchema.tId} = ?',
        whereArgs: <Object?>[transactionId],
      );
    });

    AppLogger.i('자산 이동 표시(${kind.label}): $fromAccount -> $toAccount '
        '$amount원 (거래 $transactionId, 소비 통계 제외)');
    _notify();

    return AssetTransfer(
      transactionId: transactionId,
      fromAccount: fromAccount.trim(),
      toAccount: toAccount.trim(),
      amount: amount,
      transferredAt: transferredAt,
      note: note,
    );
  }

  @override
  Future<void> unmarkTransaction(int transactionId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((DatabaseExecutor txn) async {
      await txn.delete(
        DbSchema.tableAssetTransfers,
        where: '${DbSchema.atTransactionId} = ?',
        whereArgs: <Object?>[transactionId],
      );
      await txn.update(
        DbSchema.tableTransactions,
        <String, Object?>{
          DbSchema.tIsAssetTransfer: 0,
          DbSchema.tAssetKind: null,
          DbSchema.tUpdatedAt: now,
        },
        where: '${DbSchema.tId} = ?',
        whereArgs: <Object?>[transactionId],
      );
    });

    AppLogger.i('자산 이동 해제: 거래 $transactionId (다시 소비로 집계)');
    _notify();
  }

  @override
  Future<AssetTransfer?> findByTransaction(int transactionId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      DbSchema.tableAssetTransfers,
      where: '${DbSchema.atTransactionId} = ?',
      whereArgs: <Object?>[transactionId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<List<AssetTransfer>> findInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.query(
      DbSchema.tableAssetTransfers,
      where: '${DbSchema.atTransferredAt} >= ? '
          'AND ${DbSchema.atTransferredAt} < ?',
      whereArgs: <Object?>[range.startMillis, range.endExclusiveMillis],
      orderBy: '${DbSchema.atTransferredAt} DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<AssetSummary> summary({DateRange? range}) async {
    final String where = range == null
        ? ''
        : 'WHERE ${DbSchema.atTransferredAt} >= ? '
            'AND ${DbSchema.atTransferredAt} < ?';
    final List<Object?> args = range == null
        ? const <Object?>[]
        : <Object?>[range.startMillis, range.endExclusiveMillis];

    // 들어온 곳과 나간 곳을 각각 합산한 뒤 Dart 에서 합친다.
    final List<Map<String, Object?>> inflow = await _db.rawQuery(
      'SELECT ${DbSchema.atToAccount} AS account, '
      'COALESCE(SUM(${DbSchema.atAmount}), 0) AS total, '
      'COUNT(*) AS cnt '
      'FROM ${DbSchema.tableAssetTransfers} $where '
      'GROUP BY ${DbSchema.atToAccount}',
      args,
    );
    final List<Map<String, Object?>> outflow = await _db.rawQuery(
      'SELECT ${DbSchema.atFromAccount} AS account, '
      'COALESCE(SUM(${DbSchema.atAmount}), 0) AS total, '
      'COUNT(*) AS cnt '
      'FROM ${DbSchema.tableAssetTransfers} $where '
      'GROUP BY ${DbSchema.atFromAccount}',
      args,
    );

    final Map<String, int> inflowByAccount = <String, int>{};
    final Map<String, int> outflowByAccount = <String, int>{};
    final Map<String, int> countByAccount = <String, int>{};

    for (final Map<String, Object?> row in inflow) {
      final String account = (row['account'] as String?) ?? '';
      inflowByAccount[account] = _asInt(row['total']);
      countByAccount[account] =
          (countByAccount[account] ?? 0) + _asInt(row['cnt']);
    }
    for (final Map<String, Object?> row in outflow) {
      final String account = (row['account'] as String?) ?? '';
      outflowByAccount[account] = _asInt(row['total']);
      countByAccount[account] =
          (countByAccount[account] ?? 0) + _asInt(row['cnt']);
    }

    final Set<String> accounts = <String>{
      ...inflowByAccount.keys,
      ...outflowByAccount.keys,
    }..removeWhere((String a) => a.isEmpty);

    final List<AccountBalance> balances = accounts
        .map(
          (String account) => AccountBalance(
            account: account,
            inflow: inflowByAccount[account] ?? 0,
            outflow: outflowByAccount[account] ?? 0,
            transferCount: countByAccount[account] ?? 0,
          ),
        )
        .toList()
      ..sort((AccountBalance a, AccountBalance b) => b.net.compareTo(a.net));

    final int total = Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COALESCE(SUM(${DbSchema.atAmount}), 0) '
            'FROM ${DbSchema.tableAssetTransfers} $where',
            args,
          ),
        ) ??
        0;

    return AssetSummary(totalTransferred: total, balances: balances);
  }

  @override
  Future<List<String>> knownAccounts() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT ${DbSchema.atToAccount} AS account '
      'FROM ${DbSchema.tableAssetTransfers} '
      'UNION '
      'SELECT ${DbSchema.atFromAccount} AS account '
      'FROM ${DbSchema.tableAssetTransfers} '
      'ORDER BY account ASC',
    );
    return rows
        .map((Map<String, Object?> row) => (row['account'] as String?) ?? '')
        .where((String a) => a.isNotEmpty)
        .toList();
  }

  static AssetTransfer _fromRow(Map<String, Object?> row) {
    return AssetTransfer(
      id: row[DbSchema.atId] as int?,
      transactionId: row[DbSchema.atTransactionId] as int?,
      fromAccount: (row[DbSchema.atFromAccount] as String?) ?? '',
      toAccount: (row[DbSchema.atToAccount] as String?) ?? '',
      amount: (row[DbSchema.atAmount] as int?) ?? 0,
      transferredAt: DateTime.fromMillisecondsSinceEpoch(
        (row[DbSchema.atTransferredAt] as int?) ?? 0,
      ),
      note: row[DbSchema.atNote] as String?,
      createdAt: row[DbSchema.atCreatedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row[DbSchema.atCreatedAt]! as int,
            ),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  void dispose() => _changes.close();
}
