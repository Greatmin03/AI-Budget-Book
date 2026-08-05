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
