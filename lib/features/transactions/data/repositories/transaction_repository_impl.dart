import 'dart:async';

import '../../../../core/constants/classification_source.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../datasources/transaction_local_datasource.dart';
import '../models/transaction_dto.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._local);

  final TransactionLocalDataSource _local;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// 같은 결제로 보는 시각 차이. 카드사 앱과 페이 앱의 알림 시각이
  /// 몇 초씩 어긋나므로 여유를 둔다. 30초면 같은 가게에서 같은 금액을
  /// 두 번 결제하는 정상 상황과는 사실상 겹치지 않는다.
  static const int _nearDuplicateWindowSeconds = 30;

  @override
  Future<Transaction?> insert(Transaction transaction) async {
    final DateTime now = DateTime.now();

    // 여러 금융 앱이 같은 결제를 알리는 경우를 저장 단계에서 막는다.
    // **화면에서 숨기지 않고 저장 자체를 하지 않는다.** 저장해 두면
    // 모든 집계가 두 배가 되고, 나중에 골라내는 것은 사용자 몫이 된다.
    if (await _isNearDuplicate(transaction)) return null;

    final int id = await _local.insert(
      TransactionDto.toRow(transaction, now: now),
    );

    if (id == 0) {
      // conflictAlgorithm.ignore -> 같은 지문이라 저장되지 않음
      AppLogger.d('중복 알림 무시: ${transaction.fingerprint}');
      return null;
    }

    AppLogger.i('거래 저장: ${transaction.displayName} ${transaction.amount}원 '
        '(${transaction.category}/${transaction.subcategory})');
    _notify();
    return transaction.copyWith(id: id);
  }

  /// 같은 결제를 다른 앱이 알렸다고 볼 시각 차이.
  ///
  /// 은행 알림은 분 단위로만 시각을 주므로(`08/06 10:07`) 초가 항상 0이다.
  /// 두 앱의 알림이 분 경계를 사이에 두면 60초까지 벌어질 수 있어 넉넉히
  /// 잡되, 같은 금액의 다른 결제를 삼키지 않도록 2분을 넘기지 않는다.
  static const int _mergeWindowSeconds = 120;

  @override
  Future<Transaction?> findMergeTarget({
    required int amount,
    required DateTime paymentDatetime,
    required String sourcePackage,
  }) async {
    final Map<String, Object?>? row = await _local.findMergeTarget(
      amount: amount,
      paymentDatetime: paymentDatetime,
      sourcePackage: sourcePackage,
      windowSeconds: _mergeWindowSeconds,
    );
    return row == null ? null : TransactionDto.fromRow(row);
  }

  /// 다른 앱이 알린 **같은 결제**인지 판단한다.
  ///
  /// 직접 입력은 검사하지 않는다. 사용자가 의도적으로 추가한 거래를
  /// 조용히 버리면 "저장했는데 없어졌다" 가 되기 때문이다.
  /// (같은 현금 결제를 두 번 하는 것도 정상이다)
  Future<bool> _isNearDuplicate(Transaction transaction) async {
    if (transaction.isManual) return false;

    final Map<String, Object?>? existing = await _local.findNearDuplicate(
      brand: transaction.brand,
      amount: transaction.amount,
      paymentMethod: transaction.method.code,
      paymentDatetime: transaction.paymentDatetime,
      windowSeconds: _nearDuplicateWindowSeconds,
    );
    if (existing == null) return false;

    final Transaction kept = TransactionDto.fromRow(existing);
    AppLogger.i('같은 결제로 판단해 저장하지 않음: '
        '${transaction.brand} ${transaction.amount}원 '
        '(${transaction.sourcePackage ?? '알 수 없는 앱'} → '
        '이미 ${kept.sourcePackage ?? '기존 기록'}에서 저장됨)');
    return true;
  }

  @override
  Future<Transaction?> findById(int id) async {
    final Map<String, Object?>? row = await _local.findById(id);
    return row == null ? null : TransactionDto.fromRow(row);
  }

  @override
  Future<List<Transaction>> findByRange(DateRange range) async {
    final List<Map<String, Object?>> rows = await _local.findByRange(range);
    return rows.map(TransactionDto.fromRow).toList();
  }

  @override
  Future<List<Transaction>> findNeedingReview({int limit = 100}) async {
    final List<Map<String, Object?>> rows =
        await _local.findNeedingReview(limit);
    return rows.map(TransactionDto.fromRow).toList();
  }

  @override
  Future<int> countNeedingReview() => _local.countNeedingReview();

  @override
  Future<int> resolveReviewForBrand({
    required String brand,
    required String category,
    required String subcategory,
  }) async {
    final int updated = await _local.resolveReviewForBrand(
      brand: brand,
      category: category,
      subcategory: subcategory,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (updated > 0) {
      AppLogger.i('브랜드 "$brand" 분류 필요 $updated건 해소 -> $category/$subcategory');
      _notify();
    }
    return updated;
  }

  @override
  Future<List<Transaction>> findRecent({int limit = 20}) async {
    final List<Map<String, Object?>> rows = await _local.findRecent(limit);
    return rows.map(TransactionDto.fromRow).toList();
  }

  // ------------------------------------------------------- AI 분석 대기열
  @override
  Future<List<Transaction>> findAiPending({int limit = 500}) async {
    final List<Map<String, Object?>> rows =
        await _local.findAiPending(limit: limit);
    return rows.map(TransactionDto.fromRow).toList();
  }

  @override
  Future<int> countAiPending() => _local.countAiPending();

  @override
  Future<int> resetStuckAiProcessing() async {
    final int reset = await _local.resetStuckAiProcessing();
    if (reset > 0) {
      AppLogger.i('처리 중에 멈춘 거래 $reset건을 대기로 되돌렸습니다.');
      _notify();
    }
    return reset;
  }

  @override
  Future<int> markAiStatusForBrand({
    required String brand,
    required AiStatus status,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int updated = await _local.updateAiStatusForBrand(
      brand: brand,
      status: status.code,
      updatedAt: now,
      // 처리 중에는 완료 시각을 남기지 않는다.
      processedAt: status == AiStatus.processing ? null : now,
    );
    if (updated > 0) _notify();
    return updated;
  }

  @override
  Future<int> applyAiClassificationForBrand({
    required String brand,
    required String category,
    required String subcategory,
  }) async {
    final int updated = await _local.applyAiClassificationForBrand(
      brand: brand,
      category: category,
      subcategory: subcategory,
      source: ClassificationSource.llm.code,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (updated > 0) {
      AppLogger.i('AI 분류 적용: $brand -> $category/$subcategory ($updated건)');
      _notify();
    }
    return updated;
  }

  @override
  Future<void> update(Transaction transaction) async {
    final int? id = transaction.id;
    if (id == null) {
      throw ArgumentError('id 가 없는 거래는 수정할 수 없습니다.');
    }
    await _local.update(
      id,
      TransactionDto.toRow(
        transaction,
        now: DateTime.now(),
        includeCreatedAt: false,
      ),
    );
    _notify();
  }

  @override
  Future<void> delete(int id) async {
    await _local.delete(id);
    _notify();
  }

  /// 승인취소가 원결제보다 얼마나 늦게까지 올 수 있는지.
  ///
  /// 보통 같은 날이지만 며칠 뒤에 오는 경우도 있다. 넉넉히 잡되 무한정
  /// 거슬러 올라가지는 않는다 — 우연히 같은 금액인 옛 결제를 지우면 안 된다.
  static const Duration _cancellationWindow = Duration(days: 60);

  @override
  Future<Transaction?> findCancellationTarget({
    required String brand,
    required int amount,
    required DateTime cancelledAt,
  }) async {
    final Map<String, Object?>? row = await _local.findCancellationTarget(
      brand: brand,
      amount: amount,
      cancelledAtMillis: cancelledAt.millisecondsSinceEpoch,
      windowMillis: _cancellationWindow.inMilliseconds,
    );
    return row == null ? null : TransactionDto.fromRow(row);
  }

  @override
  Future<void> markCancelled(int id) async {
    await _local.markCancelled(id, DateTime.now().millisecondsSinceEpoch);
    _notify();
  }

  @override
  Future<List<BrandSource>> distinctBrandSources() async {
    final List<Map<String, Object?>> rows = await _local.distinctBrandSources();
    return rows
        .map(
          (Map<String, Object?> row) => BrandSource(
            merchantRaw: (row['merchant_raw'] as String?) ?? '',
            brand: (row['brand'] as String?) ?? '',
            count: (row['cnt'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<int> renameBrand({
    required String merchantRaw,
    required String from,
    required String to,
  }) async {
    final int updated = await _local.renameBrand(
      merchantRaw: merchantRaw,
      from: from,
      to: to,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (updated > 0) _notify();
    return updated;
  }

  @override
  Future<int> reclassifyByBrand({
    required String brand,
    required String category,
    required String subcategory,
    DateTime? onlyFrom,
  }) async {
    final int updated = await _local.reclassifyByBrand(
      brand: brand,
      category: category,
      subcategory: subcategory,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      onlyFromMillis: onlyFrom?.millisecondsSinceEpoch,
    );
    if (updated > 0) {
      AppLogger.i('브랜드 "$brand" 거래 $updated건 재분류 -> $category/$subcategory');
      _notify();
    }
    return updated;
  }

  @override
  Future<int> countAll() => _local.countAll();

  @override
  Future<List<Transaction>> findSettlementCandidates({
    required int depositAmount,
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
    final List<Map<String, Object?>> rows =
        await _local.findSettlementCandidates(
      depositAmount: depositAmount,
      fromMillis: from.millisecondsSinceEpoch,
      toMillis: to.millisecondsSinceEpoch,
      limit: limit,
    );
    return rows.map(TransactionDto.fromRow).toList();
  }

  @override
  void notifyChanged() => _notify();

  void dispose() {
    _changes.close();
  }
}
