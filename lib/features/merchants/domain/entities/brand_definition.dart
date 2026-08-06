import '../../../../core/utils/text_normalizer.dart';

/// 브랜드 하나의 정의.
///
/// **대표 브랜드(canonical)는 하나, 표기(alias)는 여럿이다.**
///
/// 은행·카드사가 같은 브랜드를 서로 다르게 보내기 때문이다.
///
/// ```dart
/// BrandDefinition(
///   canonical: 'CU',
///   aliases: <String>['CU', '씨유'],
///   category: '생활',
///   subcategory: '편의점',
/// )
/// ```
///
/// 새 표기가 발견되면 [aliases] 에 한 줄 추가하는 것으로 끝난다.
/// 분류·통계·학습은 전부 [canonical] 로 모이므로 흩어지지 않는다.
class BrandDefinition {
  const BrandDefinition({
    required this.canonical,
    required this.aliases,
    required this.category,
    required this.subcategory,
    this.priority = 0,
  });

  /// 대표 브랜드명. 화면과 통계에 쓰이는 이름이다.
  final String canonical;

  /// 이 브랜드를 가리키는 모든 표기.
  ///
  /// 대표 브랜드 자신도 포함한다(카드사가 그대로 보내는 경우가 많다).
  final List<String> aliases;

  final String category;
  final String subcategory;

  /// 여러 브랜드가 동시에 일치할 때의 우선순위. 큰 값이 이긴다.
  ///
  /// 기본 정렬은 "alias 길이" 이므로 대부분 0으로 둔다.
  final int priority;

  /// 매칭에 쓰는 정규화된 alias 목록.
  ///
  /// 정규화는 소문자화 + 공백/특수문자 제거 + 법인 접두사 제거다.
  /// 중복은 제거한다(`CU` 와 `cu` 는 같은 것이 된다).
  List<String> get normalizedAliases {
    final Set<String> seen = <String>{};
    for (final String alias in aliases) {
      final String normalized = TextNormalizer.normalize(alias);
      if (normalized.isNotEmpty) seen.add(normalized);
    }
    return seen.toList();
  }

  @override
  String toString() =>
      'BrandDefinition($canonical, ${aliases.length}개 표기, '
      '$category/$subcategory)';
}
