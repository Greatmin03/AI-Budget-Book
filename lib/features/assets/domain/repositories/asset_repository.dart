import '../../../../core/utils/date_range.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../entities/asset_transfer.dart';

abstract interface class AssetRepository {
  /// 거래를 자산 이동으로 표시하고 상세를 기록한다.
  ///
  /// 거래의 `is_asset_transfer` 플래그와 `asset_transfers` 행을 함께 쓴다.
  /// 두 값이 어긋나면 통계가 틀어지므로 반드시 이 경로로만 변경한다.
  Future<AssetTransfer> markTransaction({
    required int transactionId,
    required String fromAccount,
    required String toAccount,
    required int amount,
    required DateTime transferredAt,

    /// 돈이 들어가는 계좌. **이것이 있어야 그 계좌 잔액이 늘어난다.**
    /// null 이면 추적하지 않는 곳으로 나간 것으로 본다.
    int? toAccountId,
    String? note,

    /// 저축 / 청약 / 투자. 자산 통계에서 나눠 보여 주는 기준이다.
    AssetKind kind,
  });

  /// 자산 이동 표시를 해제한다(다시 소비로 취급).
  Future<void> unmarkTransaction(int transactionId);

  /// 거래에 연결된 자산 이동.
  Future<AssetTransfer?> findByTransaction(int transactionId);

  /// 기간 내 자산 이동 목록(최신순).
  Future<List<AssetTransfer>> findInRange(DateRange range);

  /// 계좌별 자산 현황.
  ///
  /// [range] 를 주지 않으면 전체 기간을 합산한다(적금 총 납입액).
  Future<AssetSummary> summary({DateRange? range});

  /// 사용자가 입력한 적 있는 계좌 이름(입력 편의용 제안).
  Future<List<String>> knownAccounts();

  Stream<void> get changes;
}
