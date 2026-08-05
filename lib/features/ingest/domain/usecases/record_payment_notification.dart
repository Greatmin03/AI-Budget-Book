import '../../../../core/constants/classification_source.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../../classification/domain/entities/brand_metadata.dart';
import '../../../classification/domain/entities/merchant_classification.dart';
import '../../../classification/domain/services/rule_based_classifier.dart';
import '../../../classification/domain/usecases/lookup_brand_industry.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/domain/repositories/merchant_repository.dart';
import '../../../merchants/domain/services/brand_learning_policy.dart';
import '../../../notifications/domain/entities/raw_notification.dart';
import '../../../parsing/domain/entities/parsed_payment.dart';
import '../../../parsing/domain/services/payment_notification_parser.dart';
import '../../../recurring/domain/entities/recurring_rule.dart';
import '../../../recurring/domain/repositories/recurring_repository.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../../../settlements/domain/entities/deposit.dart';
import '../../../settlements/domain/repositories/settlement_repository.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../entities/ingest_result.dart';
import '../repositories/ingest_failure_repository.dart';

/// 알림 한 건 -> 가계부 한 줄. 파이프라인의 중심.
///
/// ```
/// 알림 -> 파싱 -> 브랜드 DB 조회
///                   ├─ 등록됨   -> 자동 분류
///                   └─ 미등록   -> "분류 필요" 로 저장 (사용자가 1회 선택)
///                                   └─ AI 분류가 켜져 있으면 그 선택을 LLM 이 대신한다
/// ```
///
/// **LLM 은 필수 요소가 아니다.** 기본값은 꺼짐이며, 꺼져 있어도 모든 결제가
/// 정상적으로 기록된다. 처음 보는 브랜드만 `needsReview` 로 표시되어
/// 사용자에게 한 번 물어보고, 그 선택이 학습되어 이후에는 자동 분류된다.
class RecordPaymentNotification {
  const RecordPaymentNotification({
    required PaymentNotificationParser parser,
    required MerchantRepository merchants,
    required TransactionRepository transactions,
    required IngestFailureRepository failures,
    required SettingsRepository settings,
    required DepositRepository deposits,
    required RecurringRepository recurring,
    LookupBrandIndustry? lookupIndustry,
    RuleBasedClassifier ruleBased = const RuleBasedClassifier(),
    BrandLearningPolicy policy = const BrandLearningPolicy(),
  })  : _policy = policy,
        _lookupBrandIndustry = lookupIndustry,
        _deposits = deposits,
        _recurring = recurring,
        _parser = parser,
        _merchants = merchants,
        _transactions = transactions,
        _failures = failures,
        _settings = settings,
        _ruleBased = ruleBased;

  final PaymentNotificationParser _parser;
  final MerchantRepository _merchants;

  final TransactionRepository _transactions;
  final IngestFailureRepository _failures;
  final SettingsRepository _settings;

  /// 사용자에게 보여 줄 "제안" 을 만드는 데 쓴다(확정 분류가 아니다).
  final RuleBasedClassifier _ruleBased;

  /// 이체/송금 거래명을 브랜드로 학습하지 않도록 막는 정책.
  final BrandLearningPolicy _policy;

  /// 입금 알림 저장소(정산 후보).
  final DepositRepository _deposits;

  /// 정기결제 규칙. 새 결제를 기존 규칙에 연결한다.
  final RecurringRepository _recurring;

  /// 장소 API 업종 조회. null 이면 이 단계를 건너뛴다.
  final LookupBrandIndustry? _lookupBrandIndustry;

  /// 업종 조회를 안전하게 감싼다. 실패해도 기록을 막지 않는다.
  ///
  /// **[BrandLearningPolicy] 가 학습을 허용한 거래명만 외부로 보낸다.**
  /// 이체/송금의 거래명은 상대방 이름이다. 그것을 장소 검색에 보내면
  ///  - 사람 이름이 기기 밖으로 나가고(로컬 우선 원칙 위반),
  ///  - `홍길동` 이라는 가게가 검색되어 엉뚱하게 자동 분류된다.
  ///
  /// 사람 이름처럼 보이는 경우(`discouraged`)도 보내지 않는다.
  /// 확실하지 않을 때 외부로 보내지 않는 쪽이 되돌릴 수 없는 실수를 막는다.
  Future<BrandMetadata?> _lookupIndustry({
    required ParsedPayment payment,
    required String merchantRaw,
  }) async {
    final LookupBrandIndustry? lookup = _lookupBrandIndustry;
    if (lookup == null) return null;

    final BrandLearningDecision decision = _policy.evaluate(
      method: payment.method,
      brand: payment.merchantRaw,
      merchantRaw: merchantRaw,
    );
    if (decision.stance != BrandLearningStance.allowed) {
      AppLogger.d('업종 조회 생략(${decision.reason ?? '정책'}): $merchantRaw');
      return null;
    }

    try {
      return await lookup(merchantRaw);
    } on Object catch (e, stack) {
      AppLogger.e('업종 조회 중 예외', e, stack);
      return null;
    }
  }

  Future<IngestResult> call(RawNotification notification) async {
    // ------------------------------------------------------------- 1) 파싱
    final ParseOutcome outcome = _parser.parse(notification);

    switch (outcome) {
      case ParseIgnored(:final String reason):
        AppLogger.d('알림 무시 ($reason): ${notification.title}');
        return IngestIgnored(reason);

      case ParseFailed(:final String reason):
        AppLogger.w('파싱 실패 ($reason): ${notification.combinedText}');
        await _failures.record(
          packageName: notification.packageName,
          title: notification.title,
          text: notification.text,
          postedAt: notification.postedAt,
          reason: reason,
        );
        return IngestFailed(reason);

      // 입금은 지출이 아니다. 거래로 만들지 않고 정산 후보로만 남긴다.
      case ParseDepositOutcome(:final ParsedDeposit deposit):
        return _recordDeposit(deposit);

      case ParseSuccess(:final ParsedPayment payment):
        return _process(payment);
    }
  }

  /// 입금 알림을 정산 후보로 저장한다.
  ///
  /// **브랜드 학습은 하지 않는다.** `홍길동` 은 브랜드가 아니다.
  /// 역할을 분리해 두면 이름을 오염 없이 정산 매칭에만 쓸 수 있다.
  Future<IngestResult> _recordDeposit(ParsedDeposit parsed) async {
    final Deposit? saved = await _deposits.insert(
      Deposit(
        counterparty: parsed.counterparty,
        amount: parsed.amount,
        depositedAt: parsed.depositedAt,
        rawNotification: parsed.rawNotification,
        sourcePackage: parsed.sourcePackage,
        bankName: parsed.bankName,
        fingerprint: Deposit.buildFingerprint(
          counterparty: parsed.counterparty,
          amount: parsed.amount,
          depositedAt: parsed.depositedAt,
        ),
      ),
    );

    if (saved == null) return const IngestDuplicate();

    return IngestDepositRecorded(
      counterparty: parsed.counterparty,
      amount: parsed.amount,
    );
  }

  Future<IngestResult> _process(ParsedPayment payment) async {
    // -------------------------------------------- 2) 가맹점 조회 / 3) 분류
    final _Resolution resolution = await _resolve(payment);

    // ------------------------------------------- 4) 정기결제 규칙 연결(메타데이터)
    final RecurringRule? rule = await _matchRecurringRule(
      brand: resolution.brand,
      amount: payment.amount,
    );

    // ---------------------------------------------------------- 5) 거래 저장
    final Transaction transaction = Transaction(
      recurringRuleId: rule?.id,
      merchantId: resolution.merchant?.id,
      merchantRaw: payment.merchantRaw,
      brand: resolution.brand,
      amount: payment.signedAmount,
      category: resolution.category,
      subcategory: resolution.subcategory,
      method: payment.method,
      cardName: payment.cardName,
      installmentMonths: payment.installmentMonths,
      isCancelled: payment.isCancellation,
      paymentDatetime: payment.paymentDatetime,
      rawNotification: payment.rawNotification,
      sourcePackage: payment.sourcePackage,
      fingerprint: Transaction.buildFingerprint(
        merchantRaw: payment.merchantRaw,
        signedAmount: payment.signedAmount,
        paymentDatetime: payment.paymentDatetime,
        cardName: payment.cardName,
      ),
      classificationSource: resolution.source,
      needsReview: resolution.needsReview,
      aiStatus: resolution.aiStatus,
    );

    final Transaction? saved = await _transactions.insert(transaction);
    if (saved == null) {
      return const IngestDuplicate();
    }

    // 매칭 횟수 갱신(통계의 "가장 많이 간 가게" 보조 지표)
    final int? merchantId = resolution.merchant?.id;
    if (merchantId != null) {
      await _merchants.registerHit(merchantId);
    }

    // 정기결제라면 마지막 결제일과 다음 예정일을 갱신한다.
    final int? ruleId = rule?.id;
    if (ruleId != null) {
      await _recurring.registerPayment(
        ruleId: ruleId,
        paidAt: payment.paymentDatetime,
        amount: payment.amount,
      );
    }

    return IngestSaved(saved);
  }

  /// 이 결제가 기존 정기결제 규칙에 해당하는지 확인한다.
  ///
  /// 브랜드가 같고 금액이 예상치와 비슷해야 한다.
  /// 넷플릭스에서 일회성 결제를 했다면 정기결제로 잡지 않는다.
  Future<RecurringRule?> _matchRecurringRule({
    required String brand,
    required int amount,
  }) async {
    if (brand.trim().isEmpty) return null;
    try {
      final RecurringRule? rule = await _recurring.findActiveByBrand(brand);
      if (rule == null) return null;
      return rule.matchesAmount(amount) ? rule : null;
    } on Object catch (e, stack) {
      // 정기결제 연결은 부가 기능이다. 실패해도 거래 기록을 막지 않는다.
      AppLogger.e('정기결제 규칙 조회 실패', e, stack);
      return null;
    }
  }

  /// 가맹점 문자열을 분류로 바꾼다.
  Future<_Resolution> _resolve(ParsedPayment payment) async {
    // 가맹점을 특정하지 못한 경우엔 학습하지 않는다(쓰레기 데이터 방지).
    // 대신 사용자 확인 대상으로 올려 직접 고칠 수 있게 한다.
    if (payment.isMerchantUnknown) {
      return const _Resolution(
        brand: ParsedPayment.unknownMerchantLabel,
        category: '기타',
        subcategory: '미분류',
        source: ClassificationSource.pending,
        needsReview: true,
      );
    }

    final MerchantLookup lookup = await _merchants.lookup(payment.merchantRaw);

    switch (lookup) {
      // 2-a) 이미 학습된 가맹점 → LLM 호출 없음
      case MerchantExactHit(:final Merchant merchant):
        AppLogger.d('가맹점 캐시 히트: ${merchant.brand}');
        return _Resolution(
          brand: merchant.brand,
          category: merchant.category,
          subcategory: merchant.subcategory,
          source: merchant.source,
          merchant: merchant,
        );

      // 2-b) 브랜드 사전으로 해결 → LLM 호출 없음. 이 가맹점명을 캐시에 학습해 둔다.
      case MerchantBrandHit(:final BrandRule rule, :final String? branch):
        AppLogger.d('브랜드 사전 히트: ${rule.brand}');
        final Merchant? learned = await _learn(
          payment: payment,
          brand: rule.brand,
          branch: branch,
          category: rule.category,
          subcategory: rule.subcategory,
          source: rule.source,
          confidence: 1,
        );
        return _Resolution(
          brand: rule.brand,
          category: rule.category,
          subcategory: rule.subcategory,
          source: rule.source,
          merchant: learned,
        );

      // 2-c) 처음 보는 브랜드
      case MerchantMiss(:final String merchantRaw):
        return _resolveUnknown(payment, merchantRaw);
    }
  }

  /// 등록되지 않은 브랜드를 처리한다.
  ///
  /// 기본 동작(AI 분류 꺼짐)은 **사용자에게 한 번 묻기** 다.
  /// 규칙 기반 추측은 사용자가 선택할 때의 *기본값*으로만 쓰이고,
  /// 확정 전까지 학습하지 않는다. 사용자가 고르지 않은 분류를
  /// 브랜드 DB 에 굳혀 버리면 이후 계속 잘못된 분류가 재사용된다.
  Future<_Resolution> _resolveUnknown(
    ParsedPayment payment,
    String merchantRaw,
  ) async {
    // 3단계: 장소 API 로 업종을 조회한다(브랜드당 최대 1회, 캐시 우선).
    // 실패하거나 키가 없으면 조용히 null 이 오고 다음 단계로 넘어간다.
    final BrandMetadata? industry = await _lookupIndustry(
      payment: payment,
      merchantRaw: merchantRaw,
    );
    if (industry != null && industry.isUsable) {
      AppLogger.i('업종 조회로 분류: $merchantRaw '
          '(${industry.industry}) -> '
          '${industry.category}/${industry.subcategory}');

      final Merchant? learned = await _learn(
        payment: payment,
        brand: industry.brand,
        branch: null,
        category: industry.category!,
        subcategory: industry.subcategory!,
        source: ClassificationSource.rule,
        confidence: 1,
      );

      return _Resolution(
        brand: industry.brand,
        category: industry.category!,
        subcategory: industry.subcategory!,
        source: ClassificationSource.rule,
        merchant: learned,
        // 외부 업종 정보로 분류했으므로 사용자에게 다시 묻지 않는다.
        needsReview: false,
      );
    }

    // 4단계: **AI 분석 대기열에 넣는다.**
    //
    // 결제 순간에는 LLM 을 호출하지 않는다. 예전에는 여기서 Ollama 를 직접
    // 불렀는데, 그러면 노트북이 꺼져 있을 때 매 결제마다 타임아웃을 기다리고
    // 배터리도 쓴다. 지금은 저장을 먼저 끝내고, Ollama 가 붙었을 때
    // 브랜드별로 한 번씩 일괄 처리한다.
    //
    // 대기열에 넣어도 거래는 이미 저장되어 있고 통계에도 들어간다.
    // 분류만 `미분류` 로 남는다.
    final MerchantClassification suggestion = _ruleBased.classify(merchantRaw);

    // 이체/송금·사람 이름은 AI 로도 분류할 수 없다(브랜드가 아니다).
    // 정책이 학습을 막는 거래는 대기열에도 넣지 않는다. 넣어 두면 매번
    // 실패하면서 대기 건수만 늘어난다.
    final BrandLearningDecision decision = _policy.evaluate(
      method: payment.method,
      brand: payment.merchantRaw,
      merchantRaw: merchantRaw,
    );
    final bool canUseAi = decision.stance == BrandLearningStance.allowed;

    AppLogger.i('처음 보는 브랜드: $merchantRaw → '
        '${canUseAi ? 'AI 분석 대기' : '사용자 분류 필요'} '
        '(제안: ${suggestion.category}/${suggestion.subcategory})');

    return _Resolution(
      brand: suggestion.brand,
      category: suggestion.category,
      subcategory: suggestion.subcategory,
      source: ClassificationSource.pending,
      needsReview: true,
      aiStatus: canUseAi ? AiStatus.pending : AiStatus.none,
    );
  }

  /// 가맹점을 `merchants` 테이블에 저장한다(= 학습).
  ///
  /// 확신도가 기준 미만이면 저장하지 않는다. 잘못된 분류를 캐시에 굳혀서
  /// 이후 계속 재사용하는 것이 가장 나쁜 결과이기 때문이다.
  Future<Merchant?> _learn({
    required ParsedPayment payment,
    required String brand,
    required String? branch,
    required String category,
    required String subcategory,
    required ClassificationSource source,
    required double confidence,
  }) async {
    // 이체/송금 거래명은 상대방 이름이다. 어떤 경우에도 학습하지 않는다.
    final BrandLearningDecision decision = _policy.evaluate(
      method: payment.method,
      brand: brand,
      merchantRaw: payment.merchantRaw,
    );
    if (decision.isBlocked) {
      AppLogger.d('학습 금지(${decision.reason}): ${payment.merchantRaw}');
      return null;
    }

    if (source == ClassificationSource.llm &&
        confidence < _settings.current.minConfidenceToLearn) {
      AppLogger.w('확신도 낮아 학습 생략: $brand '
          '(${confidence.toStringAsFixed(2)})');
      return null;
    }

    return _merchants.save(
      Merchant.unsaved(
        brand: brand,
        merchantName: payment.merchantRaw,
        normalizedName: TextNormalizer.normalize(payment.merchantRaw),
        branch: branch,
        category: category,
        subcategory: subcategory,
        source: source,
        confidence: confidence,
      ),
    );
  }

}

/// 분류 해결 결과(내부 전달용).
class _Resolution {
  const _Resolution({
    required this.brand,
    required this.category,
    required this.subcategory,
    required this.source,
    this.merchant,
    this.needsReview = false,
    this.aiStatus = AiStatus.none,
  });

  final String brand;
  final String category;
  final String subcategory;
  final ClassificationSource source;
  final Merchant? merchant;

  /// 사용자가 카테고리를 한 번 골라 줘야 하는지.
  final bool needsReview;

  /// AI 일괄 분석 대기 상태.
  ///
  /// 결제 순간에는 AI 를 부르지 않으므로, 여기서 정해지는 것은 "나중에
  /// 처리할 대상인가" 뿐이다.
  final AiStatus aiStatus;
}
