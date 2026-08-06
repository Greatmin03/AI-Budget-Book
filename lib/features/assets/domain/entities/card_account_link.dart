/// 카드 이름 하나와 계좌의 연결.
///
/// 알림은 `KB국민카드` 같은 **카드 이름**만 준다. 그 카드가 어느 계좌에서
/// 빠져나가는지는 앱이 알 수 없으므로 사용자가 한 번 지정한다.
class CardAccountLink {
  const CardAccountLink({
    required this.cardName,
    required this.accountId,
    this.accountName,
    this.transactionCount = 0,
  });

  /// 알림에서 읽은 카드 이름. 이것이 키다.
  final String cardName;

  /// 연결된 계좌. null 이면 아직 연결하지 않은 것이다.
  final int? accountId;

  /// 표시용 계좌 이름.
  final String? accountName;

  /// 이 카드로 기록된 거래 수. 연결의 가치를 가늠하는 데 쓴다.
  final int transactionCount;

  bool get isLinked => accountId != null;

  @override
  String toString() =>
      'CardAccountLink($cardName -> ${accountName ?? '연결 안 됨'}, '
      '$transactionCount건)';
}
