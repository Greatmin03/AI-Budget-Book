/// 입금 알림 한 건.
///
/// **지출이 아니므로 `transactions` 에 넣지 않는다.**
/// 정산 후보로만 쓰이고, 사용자가 거래에 연결하면 [Settlement] 이 생성된다.
///
/// 브랜드 학습에는 절대 사용하지 않는다. `홍길동` 은 브랜드가 아니다.
class Deposit {
  const Deposit({
    required this.counterparty,
    required this.amount,
    required this.depositedAt,
    required this.rawNotification,
    required this.fingerprint,
    this.id,
    this.sourcePackage,
    this.bankName,
    this.status = DepositStatus.pending,
    this.createdAt,
  });

  final int? id;

  /// 보낸 사람. 예: `홍길동`
  final String counterparty;

  /// 입금액. 항상 양수.
  final int amount;

  final DateTime depositedAt;
  final String rawNotification;
  final String fingerprint;
  final String? sourcePackage;
  final String? bankName;
  final DepositStatus status;
  final DateTime? createdAt;

  bool get isPending => status == DepositStatus.pending;

  Deposit copyWith({int? id, DepositStatus? status}) {
    return Deposit(
      id: id ?? this.id,
      counterparty: counterparty,
      amount: amount,
      depositedAt: depositedAt,
      rawNotification: rawNotification,
      fingerprint: fingerprint,
      sourcePackage: sourcePackage,
      bankName: bankName,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  /// 같은 입금 알림이 두 번 들어와도 한 번만 저장되도록 하는 결정적 키.
  static String buildFingerprint({
    required String counterparty,
    required int amount,
    required DateTime depositedAt,
  }) {
    final DateTime minute = DateTime(
      depositedAt.year,
      depositedAt.month,
      depositedAt.day,
      depositedAt.hour,
      depositedAt.minute,
    );
    return '${counterparty.replaceAll(' ', '')}|$amount|'
        '${minute.millisecondsSinceEpoch}';
  }

  @override
  String toString() => 'Deposit($counterparty +$amount, ${status.name})';
}

enum DepositStatus {
  /// 아직 거래에 연결되지 않았다.
  pending('연결 대기'),

  /// 거래에 연결되어 정산으로 반영되었다.
  linked('연결됨'),

  /// 사용자가 "정산이 아님" 으로 표시했다.
  ignored('무시'),
  ;

  const DepositStatus(this.label);

  final String label;

  static DepositStatus fromCode(String? code) {
    for (final DepositStatus status in DepositStatus.values) {
      if (status.name == code) return status;
    }
    return DepositStatus.pending;
  }
}
