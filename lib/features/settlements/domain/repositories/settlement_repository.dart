import '../entities/deposit.dart';
import '../entities/settlement.dart';

abstract interface class SettlementRepository {
  /// 거래에 붙은 정산 목록.
  Future<List<Settlement>> findByTransaction(int transactionId);

  /// 여러 거래의 정산을 한 번에 가져온다(목록 화면용).
  Future<Map<int, List<Settlement>>> findByTransactions(
    List<int> transactionIds,
  );

  /// 정산 추가. 저장된 정산을 반환한다.
  Future<Settlement> add(Settlement settlement);

  Future<void> remove(int settlementId);

  /// 이 입금으로 만들어진 정산들.
  Future<List<Settlement>> findByDeposit(int depositId);

  /// 이 입금으로 만들어진 정산을 모두 지운다. 지운 개수를 돌려준다.
  Future<int> removeByDeposit(int depositId);

  /// 특정 기간에 돌려받은 금액 합계(통계 표시용).
  Future<int> totalSettledInRange(int fromMillis, int toExclusiveMillis);

  /// 변경 알림. 거래 목록/통계 갱신 트리거.
  Stream<void> get changes;
}

abstract interface class DepositRepository {
  /// 입금 저장. 중복(fingerprint)이면 `null`.
  Future<Deposit?> insert(Deposit deposit);

  /// 아직 거래에 연결되지 않은 입금 목록(최신순).
  Future<List<Deposit>> findPending({int limit = 50});

  /// 이미 거래에 연결된 입금(최신순). 연결을 되돌릴 때 쓴다.
  Future<List<Deposit>> findLinked({int limit = 50});

  Future<int> countPending();

  Future<Deposit?> findById(int id);

  Future<void> updateStatus(int depositId, DepositStatus status);

  Stream<void> get changes;
}
