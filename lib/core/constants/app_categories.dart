/// 카테고리 / 서브카테고리 분류 체계.
///
/// LLM 응답 검증의 기준이 되는 유일한 원천(single source of truth)이다.
/// LLM 이 이 목록에 없는 값을 반환하면 [CategoryTaxonomy.coerce] 가 안전한 값으로 보정한다.
class CategoryTaxonomy {
  const CategoryTaxonomy._();

  static const String etcCategory = '기타';
  static const String etcSubcategory = '기타';

  /// 카테고리 -> 서브카테고리 목록.
  static const Map<String, List<String>> tree = <String, List<String>>{
    '식비': <String>[
      '한식',
      '중식',
      '일식',
      '양식',
      '분식',
      '고기/구이',
      '치킨/피자',
      '패스트푸드',
      '카페',
      '디저트',
      '배달',
      '주류',
      '기타',
    ],
    '생활': <String>[
      '편의점',
      '마트',
      '생활용품',
      '가구/인테리어',
      '세탁',
      '미용',
      '반려동물',
      '기타',
    ],
    '교통': <String>[
      '대중교통',
      '택시',
      '주유',
      '주차',
      '통행료',
      '기차/고속버스',
      '항공',
      '기타',
    ],
    '주거/통신': <String>[
      '월세/관리비',
      '공과금',
      '통신비',
      '구독료',
      '기타',
    ],
    '의료/건강': <String>[
      '병원',
      '약국',
      '치과',
      '운동/피트니스',
      '건강식품',
      '기타',
    ],
    '문화/여가': <String>[
      '영화',
      '공연/전시',
      '도서',
      '게임',
      '취미',
      '여행',
      '숙박',
      '기타',
    ],
    '쇼핑': <String>[
      '의류',
      '신발/잡화',
      '화장품',
      '전자기기',
      '온라인쇼핑',
      '기타',
    ],
    '교육': <String>[
      '학원',
      '온라인강의',
      '교재',
      '기타',
    ],
    '금융': <String>[
      '보험',
      '이자/수수료',
      '투자',
      '기타',
    ],
    '기타': <String>[
      '경조사',
      '기부',
      '미분류',
      '기타',
    ],
  };

  /// **수입 분류 체계.** 지출 [tree] 와 별개다.
  ///
  /// 하나로 합치지 않는 이유:
  ///  - 지출 화면의 카테고리 목록에 `급여` 가 섞이면 안 된다
  ///  - 소비 통계는 지출 카테고리만 다루므로 섞이면 비율이 깨진다
  ///
  /// 어느 체계를 쓸지는 거래의 `direction` 이 결정한다.
  static const Map<String, List<String>> incomeTree = <String, List<String>>{
    '급여': <String>['월급', '상여금', '수당', '기타'],
    '용돈': <String>['용돈', '생활비', '기타'],
    '장학금': <String>['장학금', '지원금', '기타'],
    '부수입': <String>[
      '이자',
      '중고거래',
      '판매',
      '캐시백',
      '환급',
      '알바',
      '기타',
    ],
    '투자': <String>['배당', '매도차익', '이자', '기타'],
    // 실제 소득이 아니라 **돌려받은 돈**이다. 수입 통계에서 제외된다.
    settlementCategory: <String>['더치페이', '대신결제', '회비반환', '기타'],
    '기타': <String>['미분류', '송금', '기타'],
  };

  /// 돌려받은 돈을 담는 수입 카테고리.
  ///
  /// 더치페이로 친구가 보낸 20,000원은 **소득이 아니다.** 이미 그 거래의
  /// `settlements` 로 내 부담이 줄어 있으므로, 수입으로도 세면 같은 돈을
  /// 두 번 세는 것이 된다. 그래서 수입 통계는 이 카테고리를 뺀다.
  ///
  /// 기록 자체는 남긴다. "이번 달에 얼마가 들어왔나" 와 "얼마를 벌었나" 는
  /// 다른 질문이고, 둘 다 답할 수 있어야 한다.
  static const String settlementCategory = '정산';

  static List<String> get categories => tree.keys.toList(growable: false);

  /// 수입 카테고리 목록.
  static List<String> get incomeCategories =>
      incomeTree.keys.toList(growable: false);

  static List<String> subcategoriesOf(String category) =>
      tree[category] ?? const <String>[etcSubcategory];

  /// 수입 카테고리의 세부항목.
  static List<String> incomeSubcategoriesOf(String category) =>
      incomeTree[category] ?? const <String>[etcSubcategory];

  /// 방향에 맞는 카테고리 목록.
  static List<String> categoriesFor({required bool isIncome}) =>
      isIncome ? incomeCategories : categories;

  /// 방향에 맞는 세부항목 목록.
  static List<String> subcategoriesFor(
    String category, {
    required bool isIncome,
  }) =>
      isIncome ? incomeSubcategoriesOf(category) : subcategoriesOf(category);

  /// 수입 분류를 항상 유효한 값으로 보정한다.
  static CategoryPair coerceIncome(String? category, String? subcategory) {
    final String? c = _trimOrNull(category);
    final String? s = _trimOrNull(subcategory);

    if (c == null || !incomeTree.containsKey(c)) {
      return const CategoryPair(etcCategory, '미분류');
    }
    if (s == null || !incomeTree[c]!.contains(s)) {
      return CategoryPair(c, etcSubcategory);
    }
    return CategoryPair(c, s);
  }

  /// 방향에 맞는 체계로 보정한다.
  static CategoryPair coerceFor(
    String? category,
    String? subcategory, {
    required bool isIncome,
  }) =>
      isIncome
          ? coerceIncome(category, subcategory)
          : coerce(category, subcategory);

  static bool isValidCategory(String? category) =>
      category != null && tree.containsKey(category);

  static bool isValidPair(String? category, String? subcategory) =>
      isValidCategory(category) &&
      subcategory != null &&
      tree[category]!.contains(subcategory);

  /// 검증되지 않은 (category, subcategory) 조합을 항상 유효한 값으로 보정한다.
  ///
  /// - 카테고리가 유효하지 않으면 전체를 `기타/미분류` 로 떨어뜨린다.
  /// - 카테고리는 맞고 서브카테고리만 틀리면 해당 카테고리의 `기타` 로 보정한다.
  static CategoryPair coerce(String? category, String? subcategory) {
    final String? c = _trimOrNull(category);
    final String? s = _trimOrNull(subcategory);

    if (!isValidCategory(c)) {
      return const CategoryPair(etcCategory, '미분류');
    }
    if (!isValidPair(c, s)) {
      return CategoryPair(c!, etcSubcategory);
    }
    return CategoryPair(c!, s!);
  }

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 카테고리 + 서브카테고리 쌍.
class CategoryPair {
  const CategoryPair(this.category, this.subcategory);

  final String category;
  final String subcategory;

  @override
  bool operator ==(Object other) =>
      other is CategoryPair &&
      other.category == category &&
      other.subcategory == subcategory;

  @override
  int get hashCode => Object.hash(category, subcategory);

  @override
  String toString() => '$category/$subcategory';
}
