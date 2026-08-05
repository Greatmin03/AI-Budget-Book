import 'dart:async';

// sqflite 도 `Transaction`(DB 트랜잭션)을 export 하므로 도메인 엔티티와 충돌한다.
// 이 파일에서 필요한 것은 도메인 `Transaction` 뿐이고, DB 트랜잭션 콜백은
// 상위 타입인 `DatabaseExecutor` 로 받으므로 sqflite 쪽 이름만 숨긴다.
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../../transactions/data/models/transaction_dto.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/recurring_rule.dart';
import '../../domain/repositories/recurring_repository.dart';
import '../../domain/services/recurring_detector.dart';

class RecurringRepositoryImpl implements RecurringRepository {
  RecurringRepositoryImpl(
    this._db, {
    RecurringDetector detector = const RecurringDetector(),
  }) : _detector = detector;

  final Database _db;
  final RecurringDetector _detector;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const String _table = DbSchema.tableRecurringRules;

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<List<RecurringRule>> findActive() async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.rrIsActive} = 1',
      // 예정일이 없는 규칙은 뒤로 보낸다.
      orderBy: '${DbSchema.rrNextExpectedAt} IS NULL, '
          '${DbSchema.rrNextExpectedAt} ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<RecurringRule>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      orderBy: '${DbSchema.rrIsActive} DESC, ${DbSchema.rrBrand} ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<RecurringRule?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.rrId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<RecurringRule?> findActiveByBrand(String brand) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.rrBrand} = ? AND ${DbSchema.rrIsActive} = 1',
      whereArgs: <Object?>[brand],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<RecurringRule> save(RecurringRule rule) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, Object?> values = <String, Object?>{
      DbSchema.rrBrand: rule.brand,
      DbSchema.rrCategory: rule.category,
      DbSchema.rrSubcategory: rule.subcategory,
      DbSchema.rrCycle: rule.cycle.code,
      DbSchema.rrExpectedAmount: rule.expectedAmount,
      DbSchema.rrLastPaidAt: rule.lastPaidAt?.millisecondsSinceEpoch,
      DbSchema.rrNextExpectedAt: rule.nextExpectedAt?.millisecondsSinceEpoch,
      DbSchema.rrIsActive: rule.isActive ? 1 : 0,
      DbSchema.rrSource: rule.source.code,
      DbSchema.rrUpdatedAt: now,
    };

    final int? id = rule.id;
    if (id == null) {
      values[DbSchema.rrCreatedAt] = now;
      final int newId = await _db.insert(_table, values);
      AppLogger.i('정기결제 규칙 등록: ${rule.brand} ${rule.cycle.label} '
          '${rule.expectedAmount}원');
      _notify();
      return rule.copyWith(id: newId);
    }

    await _db.update(
      _table,
      values,
      where: '${DbSchema.rrId} = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
    return rule;
  }

  @override
  Future<void> setActive(int id, bool isActive) async {
    await _db.update(
      _table,
      <String, Object?>{
        DbSchema.rrIsActive: isActive ? 1 : 0,
        DbSchema.rrUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '${DbSchema.rrId} = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
  }

  @override
  Future<void> delete(int id) async {
    await _db.transaction((DatabaseExecutor txn) async {
      // 거래의 연결만 끊는다. 거래 자체는 절대 지우지 않는다.
      await txn.update(
        DbSchema.tableTransactions,
        <String, Object?>{DbSchema.tRecurringRuleId: null},
        where: '${DbSchema.tRecurringRuleId} = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        _table,
        where: '${DbSchema.rrId} = ?',
        whereArgs: <Object?>[id],
      );
    });
    AppLogger.i('정기결제 규칙 삭제: $id (거래는 유지)');
    _notify();
  }

  @override
  Future<void> registerPayment({
    required int ruleId,
    required DateTime paidAt,
    required int amount,
  }) async {
    final RecurringRule? rule = await findById(ruleId);
    if (rule == null) return;

    await _db.update(
      _table,
      <String, Object?>{
        DbSchema.rrLastPaidAt: paidAt.millisecondsSinceEpoch,
        DbSchema.rrNextExpectedAt:
            rule.cycle.nextAfter(paidAt).millisecondsSinceEpoch,
        DbSchema.rrUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '${DbSchema.rrId} = ?',
      whereArgs: <Object?>[ruleId],
    );
    _notify();
  }

  @override
  Future<List<RecurringCandidate>> detectCandidates({
    int lookbackMonths = 12,
  }) async {
    final DateTime now = DateTime.now();
    final DateRange range = DateRange.custom(
      DateTime(now.year, now.month - lookbackMonths, 1),
      now,
    );

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.*, ${DbSchema.settledSumExpr} AS '
      '${TransactionDto.settledAmountColumn} '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tPaymentDatetime} >= ? '
      '  AND t.${DbSchema.tPaymentDatetime} < ? '
      // 수입은 정기결제 후보가 아니다. 감지기에서도 한 번 더 막지만,
      // 애초에 읽지 않는 편이 싸고 명확하다.
      '  AND ${DbSchema.expenseOnly} '
      'ORDER BY t.${DbSchema.tPaymentDatetime} ASC',
      <Object?>[range.startMillis, range.endExclusiveMillis],
    );

    final List<Transaction> transactions =
        rows.map(TransactionDto.fromRow).toList();

    // 이미 규칙이 있는 브랜드는 다시 묻지 않는다.
    final List<RecurringRule> existing = await findAll();
    final Set<String> existingBrands =
        existing.map((RecurringRule r) => r.brand).toSet();

    return _detector.detect(transactions, existingBrands: existingBrands);
  }

  @override
  Future<int> backfillTransactions(RecurringRule rule) async {
    final int? id = rule.id;
    if (id == null) return 0;

    // 금액이 예상치와 비슷한 과거 거래만 연결한다.
    final int tolerance =
        (rule.expectedAmount.abs() * RecurringRule.amountTolerance).round();

    final int updated = await _db.rawUpdate(
      'UPDATE ${DbSchema.tableTransactions} SET '
      '${DbSchema.tRecurringRuleId} = ?, '
      '${DbSchema.tUpdatedAt} = ? '
      'WHERE ${DbSchema.tBrand} = ? '
      '  AND ${DbSchema.tRecurringRuleId} IS NULL '
      '  AND ${DbSchema.tIsCancelled} = 0 '
      // 수입을 정기"결제" 규칙에 묶으면 안 된다. 수입도 양수로 저장되므로
      // 금액 조건만으로는 걸러지지 않는다.
      "  AND ${DbSchema.tDirection} = 'expense' "
      '  AND ABS(ABS(${DbSchema.tAmount}) - ?) <= ?',
      <Object?>[
        id,
        DateTime.now().millisecondsSinceEpoch,
        rule.brand,
        rule.expectedAmount.abs(),
        tolerance,
      ],
    );

    if (updated > 0) {
      AppLogger.i('정기결제 소급 연결: ${rule.brand} $updated건');
    }
    return updated;
  }

  @override
  Future<List<Transaction>> transactionsOf(int ruleId, {int limit = 50}) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.*, ${DbSchema.settledSumExpr} AS '
      '${TransactionDto.settledAmountColumn} '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tRecurringRuleId} = ? '
      'ORDER BY t.${DbSchema.tPaymentDatetime} DESC '
      'LIMIT ?',
      <Object?>[ruleId, limit],
    );
    return rows.map(TransactionDto.fromRow).toList();
  }

  static RecurringRule _fromRow(Map<String, Object?> row) {
    return RecurringRule(
      id: row[DbSchema.rrId] as int?,
      brand: (row[DbSchema.rrBrand] as String?) ?? '',
      category: (row[DbSchema.rrCategory] as String?) ?? '기타',
      subcategory: (row[DbSchema.rrSubcategory] as String?) ?? '기타',
      cycle: RecurringCycle.fromCode(row[DbSchema.rrCycle] as String?),
      expectedAmount: (row[DbSchema.rrExpectedAmount] as int?) ?? 0,
      lastPaidAt: _toDate(row[DbSchema.rrLastPaidAt]),
      nextExpectedAt: _toDate(row[DbSchema.rrNextExpectedAt]),
      isActive: ((row[DbSchema.rrIsActive] as int?) ?? 1) == 1,
      source: RecurringSource.fromCode(row[DbSchema.rrSource] as String?),
      createdAt: _toDate(row[DbSchema.rrCreatedAt]),
      updatedAt: _toDate(row[DbSchema.rrUpdatedAt]),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  void dispose() => _changes.close();
}
