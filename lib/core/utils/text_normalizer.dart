/// 가맹점명 정규화 유틸.
///
/// 알림 문자열은 같은 가맹점이라도 표기가 조금씩 다르다.
/// (`스타벅스 강남점`, `스타벅스강남점`, `(주)스타벅스코리아`)
/// DB 조회 키를 안정적으로 만들기 위해 항상 이 함수를 통과시킨다.
class TextNormalizer {
  const TextNormalizer._();

  static final RegExp _keepOnly = RegExp(r'[^가-힣ㄱ-ㅎㅏ-ㅣa-z0-9]');
  static final RegExp _corpPrefix = RegExp(r'^(\(주\)|주식회사|㈜|\(유\)|유한회사)');
  /// 끝에 붙은 지점 표기만 떼어낸다.
  ///
  /// 앞부분까지 함께 매칭하면(`([가-힣]{1,10})?...`) 문자열 전체가 지워져
  /// 아무 효과가 없는 함수가 된다. 접미사만 좁게 잡는다.
  static final RegExp _branchSuffix =
      RegExp(r'(\d{1,3}호)?(지점|본점|영업소|매장|점)$');

  /// DB 의 `normalized_name` 컬럼에 저장되는 형태.
  ///
  /// 공백/특수문자 제거 + 영문 소문자화.
  static String normalize(String raw) {
    final String lowered = raw.toLowerCase().trim();
    final String withoutCorp = lowered.replaceFirst(_corpPrefix, '');
    return withoutCorp.replaceAll(_keepOnly, '');
  }

  /// 지점 접미사를 제거한 형태를 함께 반환한다.
  ///
  /// `스타벅스강남점` -> `스타벅스강남` 이 아니라 브랜드 매칭 실패 시의
  /// 2차 후보로만 사용한다. 과도하게 잘라내지 않도록 최소 2글자는 남긴다.
  static String stripBranchSuffix(String normalized) {
    if (normalized.length <= 3) return normalized;
    final String stripped = normalized.replaceFirst(_branchSuffix, '');
    return stripped.length >= 2 ? stripped : normalized;
  }

  /// 정규화 결과와 함께 "정규화 문자열의 i번째 문자가 원본의 몇 번째였는지" 를 반환한다.
  ///
  /// 브랜드 부분일치 후 지점명을 원본 표기 그대로 잘라내기 위해 필요하다.
  /// `메가MGC커피 춘천후평점` 에서 패턴 `메가mgc커피` 를 찾은 뒤
  /// 원본의 `춘천후평점` 을 얻는 데 사용한다.
  static NormalizedText normalizeWithIndex(String raw) {
    final String lowered = raw.toLowerCase();
    final StringBuffer buffer = StringBuffer();
    final List<int> indexMap = <int>[];

    // `normalize` 와 동일하게 법인 접두어를 건너뛴다(두 함수의 결과가 어긋나면 안 된다).
    final Match? corp = _corpPrefix.matchAsPrefix(lowered);
    final int start = corp?.end ?? 0;

    for (int i = start; i < lowered.length; i++) {
      final String char = lowered[i];
      if (_keepOnly.hasMatch(char)) continue;
      buffer.write(char);
      indexMap.add(i);
    }
    return NormalizedText(buffer.toString(), indexMap, raw);
  }

  /// 한글이 한 글자라도 포함되어 있는지.
  static bool hasKorean(String value) =>
      RegExp(r'[가-힣]').hasMatch(value);

  /// 사람 이름 마스킹 패턴(`홍*동`, `김**`)인지.
  static bool isMaskedPersonName(String value) =>
      RegExp(r'^[가-힣]\*+[가-힣]?$').hasMatch(value);
}

/// 정규화 문자열 + 원본 인덱스 매핑.
class NormalizedText {
  const NormalizedText(this.value, this._indexMap, this.raw);

  /// 정규화된 문자열. 예: `메가mgc커피춘천후평점`
  final String value;

  /// 원본 문자열.
  final String raw;

  /// `value[i]` 가 `raw` 에서 몇 번째 문자였는지.
  final List<int> _indexMap;

  /// 정규화 인덱스 [normalizedIndex] 에 대응하는 원본 인덱스.
  int rawIndexAt(int normalizedIndex) {
    if (_indexMap.isEmpty) return 0;
    if (normalizedIndex <= 0) return _indexMap.first;
    if (normalizedIndex >= _indexMap.length) return raw.length;
    return _indexMap[normalizedIndex];
  }

  /// 정규화 구간 [start, end) 에 대응하는 원본 부분 문자열.
  String rawSlice(int start, int end) {
    final int rawStart = rawIndexAt(start);
    final int rawEnd = rawIndexAt(end);
    if (rawStart >= rawEnd || rawEnd > raw.length) return '';
    return raw.substring(rawStart, rawEnd);
  }

  /// 정규화 인덱스 [normalizedIndex] 이후의 원본 나머지(앞뒤 공백 제거).
  String rawTailFrom(int normalizedIndex) {
    final int rawStart = rawIndexAt(normalizedIndex);
    if (rawStart >= raw.length) return '';
    return raw.substring(rawStart).trim();
  }
}
