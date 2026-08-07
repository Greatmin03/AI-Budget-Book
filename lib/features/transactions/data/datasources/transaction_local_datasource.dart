import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/utils/date_range.dart';
import '../../domain/entities/transaction.dart';
import '../models/transaction_dto.dart';

/// `transactions` 테이블 접근.
///
/// 모든 조회는 정산 합계(`settled_amount`)를 함께 계산해서 돌려준다.
/// 그래야 목록에서 "원본 금액"과 "실제 부담"을 동시에 보여 줄 수 있고,
/// 거래마다 정산을 다시 조회하는 N+1 이 생기지 않는다.
class TransactionLocalDataSource {
  TransactionLocalDataSource(this._db);

  final Database _db;

  static const String _t = DbSchema.tableTransactions;

  /// `SELECT` 절. 거래 전체 + 정산 합계.
  static const String _select =
      'SELECT t.*, ${DbSchema.settledSumExpr} AS '
      '${TransactionDto.settledAmountColumn} FROM $_t t';

  /// 중복(fingerprint 충돌) 시 0 을 반환한다.
  Future<int> insert(Map<String, Object?> row) {
    return _db.insert(
      _t,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Map<String, Object?>?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      '$_select WHERE t.${DbSchema.tId} = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findByFingerprint(String fingerprint) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      '$_select WHERE t.${DbSchema.tFingerprint} = ? LIMIT 1',
      <Object?>[fingerprint],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> findByRange(DateRange range) {
    return _db.rawQuery(
      '$_select '
      'WHERE t.${DbSchema.tPaymentDatetime} >= ? '
      '  AND t.${DbSchema.tPaymentDatetime} < ? '
      'ORDER BY t.${DbSchema.tPaymentDatetime} DESC',
      <Object?>[range.startMillis, range.endExclusiveMillis],
    );
  }

  Future<List<Map<String, Object?>>> findRecent(int limit) {
    return _db.rawQuery(
      '$_select ORDER BY t.${DbSchema.tPaymentDatetime} DESC LIMIT ?',
      <Object?>[limit],
    );
  }

  Future<List<Map<String, Object?>>> findNeedingReview(int limit) {
    return _db.rawQuery(
      '$_select WHERE t.${DbSchema.tNeedsReview} = 1 '
      'ORDER BY t.${DbSchema.tPaymentDatetime} ASC LIMIT ?',
      <Object?>[limit],
    );
  }

  /// 아직 전액을 돌려받지 못한 거래(정산 후보).
  ///
  /// 입금액과 남은 금액의 차이가 작은 순으로 정렬해, 가장 그럴듯한 후보를
  /// 먼저 보여 준다.
  Future<List<Map<String, Object?>>> findSettlementCandidates({
    required int depositAmount,
    required int fromMillis,
    required int toMillis,
    required int limit,
  }) {
    return _db.rawQuery(
      '$_select '
      'WHERE t.${DbSchema.tAmount} > 0 '
      '  AND t.${DbSchema.tIsCancelled} = 0 '
      // 정산은 "내가 대신 낸 지출"을 나눠 받는 것이다.
      // 수입(받은 돈)이나 자산 이동(적금 납입)에 입금을 붙이면 말이 안 되고,
      // net 이 깎여 통계가 틀어진다. 수입도 양수로 저장되므로
      // `amount > 0` 만으로는 걸러지지 않는다.
      '  AND ${DbSchema.spendingOnly} '
      '  AND t.${DbSchema.tPaymentDatetime} >= ? '
      '  AND t.${DbSchema.tPaymentDatetime} <= ? '
      '  AND ${DbSchema.netAmountExpr} > 0 '
      'ORDER BY ABS(${DbSchema.netAmountExpr} - ?) ASC, '
      '         t.${DbSchema.tPaymentDatetime} DESC '
      'LIMIT ?',
      <Object?>[fromMillis, toMillis, depositAmount, limit],
    );
  }

  /// **거의 같은 거래**를 찾는다(다른 앱이 같은 결제를 알린 경우).
  ///
  /// 지문(fingerprint)은 카드명까지 포함하므로, KB 앱과 토스 앱이 같은 결제를
  /// 서로 다른 문구로 알리면 지문이 달라져 두 건이 저장된다.
  /// 그래서 "사실상 같은 결제" 를 별도 조건으로 판단한다.
  ///
  ///  - 금액 동일
  ///  - 브랜드 동일
  ///  - 결제 수단 동일
  ///  - 결제 시각 차이가 [windowSeconds] 이내
  /// **다른 앱**이 알린 같은 결제를 찾는다.
  ///
  /// 브랜드는 비교하지 않는다. 토스는 `더스윙`, 은행은 `통신판매_NIC` 처럼
  /// 서로 다른 이름을 주기 때문이다 — 브랜드로 맞추려 하면 영영 못 만난다.
  ///
  /// 금액과 시각만으로 맞추므로 창을 좁게 잡는다. 같은 앱에서 온 것은
  /// 제외한다(그건 진짜 중복이거나 정말 별개의 결제다).
  Future<Map<String, Object?>?> findMergeTarget({
    required int amount,
    required DateTime paymentDatetime,
    required String sourcePackage,
    required int windowSeconds,
  }) async {
    final int center = paymentDatetime.millisecondsSinceEpoch;
    final int window = windowSeconds * 1000;

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      '$_select '
      'WHERE t.${DbSchema.tAmount} = ? '
      '  AND t.${DbSchema.tEntrySource} = ? '
      '  AND t.${DbSchema.tPaymentDatetime} BETWEEN ? AND ? '
      "  AND COALESCE(t.${DbSchema.tSourcePackage}, '') != ? "
      'ORDER BY ABS(t.${DbSchema.tPaymentDatetime} - ?) ASC '
      'LIMIT 1',
      <Object?>[
        amount,
        EntrySource.notification.code,
        center - window,
        center + window,
        sourcePackage,
        center,
      ],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findNearDuplicate({
    required String brand,
    required int amount,
    required String paymentMethod,
    required DateTime paymentDatetime,
    required int windowSeconds,
  }) async {
    final int center = paymentDatetime.millisecondsSinceEpoch;
    final int window = windowSeconds * 1000;

    final List<Map<String, Object?>> rows = await _db.query(
      _t,
      where: '${DbSchema.tAmount} = ? '
          'AND ${DbSchema.tBrand} = ? '
          'AND ${DbSchema.tPaymentMethod} = ? '
          'AND ${DbSchema.tPaymentDatetime} BETWEEN ? AND ?',
      whereArgs: <Object?>[
        amount,
        brand,
        paymentMethod,
        center - window,
        center + window,
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// AI 분석을 기다리는 거래. 브랜드별로 묶기 쉽게 브랜드 순으로 준다.
  Future<List<Map<String, Object?>>> findAiPending({int limit = 500}) {
    return _db.rawQuery(
      '$_select '
      'WHERE ${DbSchema.aiPendingOnly} '
      'ORDER BY t.${DbSchema.tBrand} ASC, '
      '         t.${DbSchema.tPaymentDatetime} DESC '
      'LIMIT ?',
      <Object?>[limit],
    );
  }

  Future<int> countAiPending() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_t t WHERE ${DbSchema.aiPendingOnly}',
    );
    final Object? value = rows.isEmpty ? null : rows.first['c'];
    return value is int ? value : 0;
  }

  /// 처리 중에 멈춘 거래를 다시 대기로 되돌린다.
  ///
  /// `processing` 은 같은 브랜드를 두 번 집어오지 않기 위한 표시인데,
  /// **일괄 분석 도중 앱이 죽으면 그 표시가 그대로 남는다.**
  /// `aiPendingOnly` 는 `processing` 을 포함하지 않으므로, 되돌리지 않으면
  /// 그 거래는 다시는 분석되지 않는다.
  ///
  /// 그래서 일괄 분석을 시작할 때마다 먼저 정리한다.
  Future<int> resetStuckAiProcessing() {
    return _db.update(
      _t,
      <String, Object?>{DbSchema.tAiStatus: 'pending'},
      where: "${DbSchema.tAiStatus} = 'processing'",
    );
  }

  /// 브랜드 하나의 대기 거래 상태를 한 번에 바꾼다.
  Future<int> updateAiStatusForBrand({
    required String brand,
    required String status,
    required int updatedAt,
    int? processedAt,
  }) {
    return _db.update(
      _t,
      <String, Object?>{
        DbSchema.tAiStatus: status,
        DbSchema.tAiProcessedAt: processedAt,
        DbSchema.tUpdatedAt: updatedAt,
      },
      // 이미 사용자가 직접 고친 거래는 건드리지 않는다.
      where: '${DbSchema.tBrand} = ? '
          "AND ${DbSchema.tAiStatus} IN ('pending', 'processing')",
      whereArgs: <Object?>[brand],
    );
  }

  /// 브랜드 하나의 분류를 확정하고 대기 상태를 해제한다.
  Future<int> applyAiClassificationForBrand({
    required String brand,
    required String category,
    required String subcategory,
    required String source,
    required int updatedAt,
  }) {
    return _db.rawUpdate(
      'UPDATE $_t SET '
      '${DbSchema.tCategory} = ?, '
      '${DbSchema.tSubcategory} = ?, '
      '${DbSchema.tClassificationSource} = ?, '
      '${DbSchema.tNeedsReview} = 0, '
      "${DbSchema.tAiStatus} = 'completed', "
      '${DbSchema.tAiProcessedAt} = ?, '
      '${DbSchema.tUpdatedAt} = ? '
      'WHERE ${DbSchema.tBrand} = ? '
      // 사용자가 직접 분류한 거래는 AI 결과로 덮지 않는다.
      "AND ${DbSchema.tClassificationSource} != 'user' "
      "AND ${DbSchema.tAiStatus} IN ('pending', 'processing')",
      <Object?>[
        category,
        subcategory,
        source,
        updatedAt,
        updatedAt,
        brand,
      ],
    );
  }

  Future<int> update(int id, Map<String, Object?> row) {
    return _db.update(
      _t,
      row,
      where: '${DbSchema.tId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> delete(int id) {
    return _db.delete(
      _t,
      where: '${DbSchema.tId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 브랜드 단위 재분류. 사용자가 개별로 고친 거래는 보존한다.
  /// (원본 거래명, 현재 브랜드) 조합과 건수. 브랜드 재정규화용.
  ///
  /// 같은 조합은 정규화 결과도 같으므로 사전 조회를 조합당 한 번으로 줄인다.
  Future<List<Map<String, Object?>>> distinctBrandSources() {
    return _db.rawQuery(
      'SELECT ${DbSchema.tMerchantRaw} AS merchant_raw, '
      '${DbSchema.tBrand} AS brand, '
      'COUNT(*) AS cnt '
      'FROM $_t '
      'WHERE ${DbSchema.tMerchantRaw} IS NOT NULL '
      "AND TRIM(${DbSchema.tMerchantRaw}) != '' "
      'GROUP BY ${DbSchema.tMerchantRaw}, ${DbSchema.tBrand} '
      'ORDER BY cnt DESC',
    );
  }

  /// 브랜드 표기만 바꾼다. `merchant_raw` 는 그대로 둔다.
  ///
  /// [from] 을 조건에 넣어, 조회 후 사용자가 손댄 거래를 덮지 않는다.
  Future<int> renameBrand({
    required String merchantRaw,
    required String from,
    required String to,
    required int updatedAt,
  }) {
    return _db.rawUpdate(
      'UPDATE $_t SET ${DbSchema.tBrand} = ?, ${DbSchema.tUpdatedAt} = ? '
      'WHERE ${DbSchema.tMerchantRaw} = ? AND ${DbSchema.tBrand} = ?',
      <Object?>[to, updatedAt, merchantRaw, from],
    );
  }

  /// 이 취소가 되돌렸을 법한 원결제 **후보 전부**. 가까운 것부터.
  ///
  /// **브랜드로 맞추지 않는다.** 취소 알림에는 가맹점 이름이 아예 없다
  /// (`출금취소 3,400`). 브랜드를 조건에 넣으면 영영 못 만난다.
  ///
  /// 대신 같은 카드 + 같은 금액 + 취소 이전으로 좁힌다.
  Future<List<Map<String, Object?>>> findCancellationCandidates({
    required int amount,
    required int cancelledAtMillis,
    required int windowMillis,
    required int excludeId,
  }) {
    return _db.rawQuery(
      '$_select '
      'WHERE t.${DbSchema.tAmount} = ? '
      '  AND t.${DbSchema.tId} != ? '
      '  AND t.${DbSchema.tIsCancelled} = 0 '
      '  AND t.${DbSchema.tPaymentDatetime} <= ? '
      '  AND t.${DbSchema.tPaymentDatetime} >= ? '
      'ORDER BY t.${DbSchema.tPaymentDatetime} DESC',
      <Object?>[
        amount,
        excludeId,
        cancelledAtMillis,
        cancelledAtMillis - windowMillis,
      ],
    );
  }

  /// 원결제를 아직 찾지 못한 취소들(최신순).
  Future<List<Map<String, Object?>>> findUnmatchedCancellations(int limit) {
    return _db.rawQuery(
      '$_select '
      'WHERE t.${DbSchema.tIsCancelled} = 1 '
      '  AND t.${DbSchema.tAmount} < 0 '
      '  AND t.${DbSchema.tCancelsTransactionId} IS NULL '
      'ORDER BY t.${DbSchema.tPaymentDatetime} DESC '
      'LIMIT ?',
      <Object?>[limit],
    );
  }

  /// 취소와 원결제를 잇는다(또는 [originalId] 가 null 이면 끊는다).
  Future<int> setCancellationLink({
    required int cancellationId,
    required int? originalId,
    required int updatedAt,
  }) {
    return _db.update(
      _t,
      <String, Object?>{
        DbSchema.tCancelsTransactionId: originalId,
        DbSchema.tUpdatedAt: updatedAt,
      },
      where: '${DbSchema.tId} = ?',
      whereArgs: <Object?>[cancellationId],
    );
  }

  Future<int> setCancelled(int id, bool cancelled, int updatedAt) {
    return _db.update(
      _t,
      <String, Object?>{
        DbSchema.tIsCancelled: cancelled ? 1 : 0,
        DbSchema.tUpdatedAt: updatedAt,
      },
      where: '${DbSchema.tId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> markCancelled(int id, int updatedAt) {
    return _db.update(
      _t,
      <String, Object?>{
        DbSchema.tIsCancelled: 1,
        DbSchema.tUpdatedAt: updatedAt,
      },
      where: '${DbSchema.tId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> reclassifyByBrand({
    required String brand,
    required String category,
    required String subcategory,
    required int updatedAt,
    int? onlyFromMillis,
  }) {
    final StringBuffer where = StringBuffer(
      "${DbSchema.tBrand} = ? AND ${DbSchema.tClassificationSource} != 'user'",
    );
    final List<Object?> args = <Object?>[category, subcategory, updatedAt, brand];

    if (onlyFromMillis != null) {
      where.write(' AND ${DbSchema.tPaymentDatetime} >= ?');
      args.add(onlyFromMillis);
    }

    return _db.rawUpdate(
      'UPDATE $_t SET '
      '${DbSchema.tCategory} = ?, '
      '${DbSchema.tSubcategory} = ?, '
      '${DbSchema.tUpdatedAt} = ? '
      'WHERE $where',
      args,
    );
  }

  /// 같은 브랜드의 "분류 필요" 거래를 모두 해소한다.
  Future<int> resolveReviewForBrand({
    required String brand,
    required String category,
    required String subcategory,
    required int updatedAt,
  }) {
    return _db.rawUpdate(
      'UPDATE $_t SET '
      '${DbSchema.tCategory} = ?, '
      '${DbSchema.tSubcategory} = ?, '
      "${DbSchema.tClassificationSource} = 'user', "
      '${DbSchema.tNeedsReview} = 0, '
      '${DbSchema.tUpdatedAt} = ? '
      'WHERE ${DbSchema.tBrand} = ? AND ${DbSchema.tNeedsReview} = 1',
      <Object?>[category, subcategory, updatedAt, brand],
    );
  }

  Future<int> countNeedingReview() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM $_t WHERE ${DbSchema.tNeedsReview} = 1',
          ),
        ) ??
        0;
  }

  Future<int> countAll() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM $_t'),
        ) ??
        0;
  }
}
