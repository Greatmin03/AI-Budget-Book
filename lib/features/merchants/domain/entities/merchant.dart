import '../../../../core/constants/classification_source.dart';

/// 학습된 가맹점.
///
/// 한 번 여기 저장되면 같은 가맹점에 대해 다시 LLM 을 호출하지 않는다.
class Merchant {
  const Merchant({
    required this.id,
    required this.brand,
    required this.merchantName,
    required this.normalizedName,
    required this.category,
    required this.subcategory,
    required this.source,
    this.branch,
    this.confidence = 0,
    this.hitCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// 아직 DB 에 저장되지 않은 가맹점(id 미할당).
  const Merchant.unsaved({
    required this.brand,
    required this.merchantName,
    required this.normalizedName,
    required this.category,
    required this.subcategory,
    required this.source,
    this.branch,
    this.confidence = 0,
  })  : id = null,
        hitCount = 0,
        createdAt = null,
        updatedAt = null;

  final int? id;

  /// 브랜드명. 예: `메가커피`
  final String brand;

  /// 알림에 찍힌 가맹점명 원본. 예: `메가MGC커피 춘천후평점`
  final String merchantName;

  /// 조회 키. 예: `메가mgc커피춘천후평점`
  final String normalizedName;

  /// 지점명. 예: `춘천후평점`
  final String? branch;

  final String category;
  final String subcategory;
  final ClassificationSource source;

  /// LLM 분류 시의 확신도(0~1). 규칙/사용자 분류는 1로 둔다.
  final double confidence;

  /// 이 가맹점이 몇 번 매칭되었는지(통계 "가장 많이 간 가게" 보조 지표).
  final int hitCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 화면에 표시할 이름. 지점명이 있으면 `브랜드 지점` 형태로 보여준다.
  String get displayName {
    final String? b = branch;
    if (b == null || b.isEmpty) return brand;
    return '$brand $b';
  }

  Merchant copyWith({
    int? id,
    String? brand,
    String? merchantName,
    String? branch,
    String? category,
    String? subcategory,
    ClassificationSource? source,
    double? confidence,
    int? hitCount,
  }) {
    return Merchant(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      merchantName: merchantName ?? this.merchantName,
      normalizedName: normalizedName,
      branch: branch ?? this.branch,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      hitCount: hitCount ?? this.hitCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'Merchant($brand, $merchantName, $category/$subcategory, ${source.code})';
}

/// 브랜드 부분일치 규칙.
class BrandRule {
  const BrandRule({
    required this.pattern,
    required this.brand,
    required this.category,
    required this.subcategory,
    this.id,
    this.priority = 0,
    this.source = ClassificationSource.seed,
  });

  final int? id;

  /// 정규화된 검색 패턴. 예: `메가mgc커피`
  final String pattern;
  final String brand;
  final String category;
  final String subcategory;
  final int priority;
  final ClassificationSource source;

  /// 짧은 패턴(`cu`, `kt` 등)은 부분일치가 위험하므로 완전일치만 허용한다.
  bool get requiresExactMatch => pattern.length <= 2;

  @override
  String toString() =>
      'BrandRule($pattern -> $brand, $category/$subcategory)';
}
