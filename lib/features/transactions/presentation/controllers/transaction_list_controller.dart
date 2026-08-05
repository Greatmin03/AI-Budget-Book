import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/apply_user_correction.dart';

/// 거래 목록 화면 상태.
///
/// 외부 상태관리 패키지 없이 [ChangeNotifier] 만 사용한다.
class TransactionListController extends ChangeNotifier {
  TransactionListController({
    required TransactionRepository repository,
    required ApplyUserCorrection applyUserCorrection,
  })  : _repository = repository,
        _applyCorrection = applyUserCorrection {
    // 파이프라인이 새 거래를 저장하면 목록을 자동 갱신한다.
    _subscription = _repository.changes.listen((_) => load());
  }

  final TransactionRepository _repository;
  final ApplyUserCorrection _applyCorrection;
  late final StreamSubscription<void> _subscription;

  DateRange _range = DateRange.month();
  List<Transaction> _transactions = const <Transaction>[];
  bool _isLoading = false;
  String? _error;

  DateRange get range => _range;
  List<Transaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 이 기간의 **소비** 합계(취소 차감 반영, 자산 이동·수입 제외).
  ///
  /// 통계 화면의 "지출" 과 같은 기준이다(`spendingOnly`).
  /// 화면마다 기준이 다르면 같은 기간에 다른 금액이 보인다.
  int get expenseTotal => _sumWhere((Transaction t) => t.countsAsSpending);

  /// 이 기간의 **수입** 합계.
  ///
  /// **지출과 절대 합산하지 않는다.** 수입도 양수로 저장되므로 그냥 더하면
  /// 300,000원 입금 + 15,000원 결제가 315,000원으로 보인다.
  int get incomeTotal => _sumWhere((Transaction t) => t.isIncome);

  /// 자산 이동(적금 납입 등) 합계. 소비도 수입도 아니다.
  int get assetTransferTotal =>
      _sumWhere((Transaction t) => t.isAssetTransfer && !t.isIncome);

  /// 순증가 = 수입 - 소비.
  int get netChange => incomeTotal - expenseTotal;

  bool get hasIncome => incomeTotal != 0;
  bool get hasAssetTransfers => assetTransferTotal != 0;

  int _sumWhere(bool Function(Transaction) test) => _transactions
      .where(test)
      .fold<int>(0, (int sum, Transaction t) => sum + t.amount);

  /// 분류 확인이 필요한 거래 수.
  int get needsReviewCount =>
      _transactions.where((Transaction t) => t.needsReview).length;

  /// 날짜별 + 그 안에서 지출/수입으로 묶은 목록.
  ///
  /// 하나의 리스트에 섞여 있으면 건수가 늘수록 읽기 어렵다.
  /// 날짜는 내림차순, 같은 날 안에서는 **지출 → 수입** 순이다.
  List<DaySection> get daySections {
    final Map<DateTime, List<Transaction>> byDay = groupedByDay;
    final List<DateTime> days = byDay.keys.toList()
      ..sort((DateTime a, DateTime b) => b.compareTo(a));

    return days.map((DateTime day) {
      final List<Transaction> items = byDay[day]!;
      return DaySection(
        day: day,
        expenses: items.where((Transaction t) => !t.isIncome).toList(),
        incomes: items.where((Transaction t) => t.isIncome).toList(),
      );
    }).toList();
  }

  /// 날짜별로 묶은 목록(섹션 헤더용).
  Map<DateTime, List<Transaction>> get groupedByDay {
    final Map<DateTime, List<Transaction>> grouped =
        <DateTime, List<Transaction>>{};
    for (final Transaction tx in _transactions) {
      final DateTime day = DateTime(
        tx.paymentDatetime.year,
        tx.paymentDatetime.month,
        tx.paymentDatetime.day,
      );
      grouped.putIfAbsent(day, () => <Transaction>[]).add(tx);
    }
    return grouped;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _transactions = await _repository.findByRange(_range);
    } on Object catch (e, stack) {
      AppLogger.e('거래 목록 조회 실패', e, stack);
      _error = '거래를 불러오지 못했습니다: $e';
      _transactions = const <Transaction>[];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> changeRange(DateRange range) async {
    if (range == _range) return;
    _range = range;
    await load();
  }

  /// 사용자가 분류를 수정했다.
  ///
  /// 학습 여부는 [ApplyUserCorrection] 안의 정책이 결정한다.
  /// 이체 거래라면 [applyToBrand] 를 true 로 넘겨도 학습되지 않는다.
  /// 반환값의 `learned` / `blockedReason` 으로 실제 결과를 알 수 있다.
  Future<CorrectionResult?> correct({
    required Transaction transaction,
    required String category,
    required String subcategory,
    String? brand,
    String? memo,
    String? displayName,
    String? tag,
    bool applyToBrand = false,
    bool reclassifyPast = false,
    int? amount,
    DateTime? paymentDatetime,
    TransactionDirection? direction,
    int? accountId,
    String? accountName,
    bool accountChanged = false,
  }) async {
    try {
      final CorrectionResult result = await _applyCorrection(
        transaction: transaction,
        category: category,
        subcategory: subcategory,
        brand: brand,
        memo: memo,
        displayName: displayName,
        tag: tag,
        applyToBrand: applyToBrand,
        reclassifyPastTransactions: reclassifyPast,
        amount: amount,
        paymentDatetime: paymentDatetime,
        direction: direction,
        accountId: accountId,
        accountName: accountName,
        accountChanged: accountChanged,
      );
      // repository.changes 로 load() 가 트리거되지만,
      // 즉시 반영을 위해 한 번 더 읽는다.
      await load();
      return result;
    } on Object catch (e, stack) {
      AppLogger.e('거래 수정 실패', e, stack);
      _error = '수정에 실패했습니다: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> delete(Transaction transaction) async {
    final int? id = transaction.id;
    if (id == null) return;
    await _repository.delete(id);
    await load();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// 한 날짜의 거래를 지출/수입으로 나눈 묶음.
class DaySection {
  const DaySection({
    required this.day,
    required this.expenses,
    required this.incomes,
  });

  final DateTime day;

  /// 나간 돈(자산 이동 포함). 목록에서는 함께 보여 준다.
  final List<Transaction> expenses;

  final List<Transaction> incomes;

  /// 이 날의 모든 거래(지출 먼저).
  List<Transaction> get all => <Transaction>[...expenses, ...incomes];

  bool get hasExpenses => expenses.isNotEmpty;
  bool get hasIncomes => incomes.isNotEmpty;

  /// 두 종류가 모두 있는 날에만 구분 라벨을 보여 준다.
  ///
  /// 지출만 있는 날에도 라벨을 넣으면 거의 모든 날에 붙어 오히려 지저분하다.
  bool get needsGroupLabels => hasExpenses && hasIncomes;
}
