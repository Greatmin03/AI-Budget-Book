import '../../../../core/constants/classification_source.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../../parsing/domain/entities/parsed_payment.dart';
import '../../../settlements/domain/entities/settlement.dart';

/// 거래가 어디서 들어왔는가.
enum EntrySource {
  /// 결제 알림에서 자동 수집.
  notification('notification', '자동 수집'),

  /// 사용자가 직접 입력(현금, 중고거래, 누락분).
  manual('manual', '직접 입력');

  const EntrySource(this.code, this.label);

  final String code;
  final String label;

  bool get isManual => this == EntrySource.manual;

  static EntrySource fromCode(String? code) =>
      code == 'manual' ? EntrySource.manual : EntrySource.notification;
}

/// 지출인가 수입인가.
///
/// 알림으로 수집된 거래는 항상 지출이다. 수입은 직접 입력에서만 생긴다.
/// **수입은 소비 통계에 포함되지 않는다.**
enum TransactionDirection {
  expense('expense', '지출'),
  income('income', '수입');

  const TransactionDirection(this.code, this.label);

  final String code;
  final String label;

  bool get isIncome => this == TransactionDirection.income;

  static TransactionDirection fromCode(String? code) =>
      code == 'income' ? TransactionDirection.income : TransactionDirection.expense;
}

/// 자산 이동의 종류.
///
/// 소비 통계에서는 어느 쪽이든 제외되지만(내 돈이 남아 있다),
/// 자산 통계에서는 "저축 얼마 / 청약 얼마 / 투자 얼마" 로 나눠 보여 준다.
enum AssetKind {
  saving('saving', '저축'),
  housing('housing', '청약'),
  investment('investment', '투자'),
  other('other', '기타');

  const AssetKind(this.code, this.label);

  final String code;
  final String label;

  static AssetKind fromCode(String? code) {
    for (final AssetKind kind in AssetKind.values) {
      if (kind.code == code) return kind;
    }
    return AssetKind.other;
  }
}

/// AI 분류 대기 상태.
///
/// 결제 순간에는 AI 를 부르지 않는다. 사전/장소 API 로 해결되지 않은 거래만
/// [pending] 으로 쌓아 두고, Ollama 가 켜진 노트북이 붙었을 때 일괄 처리한다.
enum AiStatus {
  /// AI 가 필요 없다(이미 분류됨) 또는 대상이 아니다(이체 등).
  none('none', 'AI 불필요'),

  /// 분석 대기 중.
  pending('pending', '분석 대기'),

  /// 분석 중. 같은 브랜드를 두 번 호출하지 않기 위한 표시다.
  processing('processing', '분석 중'),

  /// 분석 완료.
  completed('completed', '분석 완료'),

  /// 분석 실패. 언제든 다시 시도할 수 있다.
  failed('failed', '분석 실패');

  const AiStatus(this.code, this.label);

  final String code;
  final String label;

  bool get isPending => this == AiStatus.pending;
  bool get isProcessing => this == AiStatus.processing;

  /// 다시 시도할 수 있는 상태인지.
  bool get isRetryable => this == AiStatus.failed || this == AiStatus.pending;

  static AiStatus fromCode(String? code) {
    for (final AiStatus status in AiStatus.values) {
      if (status.code == code) return status;
    }
    return AiStatus.none;
  }
}

/// 가계부의 한 줄(거래).
class Transaction {
  const Transaction({
    required this.merchantRaw,
    required this.brand,
    required this.amount,
    required this.category,
    required this.subcategory,
    required this.method,
    required this.paymentDatetime,
    required this.rawNotification,
    required this.fingerprint,
    required this.classificationSource,
    this.id,
    this.merchantId,
    this.cardName,
    this.installmentMonths = 0,
    this.isCancelled = false,
    this.sourcePackage,
    this.memo,
    this.needsReview = false,
    this.userDisplayName,
    this.tag,
    this.settledAmount = 0,
    this.recurringRuleId,
    this.isAssetTransfer = false,
    this.entrySource = EntrySource.notification,
    this.accountId,
    this.accountNumber,
    this.balanceAfter,
    this.mergedSources = const <String>[],
    this.cancelsTransactionId,
    this.assetKind,
    this.aiStatus = AiStatus.none,
    this.aiProcessedAt,
    this.direction = TransactionDirection.expense,
    this.account,
    this.projectId,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;

  /// 학습된 가맹점과의 연결(없을 수도 있다).
  final int? merchantId;

  /// 알림 원본의 거래명. **사용자 수정으로 덮어쓰지 않는다.**
  ///
  /// 카드 결제라면 가맹점명, 이체라면 상대방 이름이 들어 있다.
  final String merchantRaw;

  /// 브랜드명. 가맹점 결제에서만 학습 대상이 된다.
  final String brand;

  /// **부호 있는** 금액. 취소 거래는 음수.
  final int amount;

  final String category;
  final String subcategory;
  final PaymentMethodKind method;
  final String? cardName;
  final int installmentMonths;
  final bool isCancelled;
  final DateTime paymentDatetime;

  /// 원본 알림 전문(감사/재파싱용).
  final String rawNotification;

  final String? sourcePackage;
  final String? memo;

  /// 중복 저장 방지 키.
  final String fingerprint;

  final ClassificationSource classificationSource;

  /// 사용자가 카테고리를 한 번 골라 줘야 하는 거래(처음 보는 브랜드).
  ///
  /// 금액은 이미 기록되어 있으므로 통계에서 빠지지 않는다.
  /// 다만 분류가 `기타/미분류` 이거나 추측값이므로 확인이 필요하다.
  final bool needsReview;

  /// 사용자가 지정한 표시 이름. 예: `친구 대신 결제`
  ///
  /// 이체 거래에서 브랜드를 학습하지 않고도 목적을 남길 수 있게 하는 수단이다.
  final String? userDisplayName;

  /// 사용자 태그. 예: `회비`, `여행 경비`
  final String? tag;

  /// 이 거래에 붙은 정산 금액의 합(돌려받은 돈).
  ///
  /// 조회 시 `settlements` 를 합산해 채워 넣는다. 저장되는 컬럼이 아니다.
  final int settledAmount;

  /// 정기결제 규칙 연결(메타데이터). 없으면 일반 거래.
  final int? recurringRuleId;

  /// 자산 이동(적금 납입 등)인지.
  ///
  /// true 면 **소비 통계에서 제외**된다. 돈이 사라진 게 아니라
  /// 내 계좌 사이를 이동한 것이기 때문이다.
  final bool isAssetTransfer;

  /// 자동 수집 / 직접 입력.
  final EntrySource entrySource;

  /// 지출 / 수입.
  final TransactionDirection direction;

  /// 은행 알림이 알려 준 마스킹 계좌번호. 예: `942902-**-***245`
  final String? accountNumber;

  /// 이 거래 직후의 계좌 잔액(은행이 알려 준 실제 값).
  final int? balanceAfter;

  /// 이 취소가 되돌린 원결제. null 이면 아직 짝을 못 찾았다.
  ///
  /// 취소 알림에는 가맹점 이름이 없으므로 브랜드로 맞추지 않는다.
  final int? cancelsTransactionId;

  /// 취소인데 원결제를 찾지 못한 상태.
  ///
  /// 사용자가 나중에 직접 연결해야 한다. 그때까지 원결제는 통계에 남는다.
  bool get isUnmatchedCancellation =>
      isCancelled && amount < 0 && cancelsTransactionId == null;

  /// 이 거래를 만든 알림들의 패키지 이름.
  ///
  /// 같은 결제를 토스와 은행이 각각 알린 경우 둘 다 들어간다.
  final List<String> mergedSources;

  /// 사용한 계좌·수단 이름. 예: `KB 입출금`, `현금`
  ///
  /// 표시용이다. 잔액 반영 대상은 [accountId] 로 판단한다.
  final String? account;

  /// 잔액을 반영할 계좌. null 이면 자산에 영향을 주지 않는다.
  final int? accountId;

  /// 자산 이동의 종류. [isAssetTransfer] 가 true 일 때만 의미가 있다.
  final String? assetKind;

  /// AI 분류 대기 상태.
  final AiStatus aiStatus;

  /// AI 분석을 마친 시각.
  final DateTime? aiProcessedAt;

  /// 프로젝트(폴더) 연결. 카테고리와 별개다.
  final int? projectId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isManual => entrySource.isManual;

  /// 자산 이동의 종류. 자산 이동이 아니면 null.
  AssetKind? get assetKindValue =>
      isAssetTransfer ? AssetKind.fromCode(assetKind) : null;

  /// 계좌 잔액에 반영해야 하는 거래인지.
  bool get affectsAccountBalance => accountId != null;

  bool get isIncome => direction.isIncome;
  bool get hasProject => projectId != null;

  /// 정기결제로 등록된 거래인지.
  bool get isRecurring => recurringRuleId != null;

  /// 소비 통계에 포함되는 거래인지.
  ///
  /// 자산 이동(계좌 간 이동)과 수입은 소비가 아니다.
  bool get countsAsSpending => !isAssetTransfer && !isIncome;

  bool get isInstallment => installmentMonths > 0;

  /// **실제 부담 금액** = 결제 금액 - 돌려받은 금액.
  ///
  /// 통계와 대시보드는 이 값을 쓴다.
  /// 거래 목록과 카드 명세 대조에는 [amount] 를 쓴다.
  int get netAmount => amount - settledAmount;

  bool get hasSettlements => settledAmount != 0;

  SettlementStatus get settlementStatus {
    if (settledAmount == 0) return SettlementStatus.none;
    // 취소 거래(음수)는 부호를 뒤집어 비교한다.
    final int total = amount.abs();
    return settledAmount.abs() >= total
        ? SettlementStatus.completed
        : SettlementStatus.partial;
  }

  /// 아직 더 받을 수 있는 금액. 정산 후보 매칭에 쓴다.
  int get unsettledAmount {
    final int remaining = amount.abs() - settledAmount.abs();
    return remaining > 0 ? remaining : 0;
  }

  /// 이 거래의 거래명이 상대방(사람/계좌)을 가리키는가.
  bool get isTransfer => method.isTransfer;

  /// 목록에 표시할 이름.
  ///
  /// 우선순위: 사용자가 지정한 표시 이름 > 브랜드 > 원본 거래명.
  String get displayName {
    final String? custom = userDisplayName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return brand.trim().isEmpty ? merchantRaw : brand;
  }

  /// 표시 이름이 원본과 다를 때 원본을 함께 보여 주기 위한 보조 문구.
  ///
  /// 이체 거래에서 특히 중요하다. `친구 대신 결제` 만 보이면 누구에게 보낸
  /// 돈인지 알 수 없으므로 원본 거래명을 잃지 않게 한다.
  String? get secondaryName {
    final String primary = displayName;
    return primary == merchantRaw ? null : merchantRaw;
  }

  /// 사용자가 직접 분류를 고친 거래인지.
  bool get isUserClassified => classificationSource.isUserDefined;

  /// `copyWith` 에서 "값을 주지 않음" 과 "null 로 지움" 을 구분하기 위한 표식.
  static const Object _unset = Object();

  /// "이 값은 건드리지 마라" 를 조건부로 표현할 때 쓴다.
  ///
  /// `copyWith(account: cond ? value : Transaction.keep)` 처럼, null 이
  /// **지우기**를 뜻하는 필드에서 "그대로 두기" 와 구분하기 위한 표식이다.
  static const Object keep = _unset;

  /// [memo] 는 `null` 을 넘기면 메모를 **지운다**.
  /// (인자를 생략하면 기존 값을 유지한다)
  Transaction copyWith({
    int? id,
    int? merchantId,
    String? brand,
    int? amount,
    String? category,
    String? subcategory,
    Object? memo = _unset,
    Object? userDisplayName = _unset,
    Object? tag = _unset,
    ClassificationSource? classificationSource,
    DateTime? paymentDatetime,
    bool? needsReview,
    int? settledAmount,
    Object? recurringRuleId = _unset,
    bool? isAssetTransfer,
    Object? account = _unset,
    Object? accountId = _unset,
    Object? accountNumber = _unset,
    Object? balanceAfter = _unset,
    List<String>? mergedSources,
    Object? cancelsTransactionId = _unset,
    Object? assetKind = _unset,
    AiStatus? aiStatus,
    Object? aiProcessedAt = _unset,
    Object? projectId = _unset,
    TransactionDirection? direction,
    PaymentMethodKind? method,
    Object? cardName = _unset,
    EntrySource? entrySource,
  }) {
    return Transaction(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      merchantRaw: merchantRaw,
      brand: brand ?? this.brand,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      method: method ?? this.method,
      cardName: identical(cardName, _unset)
          ? this.cardName
          : cardName as String?,
      installmentMonths: installmentMonths,
      isCancelled: isCancelled,
      paymentDatetime: paymentDatetime ?? this.paymentDatetime,
      rawNotification: rawNotification,
      sourcePackage: sourcePackage,
      memo: identical(memo, _unset) ? this.memo : memo as String?,
      userDisplayName: identical(userDisplayName, _unset)
          ? this.userDisplayName
          : userDisplayName as String?,
      tag: identical(tag, _unset) ? this.tag : tag as String?,
      settledAmount: settledAmount ?? this.settledAmount,
      recurringRuleId: identical(recurringRuleId, _unset)
          ? this.recurringRuleId
          : recurringRuleId as int?,
      isAssetTransfer: isAssetTransfer ?? this.isAssetTransfer,
      entrySource: entrySource ?? this.entrySource,
      direction: direction ?? this.direction,
      account: identical(account, _unset) ? this.account : account as String?,
      accountId:
          identical(accountId, _unset) ? this.accountId : accountId as int?,
      accountNumber: identical(accountNumber, _unset)
          ? this.accountNumber
          : accountNumber as String?,
      balanceAfter: identical(balanceAfter, _unset)
          ? this.balanceAfter
          : balanceAfter as int?,
      mergedSources: mergedSources ?? this.mergedSources,
      cancelsTransactionId: identical(cancelsTransactionId, _unset)
          ? this.cancelsTransactionId
          : cancelsTransactionId as int?,
      assetKind:
          identical(assetKind, _unset) ? this.assetKind : assetKind as String?,
      aiStatus: aiStatus ?? this.aiStatus,
      aiProcessedAt: identical(aiProcessedAt, _unset)
          ? this.aiProcessedAt
          : aiProcessedAt as DateTime?,
      projectId:
          identical(projectId, _unset) ? this.projectId : projectId as int?,
      fingerprint: fingerprint,
      classificationSource: classificationSource ?? this.classificationSource,
      needsReview: needsReview ?? this.needsReview,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 같은 알림이 두 번 들어와도 중복 저장되지 않도록 하는 결정적 키.
  ///
  /// 해시를 쓰지 않는다. Dart 의 `String.hashCode` 는 실행 간 안정성이
  /// 보장되지 않으므로, 사람이 읽을 수 있는 결정적 문자열을 그대로 쓴다.
  /// 초 단위 오차를 흡수하기 위해 시각은 분 단위로 절삭한다.
  static String buildFingerprint({
    required String merchantRaw,
    required int signedAmount,
    required DateTime paymentDatetime,
    String? cardName,
  }) {
    final DateTime minute = DateTime(
      paymentDatetime.year,
      paymentDatetime.month,
      paymentDatetime.day,
      paymentDatetime.hour,
      paymentDatetime.minute,
    );
    final String merchantKey = TextNormalizer.normalize(merchantRaw);
    return '$merchantKey|$signedAmount|'
        '${minute.millisecondsSinceEpoch}|${cardName ?? ''}';
  }

  @override
  String toString() => 'Transaction($displayName, $amount원, '
      '$category/$subcategory, $paymentDatetime)';
}
