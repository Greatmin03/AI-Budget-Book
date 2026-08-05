import '../../../../core/constants/app_categories.dart';

/// 후보 여러 개를 비교한 결과.
class PlaceConsensus {
  const PlaceConsensus({
    required this.pair,
    required this.industry,
    required this.agreeing,
    required this.mappable,
    required this.total,
  });

  const PlaceConsensus.ambiguous({required this.total, this.industry})
      : pair = null,
        agreeing = 0,
        mappable = 0;

  /// 다수결로 정해진 분류. null 이면 판단하지 못했다.
  final CategoryPair? pair;

  /// 대표 업종 문자열(캐시에 남겨 두면 나중에 참고가 된다).
  final String? industry;

  /// [pair] 에 동의한 후보 수.
  final int agreeing;

  /// 우리 분류 체계로 옮길 수 있었던 후보 수.
  final int mappable;

  /// 받은 후보 총 수.
  final int total;

  /// 자동 분류해도 되는가.
  bool get isConfident => pair != null;

  /// 후보 전체가 같은 업종이었는가(가장 강한 신호).
  bool get isUnanimous => pair != null && agreeing == mappable && mappable > 1;

  @override
  String toString() => pair == null
      ? '판단 불가 (후보 $total개, 업종 불일치)'
      : '$pair ($agreeing/$mappable 일치, 후보 $total개)';
}

/// 장소 API 의 업종 문자열을 앱의 카테고리 체계로 옮긴다.
///
/// 카카오 로컬 API 는 `category_name` 을 계층 문자열로 준다.
/// ```
/// 음식점 > 중식 > 중국요리
/// 음식점 > 카페 > 커피전문점 > 스타벅스
/// 가정,생활 > 편의점 > GS25
/// ```
///
/// 가장 구체적인 단계(오른쪽)부터 매칭해야 정확하다.
/// `음식점 > 카페` 를 왼쪽부터 보면 그냥 "외식" 이 되어 정보가 사라진다.
class PlaceCategoryMapper {
  const PlaceCategoryMapper();

  /// 업종 키워드 -> 분류. 긴 키워드가 먼저 검사된다.
  static const Map<String, CategoryPair> _rules = <String, CategoryPair>{
    // 음식점 계열
    '커피전문점': CategoryPair('식비', '카페'),
    '카페': CategoryPair('식비', '카페'),
    '디저트카페': CategoryPair('식비', '디저트'),
    '베이커리': CategoryPair('식비', '디저트'),
    '제과,베이커리': CategoryPair('식비', '디저트'),
    '아이스크림': CategoryPair('식비', '디저트'),
    '떡,한과': CategoryPair('식비', '디저트'),
    '중국요리': CategoryPair('식비', '중식'),
    '중식': CategoryPair('식비', '중식'),
    '일본식': CategoryPair('식비', '일식'),
    '초밥,롤': CategoryPair('식비', '일식'),
    '돈까스,우동': CategoryPair('식비', '일식'),
    '일식': CategoryPair('식비', '일식'),
    '양식': CategoryPair('식비', '양식'),
    '이탈리안': CategoryPair('식비', '양식'),
    '패밀리레스토랑': CategoryPair('식비', '양식'),
    '뷔페': CategoryPair('식비', '양식'),
    '패스트푸드': CategoryPair('식비', '패스트푸드'),
    '햄버거': CategoryPair('식비', '패스트푸드'),
    '치킨': CategoryPair('식비', '치킨/피자'),
    '피자': CategoryPair('식비', '치킨/피자'),
    '분식': CategoryPair('식비', '분식'),
    '김밥': CategoryPair('식비', '분식'),
    '한식': CategoryPair('식비', '한식'),
    '국수': CategoryPair('식비', '한식'),
    '해물,생선': CategoryPair('식비', '한식'),
    '샤브샤브': CategoryPair('식비', '한식'),
    '족발,보쌈': CategoryPair('식비', '한식'),
    '고기': CategoryPair('식비', '고기/구이'),
    '육류': CategoryPair('식비', '고기/구이'),
    '곱창': CategoryPair('식비', '고기/구이'),
    '술집': CategoryPair('식비', '주류'),
    '호프': CategoryPair('식비', '주류'),
    '요리주점': CategoryPair('식비', '주류'),
    '음식점': CategoryPair('식비', '기타'),

    // 생활
    '편의점': CategoryPair('생활', '편의점'),
    '대형마트': CategoryPair('생활', '마트'),
    '슈퍼마켓': CategoryPair('생활', '마트'),
    '생활용품': CategoryPair('생활', '생활용품'),
    '다이소': CategoryPair('생활', '생활용품'),
    '미용실': CategoryPair('생활', '미용'),
    '네일': CategoryPair('생활', '미용'),
    '세탁': CategoryPair('생활', '세탁'),
    '가구': CategoryPair('생활', '가구/인테리어'),
    '인테리어': CategoryPair('생활', '가구/인테리어'),
    '동물병원': CategoryPair('생활', '반려동물'),
    '애완': CategoryPair('생활', '반려동물'),

    // 교통
    '주차장': CategoryPair('교통', '주차'),
    '주유소': CategoryPair('교통', '주유'),
    '충전소': CategoryPair('교통', '주유'),
    '지하철': CategoryPair('교통', '대중교통'),
    '버스': CategoryPair('교통', '대중교통'),
    '기차': CategoryPair('교통', '기차/고속버스'),
    '터미널': CategoryPair('교통', '기차/고속버스'),
    '공항': CategoryPair('교통', '항공'),
    '자동차': CategoryPair('교통', '기타'),

    // 의료
    '약국': CategoryPair('의료/건강', '약국'),
    '치과': CategoryPair('의료/건강', '치과'),
    '한의원': CategoryPair('의료/건강', '병원'),
    '병원': CategoryPair('의료/건강', '병원'),
    '의원': CategoryPair('의료/건강', '병원'),
    '헬스': CategoryPair('의료/건강', '운동/피트니스'),
    '요가,필라테스': CategoryPair('의료/건강', '운동/피트니스'),
    '스포츠,레저': CategoryPair('의료/건강', '운동/피트니스'),

    // 문화/여가
    '영화관': CategoryPair('문화/여가', '영화'),
    '공연': CategoryPair('문화/여가', '공연/전시'),
    '박물관': CategoryPair('문화/여가', '공연/전시'),
    '미술관': CategoryPair('문화/여가', '공연/전시'),
    '서점': CategoryPair('문화/여가', '도서'),
    'PC방': CategoryPair('문화/여가', '게임'),
    '오락': CategoryPair('문화/여가', '취미'),
    '노래방': CategoryPair('문화/여가', '취미'),
    '숙박': CategoryPair('문화/여가', '숙박'),
    '호텔': CategoryPair('문화/여가', '숙박'),
    '모텔': CategoryPair('문화/여가', '숙박'),
    '펜션': CategoryPair('문화/여가', '숙박'),
    '여행': CategoryPair('문화/여가', '여행'),

    // 쇼핑
    '백화점': CategoryPair('쇼핑', '의류'),
    '의류': CategoryPair('쇼핑', '의류'),
    '패션': CategoryPair('쇼핑', '의류'),
    '신발': CategoryPair('쇼핑', '신발/잡화'),
    '가방': CategoryPair('쇼핑', '신발/잡화'),
    '화장품': CategoryPair('쇼핑', '화장품'),
    '전자제품': CategoryPair('쇼핑', '전자기기'),
    '가전': CategoryPair('쇼핑', '전자기기'),
    '휴대폰': CategoryPair('쇼핑', '전자기기'),

    // 교육
    '학원': CategoryPair('교육', '학원'),
    '어학원': CategoryPair('교육', '학원'),
    '독서실': CategoryPair('교육', '학원'),

    // 금융
    '은행': CategoryPair('금융', '이자/수수료'),
    '보험': CategoryPair('금융', '보험'),
  };

  static final List<String> _sortedKeys = _rules.keys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));

  /// 업종 문자열을 카테고리로 변환한다. 매칭 실패 시 null.
  ///
  /// 계층 문자열의 **가장 구체적인 단계부터** 검사한다.
  CategoryPair? map(String? categoryName) {
    if (categoryName == null || categoryName.trim().isEmpty) return null;

    // "음식점 > 중식 > 중국요리" -> ["중국요리", "중식", "음식점"]
    final List<String> segments = categoryName
        .split('>')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList()
        .reversed
        .toList();

    for (final String segment in segments) {
      // 세그먼트 정확 일치 우선
      final CategoryPair? exact = _rules[segment];
      if (exact != null) return _validate(exact);

      // 부분 일치(긴 키워드부터)
      for (final String key in _sortedKeys) {
        if (segment.contains(key)) return _validate(_rules[key]!);
      }
    }
    return null;
  }

  /// 매핑 결과가 현재 카테고리 체계에 실제로 존재하는지 확인한다.
  ///
  /// 체계를 바꾸면 이 표가 조용히 어긋날 수 있으므로 한 번 더 통과시킨다.
  static CategoryPair _validate(CategoryPair pair) =>
      CategoryTaxonomy.coerce(pair.category, pair.subcategory);

  /// 업종 문자열에서 사람이 읽을 대표 업종만 추출한다.
  ///
  /// `음식점 > 중식 > 중국요리` -> `중국요리`
  /// 후보 여러 개의 업종을 비교해 **다수결로** 분류를 정한다.
  ///
  /// LLM 은 최후의 수단이다. 앱이 충분히 판단할 수 있으면 부르지 않는다.
  /// 카카오가 이미 가진 실제 장소 정보를 최대한 활용하는 것이 목적이다.
  ///
  /// ```
  /// 한식 한식 한식        -> 한식 (만장일치)
  /// 한식 한식 한식 중식   -> 한식 (다수)
  /// 카페 병원 약국 세탁소 -> 판단 불가 -> AI 대기열
  /// ```
  ///
  /// ## 판단 기준
  ///  - 후보 1개면 그대로 쓴다
  ///  - 2개 이상이면 **최다 득표가 2표 이상이고 2위보다 많아야** 한다
  ///    (2:2 동점, 1:1:1:1 처럼 갈리면 판단하지 않는다)
  ///
  /// 자동 분류는 사용자에게 묻지 않고 확정되므로, 애매하면 넘기는 편이 낫다.
  PlaceConsensus resolveConsensus(List<String> categoryNames) {
    if (categoryNames.isEmpty) {
      return const PlaceConsensus.ambiguous(total: 0);
    }

    // 후보를 각각 우리 체계로 옮긴다. 못 옮기는 것은 투표에서 제외한다.
    final Map<CategoryPair, int> votes = <CategoryPair, int>{};
    final Map<CategoryPair, String> industries = <CategoryPair, String>{};

    for (final String categoryName in categoryNames) {
      final CategoryPair? pair = map(categoryName);
      if (pair == null) continue;
      votes[pair] = (votes[pair] ?? 0) + 1;
      industries[pair] ??= primaryIndustry(categoryName) ?? categoryName;
    }

    final String? fallbackIndustry = primaryIndustry(categoryNames.first);

    if (votes.isEmpty) {
      // 업종은 받았지만 우리 체계로 옮길 수 없었다.
      return PlaceConsensus.ambiguous(
        total: categoryNames.length,
        industry: fallbackIndustry,
      );
    }

    final List<MapEntry<CategoryPair, int>> ranked = votes.entries.toList()
      ..sort((MapEntry<CategoryPair, int> a, MapEntry<CategoryPair, int> b) =>
          b.value.compareTo(a.value));

    final MapEntry<CategoryPair, int> first = ranked.first;
    final int mappable = votes.values.reduce((int a, int b) => a + b);

    // 후보가 하나뿐이면 비교할 것이 없으므로 그대로 받아들인다.
    if (mappable == 1) {
      return PlaceConsensus(
        pair: first.key,
        industry: industries[first.key],
        agreeing: 1,
        mappable: 1,
        total: categoryNames.length,
      );
    }

    final int second = ranked.length > 1 ? ranked[1].value : 0;
    final bool hasMajority = first.value >= 2 && first.value > second;

    if (!hasMajority) {
      return PlaceConsensus.ambiguous(
        total: categoryNames.length,
        industry: fallbackIndustry,
      );
    }

    return PlaceConsensus(
      pair: first.key,
      industry: industries[first.key],
      agreeing: first.value,
      mappable: mappable,
      total: categoryNames.length,
    );
  }

  static String? primaryIndustry(String? categoryName) {
    if (categoryName == null || categoryName.trim().isEmpty) return null;
    final List<String> segments = categoryName
        .split('>')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? null : segments.last;
  }
}
