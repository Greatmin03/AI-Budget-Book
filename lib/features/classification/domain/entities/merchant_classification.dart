import '../../../../core/constants/classification_source.dart';

/// 가맹점 분류 결과.
class MerchantClassification {
  const MerchantClassification({
    required this.brand,
    required this.category,
    required this.subcategory,
    required this.source,
    this.branch,
    this.confidence = 1.0,
  });

  /// 정규화된 브랜드명. 예: `메가커피`
  final String brand;

  /// 지점명. 예: `춘천후평점`
  final String? branch;

  final String category;
  final String subcategory;
  final ClassificationSource source;

  /// 0~1. 규칙/사용자 분류는 1.0, LLM 은 모델이 보고한 값(없으면 0.7).
  final double confidence;

  bool get isUnclassified => category == '기타' && subcategory == '미분류';

  @override
  String toString() => 'MerchantClassification($brand${branch == null ? '' : ' $branch'}, '
      '$category/$subcategory, ${source.code}, ${confidence.toStringAsFixed(2)})';
}
