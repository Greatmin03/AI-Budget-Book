import '../../../../core/constants/app_categories.dart';
import '../../../../core/constants/classification_source.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/domain/repositories/merchant_repository.dart';
import '../../../merchants/domain/services/brand_learning_policy.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../entities/brand_metadata.dart';
import '../entities/llm_health.dart';
import '../entities/merchant_classification.dart';
import '../repositories/brand_metadata_repository.dart';
import '../repositories/classifier_repository.dart';

/// 일괄 분석 결과.
class AiBatchResult {
  const AiBatchResult({
    required this.brandsProcessed,
    required this.transactionsUpdated,
    required this.llmCalls,
    required this.cacheHits,
    required this.failures,
    this.skippedReason,
  });

  const AiBatchResult.skipped(String reason)
      : brandsProcessed = 0,
        transactionsUpdated = 0,
        llmCalls = 0,
        cacheHits = 0,
        failures = 0,
        skippedReason = reason;

  /// 처리한 브랜드 수(거래 수가 아니다).
  final int brandsProcessed;

  /// 분류가 확정된 거래 수.
  final int transactionsUpdated;

  /// 실제 LLM 호출 횟수. **브랜드당 최대 1회.**
  final int llmCalls;

  /// 캐시(brand_metadata)로 해결해 LLM 을 부르지 않은 브랜드 수.
  final int cacheHits;

  /// 분류하지 못한 브랜드 수. `failed` 로 남아 재시도할 수 있다.
  final int failures;

  /// 아예 실행하지 못한 이유(꺼져 있음 / 연결 안 됨 / 대기 없음).
  final String? skippedReason;

  bool get didRun => skippedReason == null;
  bool get changedAnything => transactionsUpdated > 0;

  @override
  String toString() => skippedReason ??
      'AI 일괄 분석: 브랜드 $brandsProcessed개 · 거래 $transactionsUpdated건 · '
          'LLM 호출 $llmCalls회 · 캐시 $cacheHits회 · 실패 $failures개';
}

/// **AI 분류 대기열을 한 번에 처리한다.**
///
/// ## 왜 일괄 처리인가
/// 결제 순간에 Ollama 를 부르면, 노트북이 꺼져 있을 때마다 타임아웃을 기다리고
/// 배터리를 쓴다. 그래서 수집 단계에서는 저장만 하고 `ai_status = pending` 으로
/// 표시해 두었다가, Ollama 에 닿을 때 여기서 몰아서 처리한다.
///
/// ## 브랜드당 LLM 1회
/// `행복반점` 을 15번 결제해도 LLM 호출은 1회다.
///  1. 대기 거래를 **브랜드로 묶는다**
///  2. `brand_metadata` 캐시에 있으면 LLM 을 부르지 않는다
///  3. 부른 결과는 캐시에 저장하고, 같은 브랜드의 대기 거래를 한 번에 갱신한다
///
/// ## 실패는 남는다
/// 분류하지 못한 브랜드는 `failed` 로 표시되어 언제든 다시 시도할 수 있다.
/// 조용히 사라지면 사용자는 왜 미분류인지 알 수 없다.
class ProcessAiPendingQueue {
  const ProcessAiPendingQueue({
    required ClassifierRepository classifier,
    required TransactionRepository transactions,
    required BrandMetadataRepository metadata,
    required MerchantRepository merchants,
    required SettingsRepository settings,
    BrandLearningPolicy policy = const BrandLearningPolicy(),
  })  : _classifier = classifier,
        _transactions = transactions,
        _metadata = metadata,
        _merchants = merchants,
        _settings = settings,
        _policy = policy;

  final ClassifierRepository _classifier;
  final TransactionRepository _transactions;
  final BrandMetadataRepository _metadata;
  final MerchantRepository _merchants;
  final SettingsRepository _settings;
  final BrandLearningPolicy _policy;

  /// 한 번에 처리할 브랜드 수 상한.
  ///
  /// 로컬 LLM 은 브랜드당 수 초가 걸릴 수 있다. 수백 개를 한 번에 돌리면
  /// 사용자는 끝나지 않는 작업을 보게 된다. 남은 것은 다음 실행에서 처리된다.
  static const int maxBrandsPerRun = 40;

  /// 대기 건수. 배너에 그대로 쓴다.
  Future<int> pendingCount() => _transactions.countAiPending();

  /// Ollama 에 닿는지 확인한다. 배너를 보여 줄지 판단하는 데 쓴다.
  Future<LlmHealth> checkConnection() => _classifier.checkHealth();

  /// 대기열을 처리한다.
  ///
  /// [requireConnectionCheck] 를 false 로 주면 헬스체크를 건너뛴다
  /// (이미 확인한 직후 호출하는 경우).
  Future<AiBatchResult> call({bool requireConnectionCheck = true}) async {
    if (!_classifier.isEnabled) {
      return const AiBatchResult.skipped('AI 분류가 꺼져 있습니다.');
    }

    // 지난 실행이 도중에 끊겼다면 `processing` 표시가 남아 있다.
    // 되돌리지 않으면 그 거래는 다시는 대기열에 잡히지 않는다.
    await _transactions.resetStuckAiProcessing();

    final int pending = await _transactions.countAiPending();
    if (pending == 0) {
      return const AiBatchResult.skipped('분석할 거래가 없습니다.');
    }

    if (requireConnectionCheck) {
      final LlmHealth health = await _classifier.checkHealth();
      if (!health.isUsable) {
        return AiBatchResult.skipped('Ollama 에 연결할 수 없습니다: ${health.message}');
      }
    }

    final List<Transaction> queue = await _transactions.findAiPending();

    // 브랜드로 묶는다. 같은 브랜드는 한 번만 처리한다.
    final Map<String, List<Transaction>> byBrand = <String, List<Transaction>>{};
    for (final Transaction tx in queue) {
      final String brand = tx.brand.trim();
      if (brand.isEmpty) continue;
      byBrand.putIfAbsent(brand, () => <Transaction>[]).add(tx);
    }

    AppLogger.i('AI 일괄 분석 시작: 거래 $pending건 / 브랜드 ${byBrand.length}개');

    int brandsProcessed = 0;
    int transactionsUpdated = 0;
    int llmCalls = 0;
    int cacheHits = 0;
    int failures = 0;

    for (final MapEntry<String, List<Transaction>> entry in byBrand.entries) {
      if (brandsProcessed >= maxBrandsPerRun) {
        AppLogger.i('이번 실행 한도($maxBrandsPerRun개 브랜드) 도달. '
            '남은 브랜드는 다음 실행에서 처리합니다.');
        break;
      }
      brandsProcessed++;

      final String brand = entry.key;
      final Transaction sample = entry.value.first;

      // 이 브랜드가 AI 로 분류해도 되는 대상인지 다시 확인한다.
      // 대기열에 넣을 때 걸렀지만, 사용자가 그 사이 거래를 고쳤을 수 있다.
      final BrandLearningDecision decision = _policy.evaluate(
        method: sample.method,
        brand: brand,
        merchantRaw: sample.merchantRaw,
      );
      if (decision.stance != BrandLearningStance.allowed) {
        AppLogger.d('AI 분석 건너뜀($brand): ${decision.reason}');
        await _transactions.markAiStatusForBrand(
          brand: brand,
          status: AiStatus.none,
        );
        continue;
      }

      try {
        await _transactions.markAiStatusForBrand(
          brand: brand,
          status: AiStatus.processing,
        );

        final CategoryPair? cached = await _fromCache(brand);
        final CategoryPair? pair;
        if (cached != null) {
          cacheHits++;
          pair = cached;
          AppLogger.d('캐시로 해결($brand): $cached');
        } else {
          llmCalls++;
          pair = await _askLlm(brand: brand, sample: sample);
        }

        if (pair == null) {
          failures++;
          await _transactions.markAiStatusForBrand(
            brand: brand,
            status: AiStatus.failed,
          );
          continue;
        }

        transactionsUpdated += await _apply(
          brand: brand,
          pair: pair,
          sample: sample,
        );
      } on Object catch (e, stack) {
        // 한 브랜드가 실패해도 나머지는 계속 처리한다.
        AppLogger.e('AI 분석 실패($brand)', e, stack);
        failures++;
        await _transactions.markAiStatusForBrand(
          brand: brand,
          status: AiStatus.failed,
        );
      }
    }

    final AiBatchResult result = AiBatchResult(
      brandsProcessed: brandsProcessed,
      transactionsUpdated: transactionsUpdated,
      llmCalls: llmCalls,
      cacheHits: cacheHits,
      failures: failures,
    );
    AppLogger.i(result.toString());
    return result;
  }

  /// 캐시(brand_metadata)에 이미 답이 있으면 LLM 을 부르지 않는다.
  Future<CategoryPair?> _fromCache(String brand) async {
    final BrandMetadata? cached = await _metadata.find(brand);
    return cached?.pair;
  }

  /// LLM 에 한 번 묻는다. 실패하면 null.
  Future<CategoryPair?> _askLlm({
    required String brand,
    required Transaction sample,
  }) async {
    // 원본 거래명을 보낸다. 지점명까지 있으면 LLM 이 업종을 더 잘 맞춘다.
    // 이 요청은 **사용자가 지정한 로컬 Ollama 로만** 나간다.
    final MerchantClassification classification =
        await _classifier.classifyWithLlm(sample.merchantRaw);

    if (classification.isUnclassified) {
      AppLogger.i('AI 가 분류하지 못함: $brand');
      return null;
    }

    if (classification.confidence < _settings.current.minConfidenceToLearn) {
      AppLogger.i('확신도 미달로 보류($brand): '
          '${classification.confidence} < ${_settings.current.minConfidenceToLearn}');
      return null;
    }

    return CategoryTaxonomy.coerce(
      classification.category,
      classification.subcategory,
    );
  }

  /// 결과를 저장하고 같은 브랜드의 대기 거래를 한 번에 갱신한다.
  Future<int> _apply({
    required String brand,
    required CategoryPair pair,
    required Transaction sample,
  }) async {
    // 1) 브랜드 캐시. 다음부터는 LLM 없이 즉시 분류된다.
    await _metadata.save(
      BrandMetadata(
        brand: brand,
        normalizedBrand: TextNormalizer.normalize(brand),
        category: pair.category,
        subcategory: pair.subcategory,
        source: BrandMetadataSource.llm,
        lookedUpAt: DateTime.now(),
      ),
    );

    // 2) 가맹점 학습. 원본 거래명으로 캐시해 두면 같은 가게는 조회조차 안 한다.
    await _merchants.save(
      Merchant.unsaved(
        brand: brand,
        merchantName: sample.merchantRaw,
        normalizedName: TextNormalizer.normalize(sample.merchantRaw),
        category: pair.category,
        subcategory: pair.subcategory,
        source: ClassificationSource.llm,
        confidence: 1,
      ),
    );

    // 3) 브랜드 규칙으로 승격. 아직 본 적 없는 지점까지 자동 분류된다.
    //    설정에서 껐으면 하지 않는다.
    if (_settings.current.autoLearnBrandRule) {
      final String pattern = TextNormalizer.normalize(brand);
      // 너무 짧은 패턴은 엉뚱한 가맹점에 걸린다.
      if (pattern.length >= 3) {
        await _merchants.upsertBrandRule(
          BrandRule(
            pattern: pattern,
            brand: brand,
            category: pair.category,
            subcategory: pair.subcategory,
            source: ClassificationSource.llm,
          ),
        );
      }
    }

    // 4) 대기 거래 일괄 갱신 + pending 해제.
    return _transactions.applyAiClassificationForBrand(
      brand: brand,
      category: pair.category,
      subcategory: pair.subcategory,
    );
  }
}
