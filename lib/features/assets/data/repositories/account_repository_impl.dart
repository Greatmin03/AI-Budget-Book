import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/account_repository.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._db);

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const String _table = DbSchema.tableAccounts;

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<AssetOverview> overview() async {
    final List<Account> accounts = await findAll();
    if (accounts.isEmpty) return const AssetOverview.empty();

    // 종류별로 묶고 표시 순서대로 정렬한다.
    final List<AccountGroup> groups = <AccountGroup>[];
    for (final AccountType type in AccountType.displayOrder) {
      final List<Account> inType =
          accounts.where((Account a) => a.type == type).toList();
      if (inType.isEmpty) continue;
      groups.add(AccountGroup(type: type, accounts: inType));
    }

    // 현재 잔액(기준 + 거래) 을 합산한다.
    final int total = accounts.fold<int>(
      0,
      (int sum, Account a) => sum + a.currentBalance,
    );

    final _SnapshotTotal? previous = await _previousSnapshotTotal();

    final DateTime now = DateTime.now();

    return AssetOverview(
      groups: groups,
      totalAssets: total,
      previousTotal: previous?.total ?? 0,
      lastRecordedAt: previous?.recordedAt,
      todayChange: await balanceChangeInRange(DateRange.today(now)),
      weekChange: await balanceChangeInRange(DateRange.week(now)),
      monthChange: await balanceChangeInRange(DateRange.month(now)),
    );
  }

  /// 비교 대상 스냅샷: **이번 달 시작 이전**의 가장 최근 기록.
  ///
  /// 같은 달 안에서 잔액을 여러 번 고쳐도 "지난달 대비" 가 흔들리지 않게 한다.
  Future<_SnapshotTotal?> _previousSnapshotTotal() async {
    final DateTime now = DateTime.now();
    final int monthStart = DateTime(now.year, now.month).millisecondsSinceEpoch;

    final List<Map<String, Object?>> latest = await _db.rawQuery(
      'SELECT MAX(${DbSchema.asRecordedAt}) AS at '
      'FROM ${DbSchema.tableAccountSnapshots} '
      'WHERE ${DbSchema.asRecordedAt} < ?',
      <Object?>[monthStart],
    );
    final int recordedAt = _int(latest.isEmpty ? null : latest.first['at']);
    if (recordedAt == 0) return null;

    // 같은 기록 시점의 잔액만 합산한다(하루 안의 여러 기록이 섞이지 않게
    // 정확히 같은 타임스탬프를 쓴다).
    final List<Map<String, Object?>> sum = await _db.rawQuery(
      'SELECT COALESCE(SUM(${DbSchema.asBalance}), 0) AS total '
      'FROM ${DbSchema.tableAccountSnapshots} '
      'WHERE ${DbSchema.asRecordedAt} = ?',
      <Object?>[recordedAt],
    );

    return _SnapshotTotal(
      total: _int(sum.isEmpty ? null : sum.first['total']),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(recordedAt),
    );
  }

  @override
  Future<List<Account>> findAll({bool includeInactive = false}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: includeInactive ? null : '${DbSchema.acIsActive} = 1',
      orderBy: '${DbSchema.acSortOrder} ASC, ${DbSchema.acId} ASC',
    );

    // 계좌별 거래 합을 한 번에 가져와 붙인다(계좌마다 쿼리하지 않는다).
    final Map<int, int> deltas = await _accountDeltas();

    return rows.map((Map<String, Object?> row) {
      final Account account = _fromRow(row);
      final int? id = account.id;
      return id == null
          ? account
          : account.copyWith(transactionDelta: deltas[id] ?? 0);
    }).toList();
  }

  /// 계좌 id -> 기준 시각 이후의 잔액 변화 전부.
  ///
  /// 두 갈래를 합친다.
  ///  - 거래(`transactions`) — 수입 +, 지출/자산이동 -
  ///  - **들어온 자산 이동**(`asset_transfers.to_account_id`) — +
  ///
  /// 두 번째가 없으면 적금 계좌는 영원히 0원이다. 나간 계좌만 줄고 받는
  /// 계좌는 늘지 않아 총자산이 조용히 감소한다.
  Future<Map<int, int>> _accountDeltas() async {
    final Map<int, int> deltas = await _transactionDeltas();
    final Map<int, int> incoming = await _incomingTransferDeltas();

    for (final MapEntry<int, int> entry in incoming.entries) {
      deltas[entry.key] = (deltas[entry.key] ?? 0) + entry.value;
    }
    return deltas;
  }

  /// 계좌 id -> 기준 시각 이후 **들어온** 자산 이동 합.
  Future<Map<int, int>> _incomingTransferDeltas() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT tr.${DbSchema.atToAccountId} AS account_id, '
      'COALESCE(SUM(tr.${DbSchema.atAmount}), 0) AS delta '
      'FROM ${DbSchema.tableAssetTransfers} tr '
      'JOIN $_table a ON a.${DbSchema.acId} = tr.${DbSchema.atToAccountId} '
      'WHERE tr.${DbSchema.atTransferredAt} >= a.${DbSchema.acBalanceAsOf} '
      'GROUP BY tr.${DbSchema.atToAccountId}',
    );

    return <int, int>{
      for (final Map<String, Object?> row in rows)
        if (row['account_id'] is int)
          row['account_id']! as int: _int(row['delta']),
    };
  }

  /// 계좌 id -> 기준 시각 이후 거래 합(수입 +, 지출/자산 이동 -).
  ///
  /// 기준 시각 비교를 SQL 안에서 하므로, 계좌마다 다른 기준 시각이 그대로
  /// 반영된다. 잔액을 따로 저장하지 않기 때문에 어긋날 수가 없다.
  Future<Map<int, int>> _transactionDeltas() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.${DbSchema.tAccountId} AS account_id, '
      'COALESCE(SUM(${DbSchema.balanceDeltaExpr}), 0) AS delta '
      'FROM ${DbSchema.tableTransactions} t '
      'JOIN $_table a ON a.${DbSchema.acId} = t.${DbSchema.tAccountId} '
      'WHERE t.${DbSchema.tPaymentDatetime} >= a.${DbSchema.acBalanceAsOf} '
      'GROUP BY t.${DbSchema.tAccountId}',
    );

    return <int, int>{
      for (final Map<String, Object?> row in rows)
        if (row['account_id'] is int) row['account_id'] as int: _int(row['delta']),
    };
  }

  @override
  Future<int> balanceChangeInRange(DateRange range, {int? accountId}) async {
    final String accountFilter =
        accountId == null ? '' : ' AND t.${DbSchema.tAccountId} = ?';

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(${DbSchema.balanceDeltaExpr}), 0) AS delta '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tAccountId} IS NOT NULL '
      'AND t.${DbSchema.tPaymentDatetime} >= ? '
      'AND t.${DbSchema.tPaymentDatetime} < ?$accountFilter',
      <Object?>[
        range.startMillis,
        range.endExclusiveMillis,
        if (accountId != null) accountId,
      ],
    );

    // 자산 이동은 나간 계좌에서 빠지므로, 받는 쪽을 더하지 않으면 총자산이
    // 줄어든 것처럼 보인다. 적금에 넣은 돈은 사라진 돈이 아니다.
    return _int(rows.isEmpty ? null : rows.first['delta']) +
        await _incomingTransfersInRange(range, accountId: accountId);
  }

  /// 기간 내 **들어온** 자산 이동 합.
  Future<int> _incomingTransfersInRange(
    DateRange range, {
    int? accountId,
  }) async {
    final String accountFilter =
        accountId == null ? '' : ' AND tr.${DbSchema.atToAccountId} = ?';

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(tr.${DbSchema.atAmount}), 0) AS delta '
      'FROM ${DbSchema.tableAssetTransfers} tr '
      'WHERE tr.${DbSchema.atToAccountId} IS NOT NULL '
      'AND tr.${DbSchema.atTransferredAt} >= ? '
      'AND tr.${DbSchema.atTransferredAt} < ?$accountFilter',
      <Object?>[
        range.startMillis,
        range.endExclusiveMillis,
        if (accountId != null) accountId,
      ],
    );
    return _int(rows.isEmpty ? null : rows.first['delta']);
  }

  @override
  Future<Account?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.acId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    // findAll 과 같은 값을 돌려줘야 한다. 거래 반영분을 빼면 화면마다 잔액이
    // 달라진다.
    final Map<int, int> deltas = await _accountDeltas();
    return _fromRow(rows.first).copyWith(transactionDelta: deltas[id] ?? 0);
  }

  @override
  Future<Account> save(Account account) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, Object?> values = <String, Object?>{
      DbSchema.acName: account.name.trim(),
      DbSchema.acType: account.type.code,
      DbSchema.acBalance: account.balance,
      DbSchema.acIsActive: account.isActive ? 1 : 0,
      DbSchema.acSortOrder: account.sortOrder,
      DbSchema.acUpdatedAt: now,
      // 기준 잔액을 저장한 시각. 이 이후의 거래만 잔액에 반영된다.
      DbSchema.acBalanceAsOf:
          (account.balanceAsOf ?? DateTime.now()).millisecondsSinceEpoch,
    };

    final int? id = account.id;
    if (id == null) {
      values[DbSchema.acCreatedAt] = now;
      final int newId = await _db.insert(
        _table,
        values,
        // 같은 이름의 계좌는 하나만.
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      AppLogger.i('계좌 추가: ${account.name} (${account.type.label})');
      _notify();
      return account.copyWith(id: newId);
    }

    await _db.update(
      _table,
      values,
      where: '${DbSchema.acId} = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
    return account;
  }

  @override
  Future<void> delete(int id) async {
    // 스냅샷은 ON DELETE CASCADE 로 함께 지워진다.
    await _db.delete(
      _table,
      where: '${DbSchema.acId} = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
  }

  @override
  Future<void> updateBalance({required int id, required int balance}) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      _table,
      <String, Object?>{
        DbSchema.acBalance: balance,
        DbSchema.acUpdatedAt: now,
        // 사용자가 "지금 잔액" 을 입력한 것이므로 기준 시각도 지금으로 옮긴다.
        // 그러지 않으면 이미 반영된 과거 거래가 두 번 반영된다.
        DbSchema.acBalanceAsOf: now,
      },
      where: '${DbSchema.acId} = ?',
      whereArgs: <Object?>[id],
    );
    // 잔액을 고칠 때마다 기록을 남겨야 추이를 계산할 수 있다.
    await recordSnapshot();
    _notify();
  }

  @override
  Future<void> recordSnapshot() async {
    final List<Account> accounts = await findAll();
    if (accounts.isEmpty) return;

    // 모든 계좌를 **같은 타임스탬프**로 기록한다.
    // 그래야 "그 시점의 총자산" 을 합산할 수 있다.
    final int at = DateTime.now().millisecondsSinceEpoch;

    final Batch batch = _db.batch();
    for (final Account account in accounts) {
      final int? id = account.id;
      if (id == null) continue;
      batch.insert(DbSchema.tableAccountSnapshots, <String, Object?>{
        DbSchema.asAccountId: id,
        DbSchema.asBalance: account.balance,
        DbSchema.asRecordedAt: at,
      });
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<String>> names() async {
    final List<Account> accounts = await findAll();
    return accounts.map((Account a) => a.name).toList();
  }

  static Account _fromRow(Map<String, Object?> row) {
    return Account(
      id: row[DbSchema.acId] as int?,
      name: (row[DbSchema.acName] as String?) ?? '',
      type: AccountType.fromCode(row[DbSchema.acType] as String?),
      balance: (row[DbSchema.acBalance] as int?) ?? 0,
      isActive: ((row[DbSchema.acIsActive] as int?) ?? 1) == 1,
      sortOrder: (row[DbSchema.acSortOrder] as int?) ?? 0,
      balanceAsOf: _toDate(row[DbSchema.acBalanceAsOf]),
      createdAt: _toDate(row[DbSchema.acCreatedAt]),
      updatedAt: _toDate(row[DbSchema.acUpdatedAt]),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  void dispose() => _changes.close();
}

/// 스냅샷 합계 + 기록 시각.
class _SnapshotTotal {
  const _SnapshotTotal({required this.total, required this.recordedAt});

  final int total;
  final DateTime recordedAt;
}
