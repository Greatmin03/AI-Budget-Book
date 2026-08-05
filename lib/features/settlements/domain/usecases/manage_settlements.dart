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
    final int? depositId = deposit.id;

    final Settlement settlement = await _settlements.add(
      transaction: transaction,
      counterparty: deposit.counterparty,
      amount: deposit.amount,
      settledAt: deposit.depositedAt,
      depositId: depositId,
    );

    if (depositId != null) {
      await _deposits.updateStatus(depositId, DepositStatus.linked);
    }

    AppLogger.i('입금 연결: ${deposit.counterparty} +${deposit.amount}원 '
        '-> ${transaction.displayName}');
    return settlement;
  }

  /// "정산이 아님" 으로 표시해 목록에서 내린다.
  Future<void> ignore(Deposit deposit) async {
    final int? id = deposit.id;
    if (id == null) return;
    await _deposits.updateStatus(id, DepositStatus.ignored);
  }
}
