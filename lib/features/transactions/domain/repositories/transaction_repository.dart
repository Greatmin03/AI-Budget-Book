import '../../../../core/utils/date_range.dart';
import '../entities/transaction.dart';

abstract interface class TransactionRepository {
  /// 거래를 저장한다.
  ///
  /// 같은 fingerprint 가 이미 있으면(중복 알림) `null` 을 반환하고 저장하지 않는다.
  Future<Transaction?> insert(Transaction transaction);

  Future<Transaction?> findById(int id);

  /// 특정 기간의 거래를 최신순으로.
  Future<List<Transaction>> findByRange(DateRange range);

  /// 사용자 확인이 필요한 거래(처음 보는 브랜드)를 오래된 순으로.
  ///
  /// 오래된 순인 이유: 먼저 발생한 것부터 처리하면 같은 브랜드의 뒤 건들이
  /// 브랜드 학습으로 한꺼번에 해소된다.
  Future<List<Transaction>> findNeedingReview({int limit = 100});

  /// 확인이 필요한 거래 수(대시보드 배지용).
  Future<int> countNeedingReview();

  /// 최근 거래 [limit] 건.
  Future<List<Transaction>> findRecent({int limit = 20});

  /// 사용자가 수정한 필드를 저장한다.
  Future<void> update(Transaction transaction);

  Future<void> delete(int id);

  /// 같은 브랜드의 거래들 분류를 일괄 변경한다(사용자 학습 전파).
  ///
  /// [onlyFrom] 이 주어지면 그 시각 이후 거래만 대상으로 한다.
  Future<int> reclassifyByBrand({
    required String brand,
    required String category,
    required String subcategory,
    DateTime? onlyFrom,
  });

  /// 같은 브랜드의 "분류 필요" 거래를 한 번에 해소한다.
  ///
  /// 사용자가 `춘천감자탕` 을 한 번 분류하면, 아직 확인하지 않은 같은 브랜드의
  /// 다른 거래들도 함께 정리된다.
  Future<int> resolveReviewForBrand({
    required String brand,
    required String category,
    required String subcategory,
  });

  Future<int> countAll();

  /// 아직 전액을 돌려받지 못한 거래(정산 후보).
  ///
  /// 남은 금액이 [depositAmount] 와 가까운 순으로 반환한다.
  Future<List<Transaction>> findSettlementCandidates({
    required int depositAmount,
    required DateTime from,
    required DateTime to,
    int limit = 10,
  });

  // ------------------------------------------------------- AI 분석 대기열
  /// AI 일괄 분석을 기다리는 거래(브랜드 순).
  Future<List<Transaction>> findAiPending({int limit = 500});

  /// 대기 건수. 배너에 "AI 분석 대기 N건" 으로 보여 준다.
  Future<int> countAiPending();

  /// 처리 중에 멈춘 거래를 다시 대기로 되돌린다.
  ///
  /// 일괄 분석 도중 앱이 죽으면 `processing` 표시가 남아 그 거래가 영구히
  /// 대기열에서 빠진다. 분석을 시작할 때마다 먼저 정리한다.
  Future<int> resetStuckAiProcessing();

  /// 브랜드 하나의 대기 상태를 바꾼다(처리 중 표시 / 실패 표시).
  Future<int> markAiStatusForBrand({
    required String brand,
    required AiStatus status,
  });

  /// AI 결과를 브랜드 단위로 확정한다.
  ///
  /// 같은 브랜드의 대기 거래를 한 번에 갱신하므로, 15번 결제한 브랜드도
  /// AI 호출은 1회다. 사용자가 직접 분류한 거래는 덮지 않는다.
  Future<int> applyAiClassificationForBrand({
    required String brand,
    required String category,
    required String subcategory,
  });

  /// 저장/수정/삭제가 일어날 때마다 이벤트가 흐른다. UI 갱신 트리거.
  Stream<void> get changes;

  /// 거래 자체는 그대로지만 파생 값(정산 합계 등)이 바뀌었을 때 알린다.
  void notifyChanged();
}
