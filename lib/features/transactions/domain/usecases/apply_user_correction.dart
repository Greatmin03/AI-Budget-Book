import '../../../../core/constants/classification_source.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/domain/repositories/merchant_repository.dart';
import '../../../classification/domain/repositories/brand_metadata_repository.dart';
import '../../../merchants/domain/services/brand_learning_policy.dart';
import '../../../parsing/domain/entities/parsed_payment.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// 사용자 수정 결과.
class CorrectionResult {
  const CorrectionResult({
    required this.transaction,
    required this.learned,
    this.blockedReason,
  });

  final Transaction transaction;

  /// 브랜드 학습이 실제로 일어났는지.
  final bool learned;

  /// 학습하지 않은 이유(정책상 금지된 경우).
  final String? blockedReason;
}

/// 사용자가 거래를 수정하면 그 내용을 반영한다.
///
/// 학습 여부는 [BrandLearningPolicy] 가 결정한다. 이 유즈케이스는 정책을
/// 우회할 수 없다.
///
/// ## 카드/간편결제 (가맹점 결제)
/// 거래명이 가맹점을 뜻하므로 학습한다.
/// `메가MGC커피 춘천후평점` -> `메가커피` 를 배우면 다른 지점도 자동 분류된다.
///
/// ## 계좌이체 / 송금
/// 거래명이 상대방을 뜻하므로 **어떤 학습도 하지 않는다.**
/// 이번 거래의 분류/표시 이름/태그만 바꾼다.
/// `000 스마트폰 -> 메가커피` 를 규칙으로 저장해 버리면 이후 그 상대방에게
/// 보내는 모든 송금이 메가커피로 분류된다.
class ApplyUserCorrection {
  const ApplyUserCorrection({
    required MerchantRepository merchants,
    required TransactionRepository transactions,
    BrandMetadataRepository? brandMetadata,
    BrandLearningPolicy policy = const BrandLearningPolicy(),
  })  : _merchants = merchants,
        _transactions = transactions,
        _brandMetadata = brandMetadata,
        _policy = policy;

  final MerchantRepository _merchants;
  final TransactionRepository _transactions;

  /// 장소 API 캐시. 사용자 선택을 여기에도 남겨 자동 조회가 덮어쓰지 못하게 한다.
  final BrandMetadataRepository? _brandMetadata;

  final BrandLearningPolicy _policy;

  Future<CorrectionResult> call({
    required Transaction transaction,
    required String category,
    required String subcategory,
    String? brand,
    String? memo,
    String? displayName,
    String? tag,
    bool applyToBrand = false,
    bool reclassifyPastTransactions = false,
    int? amount,
    DateTime? paymentDatetime,
    TransactionDirection? direction,
    int? accountId,
    String? accountName,
    bool accountChanged = false,
  }) async {
    final String effectiveBrand = (brand != null && brand.trim().isNotEmpty)
        ? brand.trim()
        : transaction.brand;

    // 정책 판단이 먼저다. 호출자가 applyToBrand=true 를 넘겼더라도
    // 이체 거래라면 학습하지 않는다.
    final BrandLearningDecision decision = _policy.evaluate(
      method: transaction.method,
      brand: effectiveBrand,
      merchantRaw: transaction.merchantRaw,
    );

    // 1) 거래 자체를 갱신.
    //    merchantRaw(원본 거래명)와 fingerprint 는 절대 건드리지 않는다.
    //    fingerprint 를 바꾸면 같은 알림이 다시 들어올 때 중복 저장된다.
    final TransactionDirection effectiveDirection =
        direction ?? transaction.direction;

    final Transaction updated = transaction.copyWith(
      brand: effectiveBrand,
      category: category,
      subcategory: subcategory,
      memo: memo,
      userDisplayName: displayName,
      tag: tag,
      // 금액은 항상 양수로 받아 부호는 취소 여부가 결정한다.
      // 취소 거래(음수)는 부호를 유지해야 통계에서 계속 차감된다.
      amount: amount == null
          ? null
          : (transaction.amount < 0 ? -amount : amount),
      paymentDatetime: paymentDatetime,
      direction: effectiveDirection,
      // 수입으로 바꾸면 결제 수단은 의미가 없어진다.
      method: effectiveDirection.isIncome && !transaction.isIncome
          ? PaymentMethodKind.unknown
          : null,
      accountId: accountChanged ? accountId : Transaction.keep,
      account: accountChanged ? accountName : Transaction.keep,
      classificationSource: ClassificationSource.user,
      needsReview: false,
    );
    await _transactions.update(updated);

    if (decision.isBlocked) {
      AppLogger.i('학습 없이 이번 거래만 수정: ${transaction.merchantRaw} '
          '-> $category/$subcategory (${decision.reason})');
      return CorrectionResult(
        transaction: updated,
        learned: false,
        blockedReason: decision.reason,
      );
    }

    // 2) 이 가맹점명을 사용자 지정으로 학습.
    await _merchants.save(
      Merchant.unsaved(
        brand: effectiveBrand,
        merchantName: transaction.merchantRaw,
        normalizedName: TextNormalizer.normalize(transaction.merchantRaw),
        category: category,
        subcategory: subcategory,
        source: ClassificationSource.user,
        confidence: 1,
      ),
    );

    // 3) 장소 API 캐시에도 사용자 확정을 남긴다.
    //    "못 찾음" 으로 캐시된 브랜드가 사용자 선택으로 교정되고,
    //    이후 자동 조회는 이 값을 덮어쓰지 않는다.
    await _markMetadata(
      brand: effectiveBrand,
      category: category,
      subcategory: subcategory,
    );

    // 4) 같은 브랜드의 "분류 필요" 거래를 함께 해소한다.
    await _transactions.resolveReviewForBrand(
      brand: effectiveBrand,
      category: category,
      subcategory: subcategory,
    );

    if (!applyToBrand) {
      AppLogger.i('사용자 수정 학습: ${transaction.merchantRaw} '
          '-> $category/$subcategory');
      return CorrectionResult(transaction: updated, learned: true);
    }

    // 5) 브랜드 전체로 확장
    await _merchants.updateClassificationForBrand(
      brand: effectiveBrand,
      category: category,
      subcategory: subcategory,
      source: ClassificationSource.user,
    );

    // 6) 브랜드 규칙에도 등록해, 아직 본 적 없는 지점까지 자동 적용되게 한다.
    final String pattern = TextNormalizer.normalize(effectiveBrand);
    if (pattern.length >= 2) {
      await _merchants.upsertBrandRule(
        BrandRule(
          pattern: pattern,
          brand: effectiveBrand,
          category: category,
          subcategory: subcategory,
          // 사용자 규칙이 항상 내장 시드보다 우선하도록 우선순위를 올린다.
          priority: 100,
          source: ClassificationSource.user,
        ),
      );
    }

    // 7) 원하면 과거 거래까지 소급 적용
    if (reclassifyPastTransactions) {
      await _transactions.reclassifyByBrand(
        brand: effectiveBrand,
        category: category,
        subcategory: subcategory,
      );
    }

    AppLogger.i('브랜드 단위 학습: $effectiveBrand -> $category/$subcategory');
    return CorrectionResult(transaction: updated, learned: true);
  }

  /// 메타데이터 갱신은 부가 작업이다. 실패해도 수정 자체를 되돌리지 않는다.
  Future<void> _markMetadata({
    required String brand,
    required String category,
    required String subcategory,
  }) async {
    final BrandMetadataRepository? metadata = _brandMetadata;
    if (metadata == null) return;
    try {
      await metadata.markUserModified(
        brand: brand,
        category: category,
        subcategory: subcategory,
      );
    } on Object catch (e, stack) {
      AppLogger.e('브랜드 메타데이터 사용자 지정 반영 실패', e, stack);
    }
  }

  /// UI 가 학습 스위치를 어떻게 보여줄지 물어보는 용도.
  BrandLearningDecision evaluateLearning(Transaction transaction, String brand) {
    return _policy.evaluate(
      method: transaction.method,
      brand: brand,
      merchantRaw: transaction.merchantRaw,
    );
  }
}
