import '../../../../core/constants/app_categories.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../entities/deposit.dart';
import '../entities/settlement.dart';
import '../repositories/settlement_repository.dart';

/// 정산을 직접 추가/삭제한다.
///
/// 원본 거래 금액은 절대 건드리지 않는다. 정산은 별도 레코드로만 쌓인다.
class ManageSettlements {
  const ManageSettlements({
    required SettlementRepository settlements,
    required TransactionRepository transactions,
  })  : _settlements = settlements,
        _transactions = transactions;

  final SettlementRepository _settlements;
  final TransactionRepository _transactions;

  /// 정산 추가.
  ///
  /// 거래 금액을 초과하는 정산도 막지 않는다(초과 입금이 실제로 있을 수 있다).
  /// 다만 [amount] 는 양수여야 한다.
  Future<Settlement> add({
    required Transaction transaction,
    required String counterparty,
    required int amount,
    DateTime? settledAt,
    String? memo,
    int? depositId,
  }) async {
    final int? transactionId = transaction.id;
    if (transactionId == null) {
      throw ArgumentError('저장되지 않은 거래에는 정산을 붙일 수 없습니다.');
    }
    if (amount <= 0) {
      throw ArgumentError('정산 금액은 0보다 커야 합니다.');
    }

    final Settlement saved = await _settlements.add(
      Settlement(
        transactionId: transactionId,
        counterparty: counterparty.trim().isEmpty ? '미지정' : counterparty.trim(),
        amount: amount,
        settledAt: settledAt ?? DateTime.now(),
        depositId: depositId,
        memo: memo,
      ),
    );

    // 거래 목록/통계가 실제 부담 금액을 다시 계산하도록 알린다.
    _transactions.notifyChanged();
    return saved;
  }

  Future<void> remove(int settlementId) async {
    await _settlements.remove(settlementId);
    _transactions.notifyChanged();
  }

  /// 이 입금으로 만들어진 정산을 모두 지운다.
  Future<int> removeByDeposit(int depositId) async {
    final int removed = await _settlements.removeByDeposit(depositId);
    if (removed > 0) _transactions.notifyChanged();
    return removed;
  }

  Future<List<Settlement>> forTransaction(int transactionId) =>
      _settlements.findByTransaction(transactionId);

  /// 여러 사람에게 균등 분할한 정산을 한 번에 만든다.
  ///
  /// 예: 30,000원을 3명이 나눠 냈다면 본인 몫을 뺀 2명분을 정산으로 넣는다.
  /// 나누어떨어지지 않는 금액은 마지막 사람에게 몰아준다(합계가 어긋나면 안 된다).
  Future<List<Settlement>> splitEvenly({
    required Transaction transaction,
    required List<String> counterparties,
    required int totalPeople,
  }) async {
    if (counterparties.isEmpty) return const <Settlement>[];
    if (totalPeople <= 1) {
      throw ArgumentError('총 인원은 2명 이상이어야 합니다.');
    }

    final int total = transaction.amount.abs();
    final int share = total ~/ totalPeople;
    final int remainder = total - share * totalPeople;

    final List<Settlement> created = <Settlement>[];
    for (int i = 0; i < counterparties.length; i++) {
      // 남는 1~2원은 마지막 정산에 더해 총액이 맞도록 한다.
      final bool isLast = i == counterparties.length - 1;
      final int amount = share + (isLast ? remainder : 0);
      if (amount <= 0) continue;

      created.add(
        await add(
          transaction: transaction,
          counterparty: counterparties[i],
          amount: amount,
        ),
      );
    }

    AppLogger.i('균등 분할 정산 ${created.length}건 생성 '
        '(총 $total원 / $totalPeople명)');
    return created;
  }
}

/// 입금 후보를 미정산 거래와 연결한다.
class LinkDepositToTransaction {
  const LinkDepositToTransaction({
    required DepositRepository deposits,
    required ManageSettlements settlements,
    required TransactionRepository transactions,
  })  : _deposits = deposits,
        _settlements = settlements,
        _transactions = transactions;

  final DepositRepository _deposits;
  final ManageSettlements _settlements;
  final TransactionRepository _transactions;

  /// 입금 시점 이전 며칠까지의 거래를 후보로 볼지.
  static const int candidateWindowDays = 30;

  /// 이 입금과 연결할 만한 거래 후보.
  ///
  /// 아직 전액을 돌려받지 못한 거래 중, 남은 금액이 입금액과 가까운 순으로.
  Future<List<Transaction>> findCandidates(Deposit deposit) {
    return _transactions.findSettlementCandidates(
      depositAmount: deposit.amount,
      from: deposit.depositedAt.subtract(
        const Duration(days: candidateWindowDays),
      ),
      // 결제보다 먼저 입금될 수도 있으니 약간의 여유를 준다.
      to: deposit.depositedAt.add(const Duration(days: 1)),
      limit: 10,
    );
  }

  /// 연결 확정. 정산을 만들고 입금을 `linked` 로 표시한다.
  Future<Settlement> link({
    required Deposit deposit,
    required Transaction transaction,
  }) async {
    final DepositAllocation result = await linkMany(
      deposit: deposit,
      transactions: <Transaction>[transaction],
    );
    return result.settlements.single;
  }

  /// **한 입금을 여러 거래에 나눠 붙인다.**
  ///
  /// 친구가 한 번에 보낸 돈이 결제 두 건을 덮는 경우가 흔하다. 하나만 고를 수
  /// 있으면 나머지는 영영 미정산으로 남아 실제 부담이 부풀어 보인다.
  ///
  /// 배분은 **고른 순서대로 남은 금액만큼** 채운다. 거래마다 금액을 손으로
  /// 넣게 하면 합계가 입금액과 어긋나기 쉽고, 어긋난 것을 사용자가 알아채기도
  /// 어렵다. 순서대로 채우면 합계가 절대 입금액을 넘지 않는다.
  Future<DepositAllocation> linkMany({
    required Deposit deposit,
    required List<Transaction> transactions,
  }) async {
    if (transactions.isEmpty) {
      throw ArgumentError('연결할 거래를 최소 하나 골라야 합니다.');
    }

    final int? depositId = deposit.id;
    final List<Settlement> created = <Settlement>[];
    int remaining = deposit.amount;

    for (final Transaction transaction in transactions) {
      if (remaining <= 0) break;

      // 이미 정산된 만큼은 빼고 남은 부담까지만 채운다.
      // 넘겨서 붙이면 그 거래의 부담이 음수가 된다.
      final int room = transaction.unsettledAmount;
      final int amount = room < remaining ? room : remaining;
      if (amount <= 0) continue;

      created.add(
        await _settlements.add(
          transaction: transaction,
          counterparty: deposit.counterparty,
          amount: amount,
          settledAt: deposit.depositedAt,
          depositId: depositId,
        ),
      );
      remaining -= amount;
    }

    if (created.isEmpty) {
      throw StateError('고른 거래에 남은 정산 금액이 없습니다.');
    }

    if (depositId != null) {
      await _deposits.updateStatus(depositId, DepositStatus.linked);
    }
    await _markAsSettlementIncome(deposit);

    AppLogger.i('입금 연결: ${deposit.counterparty} +${deposit.amount}원 '
        '-> 거래 ${created.length}건'
        '${remaining > 0 ? ' (남은 $remaining원은 배분되지 않음)' : ''}');

    return DepositAllocation(settlements: created, unallocated: remaining);
  }

  /// 이 입금으로 만들어진 수입 거래를 `정산` 분류로 옮긴다.
  ///
  /// 정산으로 확정된 순간 그 돈은 **소득이 아니게 된다.** 이미 원결제의
  /// `settlements` 로 내 부담이 줄었으므로, 수입으로도 세면 같은 돈을 두 번
  /// 세는 것이 된다.
  ///
  /// 거래를 지우지는 않는다. "이번 달에 얼마가 들어왔나" 에는 여전히 답해야
  /// 하고, 연결을 잘못했을 때 되돌릴 근거도 남아야 한다.
  Future<void> _markAsSettlementIncome(Deposit deposit) async {
    final int? transactionId = deposit.transactionId;
    if (transactionId == null) return;

    try {
      final Transaction? income = await _transactions.findById(transactionId);
      if (income == null) return;

      await _transactions.update(
        income.copyWith(
          category: CategoryTaxonomy.settlementCategory,
          subcategory: '더치페이',
          needsReview: false,
        ),
      );
    } on Object catch (e, stack) {
      // 분류 이동 실패가 정산 자체를 막아서는 안 된다.
      AppLogger.e('정산 수입 분류 이동 실패', e, stack);
    }
  }

  /// "정산이 아님" 으로 표시해 목록에서 내린다.
  Future<void> ignore(Deposit deposit) async {
    final int? id = deposit.id;
    if (id == null) return;
    await _deposits.updateStatus(id, DepositStatus.ignored);
  }

  /// 내렸던 입금을 다시 후보로 올린다.
  ///
  /// 목록에서 내리는 버튼은 한 번만 누르면 되고 확인도 없다. 잘못 누르는
  /// 일이 실제로 생기므로 되돌릴 수 있어야 한다.
  Future<void> restore(Deposit deposit) async {
    final int? id = deposit.id;
    if (id == null) return;
    await _deposits.updateStatus(id, DepositStatus.pending);
    AppLogger.i('입금 되돌리기: ${deposit.counterparty} +${deposit.amount}원');
  }

  /// **연결을 되돌린다.**
  ///
  /// 잘못 연결하는 일은 반드시 생긴다. 되돌릴 수 없으면 사용자는 틀린 숫자를
  /// 안고 살거나 거래를 지워야 한다 — 둘 다 나쁘다.
  ///
  /// 세 가지를 원래대로 돌린다.
  ///  - 이 입금으로 만든 정산 전부 삭제 (거래의 부담이 되돌아온다)
  ///  - 입금을 다시 `pending` 으로 (후보 목록에 올라온다)
  ///  - 수입 거래를 `정산` 에서 빼고 다시 사용자에게 묻는다
  ///
  /// 거래 자체는 지우지 않는다. 원본은 어느 경로로도 사라지지 않는다.
  Future<int> unlink(Deposit deposit) async {
    final int? depositId = deposit.id;
    if (depositId == null) return 0;

    final int removed = await _settlements.removeByDeposit(depositId);
    await _deposits.updateStatus(depositId, DepositStatus.pending);
    await _restoreIncomeClassification(deposit);

    AppLogger.i('입금 연결 해제: ${deposit.counterparty} '
        '+${deposit.amount}원 (정산 $removed건 삭제)');
    return removed;
  }

  /// 정산으로 옮겼던 수입 거래를 원래대로 되돌린다.
  ///
  /// `정산` 으로 둔 채 연결만 풀면 그 돈은 수입에도 안 잡히고 정산도 아닌
  /// 상태가 된다. 어느 통계에도 없는 돈이 생긴다.
  Future<void> _restoreIncomeClassification(Deposit deposit) async {
    final int? transactionId = deposit.transactionId;
    if (transactionId == null) return;

    try {
      final Transaction? income = await _transactions.findById(transactionId);
      if (income == null) return;
      if (income.category != CategoryTaxonomy.settlementCategory) return;

      await _transactions.update(
        income.copyWith(
          category: CategoryTaxonomy.etcCategory,
          subcategory: '미분류',
          // 무엇으로 들어온 돈인지 다시 사용자가 고른다.
          needsReview: true,
        ),
      );
    } on Object catch (e, stack) {
      AppLogger.e('수입 분류 복원 실패', e, stack);
    }
  }
}

/// 입금 하나를 거래들에 나눠 붙인 결과.
class DepositAllocation {
  const DepositAllocation({
    required this.settlements,
    required this.unallocated,
  });

  final List<Settlement> settlements;

  /// 고른 거래를 다 채우고도 남은 금액.
  ///
  /// 0이 아니면 그 돈은 정산이 아니라 다른 성격일 수 있다. 조용히 마지막
  /// 거래에 몰아붙이지 않고 **남았다는 사실을 알린다** — 부담을 실제보다
  /// 적게 보이게 만드는 쪽이 더 나쁘다.
  final int unallocated;

  int get total =>
      settlements.fold<int>(0, (int sum, Settlement s) => sum + s.amount);

  bool get isFullyAllocated => unallocated == 0;
}
