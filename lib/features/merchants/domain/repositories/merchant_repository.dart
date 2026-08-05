import '../../../../core/constants/classification_source.dart';
import '../entities/merchant.dart';

/// 가맹점 조회 결과.
sealed class MerchantLookup {
  const MerchantLookup();
}

/// `merchants` 테이블에 이미 학습된 가맹점이 있었다(LLM 호출 불필요).
class MerchantExactHit extends MerchantLookup {
  const MerchantExactHit(this.merchant);

  final Merchant merchant;
}

/// 브랜드 사전으로 분류할 수 있었다(LLM 호출 불필요).
class MerchantBrandHit extends MerchantLookup {
  const MerchantBrandHit(this.rule, {this.branch});

  final BrandRule rule;

  /// 원본 표기 그대로의 지점명. 예: `춘천후평점`
  final String? branch;
}

/// 처음 보는 가맹점 → LLM 분류 대상.
class MerchantMiss extends MerchantLookup {
  const MerchantMiss(this.merchantRaw);

  final String merchantRaw;
}

abstract interface class MerchantRepository {
  /// 가맹점 문자열로 분류 정보를 찾는다.
  ///
  /// 조회 순서: 학습된 가맹점(완전일치) → 지점 접미사 제거 후 완전일치 → 브랜드 부분일치.
  Future<MerchantLookup> lookup(String merchantRaw);

  /// 가맹점을 저장하거나 갱신한다(`normalized_name` 기준 upsert).
  ///
  /// 기존 분류의 출처가 더 강하면(예: user) 덮어쓰지 않는다.
  Future<Merchant> save(Merchant merchant);

  /// 매칭 횟수 +1.
  Future<void> registerHit(int merchantId);

  Future<Merchant?> findById(int id);

  Future<List<Merchant>> findByBrand(String brand);

  /// 같은 브랜드의 모든 가맹점 분류를 한 번에 바꾼다(사용자 학습 전파).
  ///
  /// 변경된 행 수를 반환한다.
  Future<int> updateClassificationForBrand({
    required String brand,
    required String category,
    required String subcategory,
    required ClassificationSource source,
  });

  /// 브랜드 규칙 추가/갱신. 사용자 학습 결과를 브랜드 단위로 승격시킬 때 쓴다.
  Future<void> upsertBrandRule(BrandRule rule);

  Future<List<BrandRule>> allBrandRules();

  /// 학습된 가맹점 수(설정 화면 표시용).
  Future<int> learnedCount();

  /// 메모리 캐시를 비운다(브랜드 규칙 변경 후 호출).
  Future<void> invalidateCache();
}
