import '../../../transactions/domain/entities/transaction.dart';
import '../entities/recurring_rule.dart';
import '../services/recurring_detector.dart';

abstract interface class RecurringRepository {
  /// 활성 규칙 목록(다음 예정일 빠른 순).
  Future<List<RecurringRule>> findActive();

  /// 전체 규칙(비활성 포함).
  Future<List<RecurringRule>> findAll();

  Future<RecurringRule?> findById(int id);

  /// 브랜드로 활성 규칙 찾기. 새 결제를 규칙에 연결할 때 쓴다.
  Future<RecurringRule?> findActiveByBrand(String brand);

  Future<RecurringRule> save(RecurringRule rule);

  /// 활성/비활성 전환.
  Future<void> setActive(int id, bool isActive);

  Future<void> delete(int id);

  /// 결제가 들어왔을 때 마지막 결제일과 다음 예정일을 갱신한다.
  Future<void> registerPayment({
    required int ruleId,
    required DateTime paidAt,
    required int amount,
  });

  /// 자동 감지 후보.
  ///
  /// 이미 규칙이 있는 브랜드는 제외된다.
  Future<List<RecurringCandidate>> detectCandidates({int lookbackMonths = 12});

  /// 규칙에 연결된 과거 거래를 소급 반영한다. 변경된 건수를 반환한다.
  Future<int> backfillTransactions(RecurringRule rule);

  /// 이 규칙으로 기록된 거래들.
  Future<List<Transaction>> transactionsOf(int ruleId, {int limit = 50});

  Stream<void> get changes;
}
