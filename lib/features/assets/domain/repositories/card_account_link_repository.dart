import '../entities/card_account_link.dart';

/// 카드 이름 -> 계좌 연결.
///
/// 알림은 카드 이름만 준다. 그 카드가 어느 계좌에서 빠져나가는지 지정해야
/// 자동 수집된 거래가 잔액에 반영된다.
abstract interface class CardAccountLinkRepository {
  /// 이 카드에 연결된 계좌. 없으면 null.
  ///
  /// 알림 수집 시 거래마다 호출된다.
  Future<int?> accountIdFor(String cardName);

  /// 거래에 등장한 카드 이름 전체 + 연결 상태(거래 많은 순).
  Future<List<CardAccountLink>> findAll();

  /// 연결하고 **과거 거래에도 소급 적용**한다. 반영된 거래 수를 돌려준다.
  ///
  /// 이미 계좌가 지정된 거래는 건드리지 않는다.
  Future<int> link({required String cardName, required int accountId});

  /// 연결을 해제하고 소급 적용도 되돌린다.
  Future<int> unlink(String cardName);
}
