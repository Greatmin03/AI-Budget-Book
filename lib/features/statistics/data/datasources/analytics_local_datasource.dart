import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/utils/date_range.dart';
import '../../../transactions/data/models/transaction_dto.dart';

/// 브랜드/카테고리 드릴다운 집계 쿼리.
///
/// 금액 기준은 `StatisticsLocalDataSource` 와 같다.
/// 집계는 **실제 부담 금액**(정산 차감 후), 개별 거래 표시는 원본 금액.
class AnalyticsLocalDataSource {
  AnalyticsLocalDataSource(this._db);

  final Database _db;

  static const String _from = 'FROM ${DbSchema.tableTransactions} t';
  static const String _net = DbSchema.netAmountExpr;

  /// 기간 조건 + **자산 이동·수입 제외**.
  ///
  /// 이 파일의 지표는 모두 "소비" 분석이므로 예외 없이 이 조건을 쓴다.
  /// 적금 납입(자산 이동)과 입금(수입)은 지출이 아니다.
  /// (현금 흐름 지표는 `StatisticsLocalDataSource` 에 있다)
  static const String _rangeWhere =
      't.${DbSchema.tPaymentDatetime} >= ? '
      'AND t.${DbSchema.tPaymentDatetime} < ? '
      'AND ${DbSchema.spendingOnly}';

  List<Object?> _rangeArgs(DateRange range) =>
      <Object?>[range.startMillis, range.endExclusiveMillis];

  /// 브랜드별 집계.
  Future<List<Map<String, Object?>>> brandStats({
    required DateRange range,
    required String orderBy,
    required int limit,
  }) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt, '
      'MAX(t.${DbSchema.tPaymentDatetime}) AS last_at, '
      'CAST(SUM($_net) AS REAL) / COUNT(*) AS avg_amount '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY $orderBy '
      'LIMIT ?',
      <Object?>[...(_rangeArgs(range)), limit],
    );
  }

  /// 브랜드별 대표 카테고리(건수 최다).
  Future<List<Map<String, Object?>>> brandPrimaryCategories(DateRange range) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      't.${DbSchema.tCategory} AS category, '
      't.${DbSchema.tSubcategory} AS subcategory, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tBrand}, t.${DbSchema.tCategory}, '
      '         t.${DbSchema.tSubcategory} '
      'ORDER BY t.${DbSchema.tBrand} ASC, cnt DESC',
      _rangeArgs(range),
    );
  }

  /// 카테고리 + 서브카테고리 집계(트리 구성용).
  Future<List<Map<String, Object?>>> categorySubcategoryTotals(
    DateRange range,
  ) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tCategory} AS category, '
      't.${DbSchema.tSubcategory} AS subcategory, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tCategory}, t.${DbSchema.tSubcategory} '
      'ORDER BY amount DESC',
      _rangeArgs(range),
    );
  }

  /// 특정 카테고리(선택적으로 서브카테고리)에 속한 브랜드 집계.
  Future<List<Map<String, Object?>>> brandsInCategory({
    required DateRange range,
    required String category,
    String? subcategory,
    int limit = 100,
  }) {
    final String subFilter =
        subcategory == null ? '' : ' AND t.${DbSchema.tSubcategory} = ?';

    return _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt, '
      'MAX(t.${DbSchema.tPaymentDatetime}) AS last_at '
      '$_from '
      'WHERE $_rangeWhere AND t.${DbSchema.tCategory} = ?$subFilter '
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY amount DESC '
      'LIMIT ?',
      <Object?>[
        ...(_rangeArgs(range)),
        category,
        if (subcategory != null) subcategory,
        limit,
      ],
    );
  }

  /// 특정 카테고리의 합계/건수.
  Future<Map<String, Object?>> categoryTotal({
    required DateRange range,
    required String category,
    String? subcategory,
  }) async {
    final String subFilter =
        subcategory == null ? '' : ' AND t.${DbSchema.tSubcategory} = ?';

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS amount, COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere AND t.${DbSchema.tCategory} = ?$subFilter',
      <Object?>[
        ...(_rangeArgs(range)),
        category,
        if (subcategory != null) subcategory,
      ],
    );
    return rows.isEmpty ? const <String, Object?>{} : rows.first;
  }

  /// 특정 카테고리의 서브카테고리 내역.
  Future<List<Map<String, Object?>>> subcategoriesOfCategory({
    required DateRange range,
    required String category,
  }) {
    return _db.rawQuery(
      'SELECT t.${DbSchema.tSubcategory} AS name, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from '
      'WHERE $_rangeWhere AND t.${DbSchema.tCategory} = ? '
      'GROUP BY t.${DbSchema.tSubcategory} '
      'ORDER BY amount DESC',
      <Object?>[...(_rangeArgs(range)), category],
    );
  }

  /// 특정 브랜드의 합계/건수/최근 결제일.
  ///
  /// `gross` 는 원본 결제 합계, `amount` 는 정산 차감 후 실제 부담이다.
  Future<Map<String, Object?>> brandTotal({
    required DateRange range,
    required String brand,
  }) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS amount, '
      'COALESCE(SUM(t.${DbSchema.tAmount}), 0) AS gross, '
      'COUNT(*) AS cnt, '
      'MAX(t.${DbSchema.tPaymentDatetime}) AS last_at '
      '$_from WHERE $_rangeWhere AND t.${DbSchema.tBrand} = ?',
      <Object?>[...(_rangeArgs(range)), brand],
    );
    return rows.isEmpty ? const <String, Object?>{} : rows.first;
  }

  /// 특정 브랜드의 결제 내역(최신순).
  ///
  /// 지점명과 정산 합계를 함께 가져온다.
  Future<List<Map<String, Object?>>> brandTransactions({
    required DateRange range,
    required String brand,
    required int limit,
  }) {
    return _db.rawQuery(
      'SELECT t.*, m.${DbSchema.mBranch} AS merchant_branch, '
      '${DbSchema.settledSumExpr} AS ${TransactionDto.settledAmountColumn} '
      '$_from '
      'LEFT JOIN ${DbSchema.tableMerchants} m '
      '  ON t.${DbSchema.tMerchantId} = m.${DbSchema.mId} '
      'WHERE $_rangeWhere AND t.${DbSchema.tBrand} = ? '
      'ORDER BY t.${DbSchema.tPaymentDatetime} DESC '
      'LIMIT ?',
      <Object?>[...(_rangeArgs(range)), brand, limit],
    );
  }

  /// 특정 브랜드의 지점별 집계.
  Future<List<Map<String, Object?>>> brandBranches({
    required DateRange range,
    required String brand,
  }) {
    return _db.rawQuery(
      'SELECT COALESCE(NULLIF(m.${DbSchema.mBranch}, \'\'), '
      '                t.${DbSchema.tMerchantRaw}) AS label, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from '
      'LEFT JOIN ${DbSchema.tableMerchants} m '
      '  ON t.${DbSchema.tMerchantId} = m.${DbSchema.mId} '
      'WHERE $_rangeWhere AND t.${DbSchema.tBrand} = ? '
      'GROUP BY label '
      'ORDER BY amount DESC',
      <Object?>[...(_rangeArgs(range)), brand],
    );
  }

  /// 특정 카테고리의 기간 합계(추이 계산용).
  Future<int> categoryAmountInRange({
    required DateRange range,
    required String category,
    String? subcategory,
  }) async {
    final String subFilter =
        subcategory == null ? '' : ' AND t.${DbSchema.tSubcategory} = ?';

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS amount '
      '$_from WHERE $_rangeWhere AND t.${DbSchema.tCategory} = ?$subFilter',
      <Object?>[
        ...(_rangeArgs(range)),
        category,
        if (subcategory != null) subcategory,
      ],
    );
    return _asInt(rows.isEmpty ? null : rows.first['amount']);
  }

  /// 특정 브랜드의 기간 합계(추이 계산용).
  Future<int> brandAmountInRange({
    required DateRange range,
    required String brand,
  }) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS amount '
      '$_from WHERE $_rangeWhere AND t.${DbSchema.tBrand} = ?',
      <Object?>[...(_rangeArgs(range)), brand],
    );
    return _asInt(rows.isEmpty ? null : rows.first['amount']);
  }

  /// 브랜드명 검색.
  ///
  /// LIKE 와일드카드(`%`, `_`)를 사용자 입력으로 받으면 의도치 않은 결과가
  /// 나오므로 ESCAPE 절로 무력화한다.
  Future<List<Map<String, Object?>>> searchBrands({
    required DateRange range,
    required String query,
    required int limit,
  }) {
    final String pattern = '%${escapeLike(query)}%';
    return _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt, '
      'MAX(t.${DbSchema.tPaymentDatetime}) AS last_at '
      '$_from '
      'WHERE $_rangeWhere '
      "  AND (t.${DbSchema.tBrand} LIKE ? ESCAPE '\\' "
      "   OR t.${DbSchema.tMerchantRaw} LIKE ? ESCAPE '\\') "
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY amount DESC '
      'LIMIT ?',
      <Object?>[...(_rangeArgs(range)), pattern, pattern, limit],
    );
  }

  /// LIKE 특수문자 이스케이프. 역슬래시를 escape 문자로 쓴다.
  ///
  /// 원시 문자열(`r'\'`)은 쓰지 않는다. 역슬래시로 끝나는 원시 문자열은
  /// 읽는 사람마다 해석이 갈리므로 명시적으로 이스케이프한다.
  static String escapeLike(String input) => input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  /// 가장 많이 방문한 브랜드 1건.
  Future<Map<String, Object?>?> topVisitedBrand(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt, '
      'MAX(t.${DbSchema.tPaymentDatetime}) AS last_at '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY cnt DESC, amount DESC '
      'LIMIT 1',
      _rangeArgs(range),
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 가장 많이 소비한 카테고리 1건.
  Future<Map<String, Object?>?> topCategory(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.${DbSchema.tCategory} AS name, '
      'SUM($_net) AS amount, '
      'COUNT(*) AS cnt '
      '$_from WHERE $_rangeWhere '
      'GROUP BY t.${DbSchema.tCategory} '
      'ORDER BY amount DESC '
      'LIMIT 1',
      _rangeArgs(range),
    );
    return rows.isEmpty ? null : rows.first;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}
