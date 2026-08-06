import '../../../../core/utils/text_normalizer.dart';
import '../entities/brand_definition.dart';

/// 브랜드 추출 결과.
class BrandExtraction {
  const BrandExtraction({
    required this.definition,
    required this.matchedAlias,
    this.branch,
  });

  final BrandDefinition definition;

  /// 실제로 매칭된 alias(정규화된 형태). 진단과 테스트에 쓴다.
  final String matchedAlias;

  /// 브랜드 뒤에 남은 지점명. **원본 표기 그대로**다.
  final String? branch;

  String get canonical => definition.canonical;
  String get category => definition.category;
  String get subcategory => definition.subcategory;

  @override
  String toString() =>
      '$canonical${branch == null ? '' : ' $branch'} '
      '($category/$subcategory, alias=$matchedAlias)';
}

/// 거래명에서 **대표 브랜드**를 뽑아낸다.
///
/// 은행·카드사마다 같은 브랜드를 다른 형식으로 보낸다.
///
/// ```
/// 씨유강원대제3학생   씨유(CU) 춘천 백령점   씨유강대병원점
/// 지에스25춘천애막골  지에스25(GS25) 춘천
/// 메가MGC커피강원대점 메가커피춘천후평점
/// ```
///
/// 이 차이를 흡수하지 못하면 **이미 아는 브랜드인데도** 카카오 API 와
/// AI 대기열까지 진행된다. 그래서 분류 사슬에서 가장 먼저 실행된다.
///
/// ## 매칭 순서
/// 1. **접두 일치**(`startsWith`) — 가장 신뢰할 수 있다. 거래명은 대개
///    브랜드로 시작하고, 뒤에 남는 것이 지점명이다.
/// 2. **부분 일치**(`contains`) — 1에서 못 찾았을 때만. 실제 알림에는
///    `춘천 스타벅스 명동점` 처럼 브랜드가 중간에 오는 형식도 있다.
///
/// 접두 일치만 쓰면 그런 형식을 놓친다. 부분 일치만 쓰면 지점 분리가
/// 부정확해진다. 그래서 둘 다 쓰되 **접두를 먼저** 본다.
///
/// 두 단계 모두 **긴 alias 부터** 검사한다.
/// `메가MGC커피` 가 `메가커피` 보다 먼저 매칭돼야 한다.
///
/// ## 실패하면
/// null 을 반환하고 호출자는 기존 흐름(카카오 API → AI 대기열 → 사용자
/// 선택)으로 넘어간다. 이 단계는 **빠른 경로**이지 유일한 경로가 아니다.
class BrandExtractor {
  const BrandExtractor(this._definitions);

  final List<BrandDefinition> _definitions;

  /// 후보가 아는 브랜드인지만 알려 준다.
  ///
  /// 파서가 여러 후보 중 무엇이 가맹점인지 고를 때 쓴다.
  bool recognizes(String candidate) => extract(candidate) != null;

  /// 거래명에서 대표 브랜드를 찾는다. 못 찾으면 null.
  BrandExtraction? extract(String merchantRaw) {
    if (merchantRaw.trim().isEmpty) return null;

    final NormalizedText normalized =
        TextNormalizer.normalizeWithIndex(merchantRaw);
    if (normalized.value.isEmpty) return null;

    // 1) 접두 일치 — 가장 신뢰할 수 있다.
    final BrandExtraction? prefix = _match(
      normalized,
      (String text, String alias) => text.startsWith(alias) ? 0 : -1,
      loose: false,
    );
    if (prefix != null) return prefix;

    // 2) 부분 일치 — 브랜드가 중간에 오는 형식을 위한 폴백.
    return _match(
      normalized,
      (String text, String alias) => text.indexOf(alias),
      loose: true,
    );
  }

  /// [locate] 가 반환한 위치에서 매칭을 확정한다. 음수면 불일치.
  ///
  /// [loose] 는 부분 일치 단계인지(= 더 위험한 단계인지)를 뜻한다.
  BrandExtraction? _match(
    NormalizedText normalized,
    int Function(String text, String alias) locate, {
    required bool loose,
  }) {
    for (final _AliasEntry entry in _sortedAliases) {
      final bool allowed = loose ? entry.allowsContains : entry.allowsPrefix;

      // 느슨한 매칭이 허용되지 않는 짧은 alias 는 완전일치만 본다.
      if (!allowed) {
        if (normalized.value == entry.alias) {
          return BrandExtraction(
            definition: entry.definition,
            matchedAlias: entry.alias,
          );
        }
        continue;
      }

      final int index = locate(normalized.value, entry.alias);
      if (index < 0) continue;

      final int end = index + entry.alias.length;

      // 짧은 라틴 alias 는 낱말 경계에서 끝나야 한다.
      // (`cu춘천점` 은 통과, `cucumber마켓` 은 탈락)
      if (AliasMatching.requiresBoundary(entry.alias) &&
          !AliasMatching.hasWordBoundary(normalized.value, end)) {
        continue;
      }

      final String branch =
          normalized.rawTailFrom(end);
      return BrandExtraction(
        definition: entry.definition,
        matchedAlias: entry.alias,
        branch: branch.isEmpty ? null : branch,
      );
    }
    return null;
  }

  /// 모든 alias 를 **긴 것부터** 펼쳐 둔다.
  ///
  /// `const` 생성자를 유지하려고 매번 계산한다. 사전이 수백 건 수준이라
  /// 비용이 문제되지 않고, 사전을 바꾸면 즉시 반영된다는 장점이 있다.
  List<_AliasEntry> get _sortedAliases {
    final List<_AliasEntry> entries = <_AliasEntry>[
      for (final BrandDefinition definition in _definitions)
        for (final String alias in definition.normalizedAliases)
          _AliasEntry(alias: alias, definition: definition),
    ]..sort((_AliasEntry a, _AliasEntry b) {
        final int byPriority =
            b.definition.priority.compareTo(a.definition.priority);
        if (byPriority != 0) return byPriority;
        return b.alias.length.compareTo(a.alias.length);
      });
    return entries;
  }
}

class _AliasEntry {
  const _AliasEntry({required this.alias, required this.definition});

  final String alias;
  final BrandDefinition definition;

  bool get allowsPrefix => AliasMatching.allowsPrefix(alias);
  bool get allowsContains => AliasMatching.allowsContains(alias);
}

/// alias 를 어디까지 느슨하게 매칭해도 되는지 판단한다.
///
/// **문자 종류에 따라 담는 정보량이 다르다.**
///  - 라틴 2글자(`cu`, `kt`)는 아무 단어에나 걸린다. `cucumber마켓` 이
///    `cu` 로 시작한다고 편의점일 리 없다.
///  - 한글 2글자(`씨유`)는 음절 하나가 담는 정보가 훨씬 크다. 실제로
///    은행이 `씨유강원대제3학생` 처럼 보내므로 접두 매칭이 꼭 필요하다.
///
/// 그래서 길이만이 아니라 **한글 포함 여부**로 나눈다.
class AliasMatching {
  const AliasMatching._();

  static final RegExp _hangul = RegExp(r'[가-힣]');

  static final RegExp _latin = RegExp(r'[a-z0-9]');

  /// 접두 일치(`startsWith`)를 허용하는가.
  ///
  /// 2글자도 허용하되, 라틴 2글자는 [hasWordBoundary] 를 함께 만족해야 한다.
  static bool allowsPrefix(String alias) => alias.length >= 2;

  /// 이 alias 가 접두 매칭될 때 **경계 검사**가 필요한가.
  ///
  /// `cu` 는 `cu춘천점`(편의점)과 `cucumber마켓`(아님)을 구별해야 한다.
  /// 한글 2글자는 그 자체로 충분히 구체적이라 검사가 필요 없다.
  static bool requiresBoundary(String alias) =>
      alias.length <= 2 && !_hangul.hasMatch(alias);

  /// alias 가 끝나는 자리가 낱말 경계인가.
  ///
  /// 뒤에 라틴 문자·숫자가 이어지면 다른 단어의 일부다.
  ///
  /// ```
  /// cu춘천점      -> 뒤가 한글    -> 경계 O -> CU
  /// cucumber마켓  -> 뒤가 라틴    -> 경계 X -> 매칭 안 함
  /// cu            -> 문자열 끝    -> 경계 O -> CU
  /// ```
  static bool hasWordBoundary(String text, int endIndex) {
    if (endIndex >= text.length) return true;
    return !_latin.hasMatch(text[endIndex]);
  }

  /// 부분 일치(`contains`)를 허용하는가.
  ///
  /// 접두보다 위험하므로 3글자 이상만 허용한다.
  /// `씨유` 를 부분 일치까지 허용하면 `아씨유통` 이 편의점이 된다.
  static bool allowsContains(String alias) => alias.length >= 3;
}
