import 'notification_source_trait.dart';

/// 거래 유형.
///
/// **이 값이 브랜드 자동 학습 여부를 결정한다.**
///
/// 카드/간편결제의 거래명은 *가맹점*이므로 학습해도 안전하다.
/// 반면 이체/송금의 거래명은 *상대방*이다. 같은 사람에게 보내는 돈의 목적은
/// 매번 달라지므로(오늘 카페값, 내일 여행비) 브랜드로 학습하면 안 된다.
enum PaymentMethodKind {
  card('card', '카드결제'),
  easyPay('easy_pay', '간편결제'),

  /// 현금. 직접 입력에서만 생긴다(알림이 오지 않으므로).
  cash('cash', '현금'),

  accountTransfer('account_transfer', '계좌이체'),
  remittance('remittance', '송금'),
  unknown('unknown', '기타');

  const PaymentMethodKind(this.code, this.label);

  /// DB 에 저장되는 안정적인 코드. 표시 문구를 바꿔도 데이터가 깨지지 않는다.
  final String code;

  /// 화면에 표시할 이름.
  final String label;

  /// 거래명이 *가맹점*을 가리키는가.
  ///
  /// true 인 경우에만 브랜드 학습 후보가 된다.
  /// 현금은 사용자가 직접 가맹점을 입력한 것이므로 포함된다.
  bool get identifiesMerchant =>
      this == PaymentMethodKind.card ||
      this == PaymentMethodKind.easyPay ||
      this == PaymentMethodKind.cash;

  /// 거래명이 *상대방*(사람/계좌)을 가리키는가.
  bool get isTransfer =>
      this == PaymentMethodKind.accountTransfer ||
      this == PaymentMethodKind.remittance;

  /// v2 까지는 한국어 표시 문구를 그대로 저장했다.
  /// 기존 데이터를 읽을 수 있도록 옛 값도 함께 받아 준다.
  static const Map<String, PaymentMethodKind> _legacyLabels =
      <String, PaymentMethodKind>{
    '카드': PaymentMethodKind.card,
    '카드결제': PaymentMethodKind.card,
    '간편결제': PaymentMethodKind.easyPay,
    '현금': PaymentMethodKind.cash,
    '계좌출금': PaymentMethodKind.accountTransfer,
    '계좌이체': PaymentMethodKind.accountTransfer,
    '송금': PaymentMethodKind.remittance,
    '기타': PaymentMethodKind.unknown,
  };

  static PaymentMethodKind fromCode(String? raw) {
    if (raw == null || raw.isEmpty) return PaymentMethodKind.unknown;
    for (final PaymentMethodKind kind in PaymentMethodKind.values) {
      if (kind.code == raw) return kind;
    }
    return _legacyLabels[raw] ?? PaymentMethodKind.unknown;
  }
}

/// 알림 문자열에서 추출한 결제 사실.
///
/// 아직 카테고리 분류는 되어 있지 않다(가맹점 문자열만 확보한 상태).
class ParsedPayment {
  const ParsedPayment({
    required this.merchantRaw,
    required this.amount,
    required this.paymentDatetime,
    required this.method,
    required this.rawNotification,
    this.cardName,
    this.isCancellation = false,
    this.installmentMonths = 0,
    this.sourcePackage,
    this.accountNumber,
    this.balanceAfter,
  });

  /// 알림에서 뽑아낸 가맹점 문자열 원본. 예: `스타벅스 강남점`
  final String merchantRaw;

  /// 항상 양수. 취소 여부는 [isCancellation] 으로 표현한다.
  final int amount;

  final DateTime paymentDatetime;
  final PaymentMethodKind method;

  /// 감사(audit)를 위해 원본 알림 전문을 보관한다.
  final String rawNotification;

  /// 예: `KB국민카드`
  final String? cardName;

  /// 승인취소/환불 거래인지.
  final bool isCancellation;

  /// 0 = 일시불, 3 = 3개월 할부
  final int installmentMonths;

  final String? sourcePackage;

  /// 은행 알림이 알려 준 계좌번호. 예: `942902-**-***245`
  ///
  /// 마스킹된 형태 그대로 둔다. 어느 계좌에서 나갔는지 사람이 알아보는 데
  /// 쓰고, 그대로 외부로 나가지 않는다.
  final String? accountNumber;

  /// 이 거래 **직후**의 계좌 잔액.
  ///
  /// 은행이 알려 주는 실제 값이다. 앱이 계산한 잔액과 대조할 수 있는
  /// 유일한 근거이므로 버리지 않고 남긴다.
  final int? balanceAfter;

  /// 알림을 보낸 앱의 특성(브랜드가 정확한가, 계좌 정보를 주는가).
  NotificationSourceTrait get sourceTrait =>
      NotificationSourceTrait.of(sourcePackage);

  /// 가계부 합산에 사용하는 부호 있는 금액.
  int get signedAmount => isCancellation ? -amount : amount;

  /// 가맹점을 특정하지 못한 채 금액만 확보한 경우.
  bool get isMerchantUnknown => merchantRaw == unknownMerchantLabel;

  static const String unknownMerchantLabel = '미확인 가맹점';

  ParsedPayment copyWith({
    String? merchantRaw,
    String? accountNumber,
    int? balanceAfter,
    int? amount,
    DateTime? paymentDatetime,
    PaymentMethodKind? method,
    String? cardName,
    bool? isCancellation,
    int? installmentMonths,
  }) {
    return ParsedPayment(
      merchantRaw: merchantRaw ?? this.merchantRaw,
      amount: amount ?? this.amount,
      paymentDatetime: paymentDatetime ?? this.paymentDatetime,
      method: method ?? this.method,
      rawNotification: rawNotification,
      cardName: cardName ?? this.cardName,
      isCancellation: isCancellation ?? this.isCancellation,
      accountNumber: accountNumber ?? this.accountNumber,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      installmentMonths: installmentMonths ?? this.installmentMonths,
      sourcePackage: sourcePackage,
    );
  }

  @override
  String toString() => 'ParsedPayment($merchantRaw, $signedAmount원, '
      '$paymentDatetime, ${method.label}, card=$cardName)';
}

/// 알림에서 추출한 **입금** 사실.
///
/// 지출이 아니므로 거래로 기록하지 않는다. 정산(더치페이) 후보로만 쓰인다.
class ParsedDeposit {
  const ParsedDeposit({
    required this.counterparty,
    required this.amount,
    required this.depositedAt,
    required this.rawNotification,
    this.bankName,
    this.sourcePackage,
  });

  /// 보낸 사람. 예: `홍길동`
  final String counterparty;

  /// 입금액. 항상 양수.
  final int amount;

  final DateTime depositedAt;
  final String rawNotification;
  final String? bankName;
  final String? sourcePackage;

  @override
  String toString() =>
      'ParsedDeposit($counterparty +$amount원, $depositedAt)';
}

/// 파싱 결과. 실패 이유를 보존해 `ingest_failures` 에 남긴다.
sealed class ParseOutcome {
  const ParseOutcome();
}

class ParseSuccess extends ParseOutcome {
  const ParseSuccess(this.payment);

  final ParsedPayment payment;
}

/// 입금 알림이었다.
class ParseDepositOutcome extends ParseOutcome {
  const ParseDepositOutcome(this.deposit);

  final ParsedDeposit deposit;
}

/// 결제 알림이 아니라고 판단해 조용히 무시하는 경우(로그만 남김).
class ParseIgnored extends ParseOutcome {
  const ParseIgnored(this.reason);

  final String reason;
}

/// 결제 알림처럼 보이는데 추출에 실패한 경우(파서 개선 대상 → DB 보관).
class ParseFailed extends ParseOutcome {
  const ParseFailed(this.reason);

  final String reason;
}
