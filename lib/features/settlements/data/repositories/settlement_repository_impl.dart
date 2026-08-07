import 'dart:async';

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/deposit.dart';
import '../../domain/entities/settlement.dart';
import '../../domain/repositories/settlement_repository.dart';
import '../datasources/settlement_local_datasource.dart';

class SettlementRepositoryImpl implements SettlementRepository {
  SettlementRepositoryImpl(this._local);

  final SettlementLocalDataSource _local;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<List<Settlement>> findByTransaction(int transactionId) async {
    final List<Map<String, Object?>> rows =
        await _local.findByTransaction(transactionId);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Map<int, List<Settlement>>> findByTransactions(
    List<int> transactionIds,
  ) async {
    final List<Map<String, Object?>> rows =
        await _local.findByTransactions(transactionIds);

    final Map<int, List<Settlement>> grouped = <int, List<Settlement>>{};
    for (final Map<String, Object?> row in rows) {
      final Settlement settlement = _fromRow(row);
      grouped
          .putIfAbsent(settlement.transactionId, () => <Settlement>[])
          .add(settlement);
    }
    return grouped;
  }

  @override
  Future<Settlement> add(Settlement settlement) async {
    final int id = await _local.insert(<String, Object?>{
      DbSchema.stTransactionId: settlement.transactionId,
      DbSchema.stCounterparty: settlement.counterparty,
      DbSchema.stAmount: settlement.amount,
      DbSchema.stSettledAt: settlement.settledAt.millisecondsSinceEpoch,
      DbSchema.stDepositId: settlement.depositId,
      DbSchema.stMemo: settlement.memo,
      DbSchema.stCreatedAt: DateTime.now().millisecondsSinceEpoch,
    });

    AppLogger.i('정산 추가: ${settlement.counterparty} '
        '+${settlement.amount}원 (거래 ${settlement.transactionId})');
    _notify();
    return settlement.copyWith(id: id);
  }

  @override
  Future<void> remove(int settlementId) async {
    await _local.delete(settlementId);
    AppLogger.i('정산 삭제: $settlementId');
    _notify();
  }

  @override
  Future<List<Settlement>> findByDeposit(int depositId) async {
    final List<Map<String, Object?>> rows =
        await _local.findByDeposit(depositId);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> removeByDeposit(int depositId) async {
    final int removed = await _local.deleteByDeposit(depositId);
    if (removed > 0) {
      AppLogger.i('입금 $depositId 로 만들어진 정산 $removed건 삭제');
      _notify();
    }
    return removed;
  }

  @override
  Future<int> totalSettledInRange(int fromMillis, int toExclusiveMillis) {
    return _local.totalInRange(fromMillis, toExclusiveMillis);
  }

  static Settlement _fromRow(Map<String, Object?> row) {
    return Settlement(
      id: row[DbSchema.stId] as int?,
      transactionId: (row[DbSchema.stTransactionId] as int?) ?? 0,
      counterparty: (row[DbSchema.stCounterparty] as String?) ?? '',
      amount: (row[DbSchema.stAmount] as int?) ?? 0,
      settledAt: DateTime.fromMillisecondsSinceEpoch(
        (row[DbSchema.stSettledAt] as int?) ?? 0,
      ),
      depositId: row[DbSchema.stDepositId] as int?,
      memo: row[DbSchema.stMemo] as String?,
      createdAt: row[DbSchema.stCreatedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row[DbSchema.stCreatedAt]! as int,
            ),
    );
  }

  void dispose() => _changes.close();
}

class DepositRepositoryImpl implements DepositRepository {
  DepositRepositoryImpl(this._local);

  final DepositLocalDataSource _local;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<Deposit?> insert(Deposit deposit) async {
    final int id = await _local.insert(<String, Object?>{
      DbSchema.dpCounterparty: deposit.counterparty,
      DbSchema.dpAmount: deposit.amount,
      DbSchema.dpDepositedAt: deposit.depositedAt.millisecondsSinceEpoch,
      DbSchema.dpRawNotification: deposit.rawNotification,
      DbSchema.dpSourcePackage: deposit.sourcePackage,
      DbSchema.dpBankName: deposit.bankName,
      DbSchema.dpStatus: deposit.status.name,
      DbSchema.dpFingerprint: deposit.fingerprint,
      DbSchema.dpTransactionId: deposit.transactionId,
      DbSchema.dpCreatedAt: DateTime.now().millisecondsSinceEpoch,
    });

    if (id == 0) {
      AppLogger.d('중복 입금 알림 무시: ${deposit.fingerprint}');
      return null;
    }

    AppLogger.i('입금 기록: ${deposit.counterparty} +${deposit.amount}원 '
        '(정산 후보)');
    _notify();
    return deposit.copyWith(id: id);
  }

  @override
  Future<List<Deposit>> findPending({int limit = 50}) async {
    final List<Map<String, Object?>> rows =
        await _local.findByStatus(DepositStatus.pending.name, limit);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<Deposit>> findLinked({int limit = 50}) async {
    final List<Map<String, Object?>> rows =
        await _local.findByStatus(DepositStatus.linked.name, limit);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<Deposit>> findIgnored({int limit = 50}) async {
    final List<Map<String, Object?>> rows =
        await _local.findByStatus(DepositStatus.ignored.name, limit);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> countPending() =>
      _local.countByStatus(DepositStatus.pending.name);

  @override
  Future<Deposit?> findById(int id) async {
    final Map<String, Object?>? row = await _local.findById(id);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> updateStatus(int depositId, DepositStatus status) async {
    await _local.updateStatus(depositId, status.name);
    _notify();
  }

  static Deposit _fromRow(Map<String, Object?> row) {
    return Deposit(
      id: row[DbSchema.dpId] as int?,
      counterparty: (row[DbSchema.dpCounterparty] as String?) ?? '',
      amount: (row[DbSchema.dpAmount] as int?) ?? 0,
      depositedAt: DateTime.fromMillisecondsSinceEpoch(
        (row[DbSchema.dpDepositedAt] as int?) ?? 0,
      ),
      rawNotification: (row[DbSchema.dpRawNotification] as String?) ?? '',
      sourcePackage: row[DbSchema.dpSourcePackage] as String?,
      bankName: row[DbSchema.dpBankName] as String?,
      status: DepositStatus.fromCode(row[DbSchema.dpStatus] as String?),
      fingerprint: (row[DbSchema.dpFingerprint] as String?) ?? '',
      transactionId: row[DbSchema.dpTransactionId] as int?,
      createdAt: row[DbSchema.dpCreatedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row[DbSchema.dpCreatedAt]! as int,
            ),
    );
  }

  void dispose() => _changes.close();
}
