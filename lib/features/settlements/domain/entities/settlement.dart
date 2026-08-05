/// 정산(더치페이) 한 건 — "이 거래에서 누가 얼마를 돌려줬다".
///
/// 거래 금액을 고치는 대신 이 레코드를 붙인다.
/// 덕분에 거래 금액은 카드 명세와 언제나 일치한다.
class Settlement {
  const Settlement({
    required this.transactionId,
    required this.counterparty,
    required this.amount,
    required this.settledAt,
    this.id,
    this.depositId,
    this.memo,
    this.createdAt,
  });

  final int? id;
  final int transactionId;

  /// 정산해 준 사람. 예: `김철수`
  final String counterparty;

  /// 받은 금액. 항상 양수.
  final int amount;

  final DateTime settledAt;

  /// 입금 알림에서 자동 생성된 경우 그 입금 건의 id.
  final int? depositId;

  final String? memo;
  final DateTime? createdAt;

  /// 입금 알림으로 자동 연결된 정산인지.
  bool get isAutoLinked => depositId != null;

  Settlement copyWith({
    int? id,
    String? counterparty,
    int? amount,
    DateTime? settledAt,
    String? memo,
  }) {
    return Settlement(
      id: id ?? this.id,
      transactionId: transactionId,
      counterparty: counterparty ?? this.counterparty,
      amount: amount ?? this.amount,
      settledAt: settledAt ?? this.settledAt,
      depositId: depositId,
      memo: memo ?? this.memo,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'Settlement($counterparty +$amount, tx=$transactionId)';
}

/// 거래의 정산 진행 상태.
enum SettlementStatus {
  /// 정산 없음.
  none('정산 없음'),

  /// 일부만 돌려받았다.
  partial('부분 정산'),

  /// 전액 돌려받았다(실제 부담 0).
  completed('정산 완료');

  const SettlementStatus(this.label);

  final String label;

  bool get hasAny => this != SettlementStatus.none;
}
