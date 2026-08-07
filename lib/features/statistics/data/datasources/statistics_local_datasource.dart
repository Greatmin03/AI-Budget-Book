import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/utils/date_range.dart';

/// 기본 통계 집계 쿼리(총액 / 카테고리 비율 / 브랜드 상위 / 일별).
///
/// ## 금액 기준
/// 모든 합계는 **실제 부담 금액**(`amount - 정산 합계`)을 더한다.
/// 30,000원을 결제하고 20,000원을 정산받았다면 통계에는 10,000원만 잡힌다.
/// 원본 결제 금액이 필요한 곳(거래 목록, 카드 명세 대조)은 `amount` 를 직접 읽는다.
///
/// 취소 거래는 금액이 음수로 저장되므로 합계에서 자동으로 차감된다.
class StatisticsLocalDataSource {
  StatisticsLocalDataSource(this._db);

  final Database _db;

  static const String _from = 'FROM ${DbSchema.tableTransactions} t';
  static const String _net = DbSchema.netAmountExpr;

  /// 기간 조건 + **자산 이동·수입 제외**.
  ///
  /// 소비 지표는 모두 이 조건을 쓴다.
  /// 적금 납입(자산 이동)과 입금(수입)은 지출이 아니다.
  /// 자산 이동까지 포함해야 하는 현금 흐름 지표는 [_rangeOnlyWhere] 를 쓴다.
  static const String _rangeWhere =
      't.${DbSchema.tPaymentDatetime} >= ? '
      'AND t.${DbSchema.tPaymentDatetime} < ? '
      'AND ${DbSchema.spendingOnly}';

  /// 기간 조건만. 방향을 가리지 않는다(수입 + 지출 전부).
  static const String _rangeOnlyWhere =
      't.${DbSchema.tPaymentDatetime} >= ? '
      'AND t.${DbSchema.tPaymentDatetime} < ?';

  /// 기간 + **나가는 돈만**(자산 이동 포함, 수입 제외). 현금 흐름용.
  static const String _rangeExpenseWhere =
      '$_rangeOnlyWhere AND ${DbSchema.expenseOnly}';

  /// 기간 + **번 돈만**.
  ///
  /// 정산(돌려받은 돈)은 뺀다. 더치페이로 친구가 보낸 20,000원은 소득이
  /// 아니다 — 이미 그 결제의 정산으로 내 부담이 줄어 있으므로, 수입으로도
  /// 세면 같은 돈을 두 번 세게 된다.
  static const String _rangeIncomeWhere =
      '$_rangeOnlyWhere AND ${DbSchema.earnedIncomeOnly}';

  List<Object?> _rangeArgs(DateRange range) =>
      <Object?>[range.startMillis, range.endExclusiveMillis];

  Future<int> totalInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS total $_from WHERE $_rangeWhere',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['total']);
  }

  /// 원본 결제 금액 합계(정산 차감 전). "총 결제" 표시용.
  Future<int> grossTotalInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(t.${DbSchema.tAmount}), 0) AS total '
      '$_from WHERE $_rangeWhere',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['total']);
  }

  /// **현금 흐름**: 자산 이동까지 포함한 실제 계좌 유출 합계.
  ///
  /// 적금 납입은 소비가 아니지만 통장에서는 나간 돈이다.
  /// "이번 달에 통장에서 얼마 나갔나" 를 보려면 이 값을 쓴다.
  ///
  /// **수입은 포함하지 않는다.** 수입도 양수로 저장되므로 방향 조건을 빼면
  /// 입금이 유출에 더해진다(300,000원 입금 + 15,000원 결제 = 315,000원).
  Future<int> cashOutflowInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS total $_from '
      'WHERE $_rangeExpenseWhere',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['total']);
  }

  /// 기간 내 **수입** 합계.
  ///
  /// 수입에는 정산 개념이 없지만 같은 식을 쓴다. 정산이 붙지 않은 거래에서는
  /// `netAmountExpr` 이 `amount` 와 같으므로 결과가 달라지지 않는다.
  Future<int> incomeTotalInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS total $_from '
      'WHERE $_rangeIncomeWhere',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['total']);
  }

  /// 기간 내 수입 건수.
  Future<int> incomeCountInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c $_from WHERE $_rangeIncomeWhere',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['c']);
  }

  /// 수입 카테고리별 합계(급여/장학금/용돈/기타).
  Future<List<Map<String, Object?>>> incomeByCategory(DateRange range) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tCategory} AS name, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeIncomeWhere '
      'GROUP BY t.${DbSchema.tCategory} '
      'ORDER BY amount DESC',
      _rangeArgs(range),
    );
  }

  /// 기간 내 자산 이동 합계(소비에서 제외된 금액).
  Future<int> assetTransferTotalInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS total $_from '
      'WHERE $_rangeOnlyWhere AND ${DbSchema.assetTransferOnly}',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['total']);
  }

  /// 자산 이동을 종류별로 나눈 합계(저축/청약/투자/기타).
  ///
  /// `asset_kind` 가 없는 예전 행은 `other` 로 묶인다.
  Future<List<Map<String, Object?>>> assetTransfersByKind(DateRange range) {
    return _db.rawQuery(
      "SELECT COALESCE(NULLIF(t.${DbSchema.tAssetKind}, ''), 'other') AS kind, "
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeOnlyWhere AND ${DbSchema.assetTransferOnly} '
      'GROUP BY kind '
      'ORDER BY amount DESC',
      _rangeArgs(range),
    );
  }

  Future<int> countInRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c $_from WHERE $_rangeWhere',
      _rangeArgs(range),
    );
    return _asInt(rows.isEmpty ? null : rows.first['c']);
  }

  /// 카테고리별 합계(금액 내림차순).
  Future<List<Map<String, Object?>>> byCategory(DateRange range) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tCategory} AS name, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tCategory} '
      'ORDER BY amount DESC',
      _rangeArgs(range),
    );
  }

  /// 서브카테고리별 합계.
  Future<List<Map<String, Object?>>> bySubcategory(DateRange range) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tSubcategory} AS name, '
      't.${DbSchema.tCategory} AS parent, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tCategory}, t.${DbSchema.tSubcategory} '
      'ORDER BY amount DESC',
      _rangeArgs(range),
    );
  }

  /// 브랜드별 합계(금액 상위).
  Future<List<Map<String, Object?>>> byBrand(DateRange range, int limit) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY amount DESC '
      'LIMIT ?',
      <Object?>[...(_rangeArgs(range)), limit],
    );
  }

  /// 방문 횟수 상위 가맹점("가장 많이 간 가게").
  Future<List<Map<String, Object?>>> topVisited(DateRange range, int limit) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY cnt DESC, amount DESC '
      'LIMIT ?',
      <Object?>[...(_rangeArgs(range)), limit],
    );
  }

  /// 특정 서브카테고리의 합계와 건수.
  Future<Map<String, Object?>> subcategoryTotal(
    DateRange range,
    String subcategory,
  ) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS amount, COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere AND t.${DbSchema.tSubcategory} = ?',
      <Object?>[...(_rangeArgs(range)), subcategory],
    );
    return rows.isEmpty ? const <String, Object?>{} : rows.first;
  }

  /// 일별 집계용 원시 시각 + 실제 부담 금액.
  ///
  /// millis -> 로컬 날짜 변환을 SQLite 에 맡기면 타임존 처리가 위험하므로,
  /// 원시 값만 가져와 Dart 에서 그룹화한다.
  Future<List<Map<String, Object?>>> paymentTimesInRange(DateRange range) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tPaymentDatetime} AS ts, $_net AS amount '
      '$_from WHERE $_rangeWhere',
      _rangeArgs(range),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}
