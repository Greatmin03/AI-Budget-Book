import '../../../../core/constants/app_categories.dart';

/// 브랜드 업종 조회 결과의 출처.
enum BrandMetadataSource {
  /// 앱 내장 브랜드 사전.
  dictionary('dictionary', '내장 사전'),

  /// 카카오 로컬 API.
  kakao('kakao', '카카오 장소'),

  /// LLM 추천.
  llm('llm', 'AI 추천'),

  /// 사용자가 직접 지정.
  user('user', '직접 지정');

  const BrandMetadataSource(this.code, this.label);

  final String code;
  final String label;

  static BrandMetadataSource fromCode(String? code) {
    for (final BrandMetadataSource s in BrandMetadataSource.values) {
      if (s.code == code) return s;
    }
    return BrandMetadataSource.dictionary;
  }
}

/// 브랜드 한 건의 업종 메타데이터.
///
/// **이 레코드의 존재 자체가 "이미 조회했다" 는 표시다.**
/// [found] 가 false 인 것도 저장한다. 그래야 못 찾은 브랜드를
/// 결제마다 다시 조회하지 않는다.
class BrandMetadata {
  const BrandMetadata({
    required this.brand,
    required this.normalizedBrand,
    required this.source,
    required this.lookedUpAt,
    this.industry,
    this.category,
    this.subcategory,
    this.userModified = false,
    this.found = true,
    this.id,
  });

  /// 조회 실패(업종을 알 수 없음)를 캐시하는 생성자.
  const BrandMetadata.notFound({
    required this.brand,
    required this.normalizedBrand,
    required this.source,
    required this.lookedUpAt,
  })  : id = null,
        industry = null,
        category = null,
        subcategory = null,
        userModified = false,
        found = false;

  final int? id;
  final String brand;
  final String normalizedBrand;

  /// API 가 알려 준 업종. 예: `중국요리`
  final String? industry;

  final String? category;
  final String? subcategory;
  final BrandMetadataSource source;
  final DateTime lookedUpAt;

  /// 사용자가 손으로 고쳤는지. true 면 재조회가 덮어쓰지 않는다.
  final bool userModified;

  /// 업종을 찾았는지.
  final bool found;

  /// 바로 분류에 쓸 수 있는 상태인지.
  bool get isUsable =>
      found && CategoryTaxonomy.isValidPair(category, subcategory);

  CategoryPair? get pair =>
      isUsable ? CategoryPair(category!, subcategory!) : null;

  @override
  String toString() => 'BrandMetadata($brand, $industry, '
      '$category/$subcategory, ${source.code}, found=$found)';
}
