/// 자산 이동 — 적금 납입, 계좌 간 이동.
///
/// 소비가 아니다. 돈이 사라진 것이 아니라 내 자산의 위치가 바뀐 것이다.
/// 따라서 소비 통계에서는 제외하고, 현금 흐름과 자산 현황에는 포함한다.
class AssetTransfer {
  const AssetTransfer({
    required this.fromAccount,
    required this.toAccount,
    this.toAccountId,
    required this.amount,
    required this.transferredAt,
    this.id,
    this.transactionId,
    this.note,
    this.createdAt,
  });

  final int? id;

  /// 연결된 거래. 알림 없이 수동으로 기록했다면 null.
  final int? transactionId;

  /// 보낸 곳. 예: `KB 입출금`
  final String fromAccount;

  /// 받는 곳. 예: `KB 청년미래적금`
  final String toAccount;

  /// 돈이 들어간 계좌. null 이면 추적하지 않는 곳이다.
  ///
  /// [toAccount] 는 표시용 문자열이고, 잔액 반영은 이 값으로 판단한다.
  final int? toAccountId;

  /// 이동 금액. 항상 양수.
  final int amount;

  final DateTime transferredAt;
  final String? note;
  final DateTime? createdAt;

  bool get isLinkedToTransaction => transactionId != null;

  AssetTransfer copyWith({int? id}) => AssetTransfer(
        id: id ?? this.id,
        transactionId: transactionId,
        fromAccount: fromAccount,
        toAccount: toAccount,
        amount: amount,
        transferredAt: transferredAt,
        note: note,
        createdAt: createdAt,
      );

  @override
  String toString() =>
      'AssetTransfer($fromAccount -> $toAccount, $amount원)';
}

/// 계좌별 자산 현황.
///
/// 별도의 계좌 테이블을 두지 않고 이동 내역을 합산해서 만든다.
/// (초기 잔액을 모르므로 "이동으로 쌓인 금액" 만 알 수 있다)
class AccountBalance {
  const AccountBalance({
    required this.account,
    required this.inflow,
    required this.outflow,
    required this.transferCount,
  });

  final String account;

  /// 이 계좌로 들어온 합계.
  final int inflow;

  /// 이 계좌에서 나간 합계.
  final int outflow;

  final int transferCount;

  /// 순 증가액. 적금이라면 지금까지 넣은 금액이다.
  int get net => inflow - outflow;
}

/// 자산 이동 요약(자산 현황 화면).
class AssetSummary {
  const AssetSummary({
    required this.totalTransferred,
    required this.balances,
  });

  const AssetSummary.empty()
      : totalTransferred = 0,
        balances = const <AccountBalance>[];

  /// 기간 내 이동 총액.
  final int totalTransferred;

  /// 계좌별 현황(순 증가액 내림차순).
  final List<AccountBalance> balances;

  bool get isEmpty => balances.isEmpty;
}
