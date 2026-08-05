import '../../../../core/utils/date_range.dart';
import '../entities/account.dart';

abstract interface class AccountRepository {
  /// 자산 화면 데이터(종류별 묶음 + 총액 + 전월 대비).
  Future<AssetOverview> overview();

  Future<List<Account>> findAll({bool includeInactive = false});

  Future<Account?> findById(int id);

  Future<Account> save(Account account);

  Future<void> delete(int id);

  /// 잔액만 갱신한다. 갱신 시 스냅샷도 함께 남긴다.
  Future<void> updateBalance({required int id, required int balance});

  /// 현재 모든 계좌 잔액을 스냅샷으로 기록한다.
  ///
  /// 자산 추이는 이 기록을 비교해서 계산한다.
  Future<void> recordSnapshot();

  /// 기간 내 잔액 변화(수입 +, 지출 -, 자산 이동 0).
  ///
  /// `오늘 -15,000` / `이번 주 -82,000` 처럼 보여 주는 값이다.
  /// [accountId] 를 주면 그 계좌만 계산한다.
  Future<int> balanceChangeInRange(DateRange range, {int? accountId});

  /// 계좌 이름 목록(다른 화면의 입력 제안용).
  Future<List<String>> names();

  Stream<void> get changes;
}
