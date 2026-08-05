import '../../../../core/constants/app_categories.dart';
import '../../../../core/constants/classification_source.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../entities/merchant_classification.dart';

/// LLM 을 쓸 수 없을 때의 안전한 폴백 분류기.
///
/// 브랜드 사전(정확 매칭)과 달리, 여기서는 **업종 키워드**로 추론한다.
/// `만복국수` -> `국수` 키워드 -> 식비/한식
///
/// 어떤 입력에도 예외 없이 결과를 돌려준다(최후에는 `기타/미분류`).
class RuleBasedClassifier {
  const RuleBasedClassifier();

  /// 키워드 -> 분류. 긴 키워드가 먼저 검사되도록 [_sortedKeywords] 에서 정렬한다.
  static const Map<String, CategoryPair> _keywords = <String, CategoryPair>{
    // 식비 - 카페/디저트
    '커피': CategoryPair('식비', '카페'),
    'coffee': CategoryPair('식비', '카페'),
    '카페': CategoryPair('식비', '카페'),
    'cafe': CategoryPair('식비', '카페'),
    '다방': CategoryPair('식비', '카페'),
    '티하우스': CategoryPair('식비', '카페'),
    '베이커리': CategoryPair('식비', '디저트'),
    '제과': CategoryPair('식비', '디저트'),
    '빵집': CategoryPair('식비', '디저트'),
    '도넛': CategoryPair('식비', '디저트'),
    '아이스크림': CategoryPair('식비', '디저트'),
    '빙수': CategoryPair('식비', '디저트'),
    '케이크': CategoryPair('식비', '디저트'),
    '디저트': CategoryPair('식비', '디저트'),

    // 식비 - 한식/분식
    '국수': CategoryPair('식비', '한식'),
    '국밥': CategoryPair('식비', '한식'),
    '해장국': CategoryPair('식비', '한식'),
    '설렁탕': CategoryPair('식비', '한식'),
    '설렁': CategoryPair('식비', '한식'),
    '곰탕': CategoryPair('식비', '한식'),
    '칼국수': CategoryPair('식비', '한식'),
    '냉면': CategoryPair('식비', '한식'),
    '백반': CategoryPair('식비', '한식'),
    '한정식': CategoryPair('식비', '한식'),
    '기사식당': CategoryPair('식비', '한식'),
    '식당': CategoryPair('식비', '한식'),
    '밥집': CategoryPair('식비', '한식'),
    '찌개': CategoryPair('식비', '한식'),
    '두부': CategoryPair('식비', '한식'),
    '보쌈': CategoryPair('식비', '한식'),
    '족발': CategoryPair('식비', '한식'),
    '순대': CategoryPair('식비', '분식'),
    '떡볶이': CategoryPair('식비', '분식'),
    '분식': CategoryPair('식비', '분식'),
    '김밥': CategoryPair('식비', '분식'),
    '토스트': CategoryPair('식비', '분식'),
    '만두': CategoryPair('식비', '분식'),

    // 식비 - 고기/기타 외식
    '삼겹': CategoryPair('식비', '고기/구이'),
    '갈비': CategoryPair('식비', '고기/구이'),
    '곱창': CategoryPair('식비', '고기/구이'),
    '구이': CategoryPair('식비', '고기/구이'),
    '정육': CategoryPair('식비', '고기/구이'),
    '숯불': CategoryPair('식비', '고기/구이'),
    '치킨': CategoryPair('식비', '치킨/피자'),
    '통닭': CategoryPair('식비', '치킨/피자'),
    '닭강정': CategoryPair('식비', '치킨/피자'),
    '닭발': CategoryPair('식비', '주류'),
    '피자': CategoryPair('식비', '치킨/피자'),
    'pizza': CategoryPair('식비', '치킨/피자'),
    '버거': CategoryPair('식비', '패스트푸드'),
    'burger': CategoryPair('식비', '패스트푸드'),
    '햄버거': CategoryPair('식비', '패스트푸드'),
    '중화': CategoryPair('식비', '중식'),
    '중국': CategoryPair('식비', '중식'),
    '짜장': CategoryPair('식비', '중식'),
    '마라': CategoryPair('식비', '중식'),
    '양꼬치': CategoryPair('식비', '중식'),
    '초밥': CategoryPair('식비', '일식'),
    '스시': CategoryPair('식비', '일식'),
    'sushi': CategoryPair('식비', '일식'),
    '라멘': CategoryPair('식비', '일식'),
    '라면': CategoryPair('식비', '일식'),
    '돈카츠': CategoryPair('식비', '일식'),
    '돈까스': CategoryPair('식비', '일식'),
    '우동': CategoryPair('식비', '일식'),
    '파스타': CategoryPair('식비', '양식'),
    '스테이크': CategoryPair('식비', '양식'),
    '레스토랑': CategoryPair('식비', '양식'),
    '브런치': CategoryPair('식비', '양식'),
    '뷔페': CategoryPair('식비', '양식'),
    '호프': CategoryPair('식비', '주류'),
    '포차': CategoryPair('식비', '주류'),
    '주막': CategoryPair('식비', '주류'),
    '이자카야': CategoryPair('식비', '주류'),
    '술집': CategoryPair('식비', '주류'),
    '와인': CategoryPair('식비', '주류'),
    '맥주': CategoryPair('식비', '주류'),
    '배달': CategoryPair('식비', '배달'),

    // 생활
    '편의점': CategoryPair('생활', '편의점'),
    '마트': CategoryPair('생활', '마트'),
    '슈퍼': CategoryPair('생활', '마트'),
    '농협': CategoryPair('생활', '마트'),
    '청과': CategoryPair('생활', '마트'),
    '수산': CategoryPair('생활', '마트'),
    '세탁': CategoryPair('생활', '세탁'),
    '미용실': CategoryPair('생활', '미용'),
    '헤어': CategoryPair('생활', '미용'),
    '바버': CategoryPair('생활', '미용'),
    '네일': CategoryPair('생활', '미용'),
    '이발': CategoryPair('생활', '미용'),
    '동물병원': CategoryPair('생활', '반려동물'),
    '펫': CategoryPair('생활', '반려동물'),
    '가구': CategoryPair('생활', '가구/인테리어'),
    '인테리어': CategoryPair('생활', '가구/인테리어'),
    '철물': CategoryPair('생활', '생활용품'),
    '문구': CategoryPair('생활', '생활용품'),

    // 교통
    '택시': CategoryPair('교통', '택시'),
    'taxi': CategoryPair('교통', '택시'),
    '주유': CategoryPair('교통', '주유'),
    '오일': CategoryPair('교통', '주유'),
    '가스충전': CategoryPair('교통', '주유'),
    '충전소': CategoryPair('교통', '주유'),
    '주차': CategoryPair('교통', '주차'),
    '파킹': CategoryPair('교통', '주차'),
    'parking': CategoryPair('교통', '주차'),
    '고속도로': CategoryPair('교통', '통행료'),
    '통행료': CategoryPair('교통', '통행료'),
    '지하철': CategoryPair('교통', '대중교통'),
    '버스': CategoryPair('교통', '대중교통'),
    '교통카드': CategoryPair('교통', '대중교통'),
    '철도': CategoryPair('교통', '기차/고속버스'),
    '터미널': CategoryPair('교통', '기차/고속버스'),
    '항공': CategoryPair('교통', '항공'),
    '에어': CategoryPair('교통', '항공'),

    // 주거/통신
    '관리비': CategoryPair('주거/통신', '월세/관리비'),
    '임대': CategoryPair('주거/통신', '월세/관리비'),
    '월세': CategoryPair('주거/통신', '월세/관리비'),
    '전기': CategoryPair('주거/통신', '공과금'),
    '가스': CategoryPair('주거/통신', '공과금'),
    '수도': CategoryPair('주거/통신', '공과금'),
    '통신': CategoryPair('주거/통신', '통신비'),
    '텔레콤': CategoryPair('주거/통신', '통신비'),
    '모바일': CategoryPair('주거/통신', '통신비'),
    '구독': CategoryPair('주거/통신', '구독료'),

    // 의료/건강
    '병원': CategoryPair('의료/건강', '병원'),
    '의원': CategoryPair('의료/건강', '병원'),
    '클리닉': CategoryPair('의료/건강', '병원'),
    '한의원': CategoryPair('의료/건강', '병원'),
    '약국': CategoryPair('의료/건강', '약국'),
    '팜': CategoryPair('의료/건강', '약국'),
    '치과': CategoryPair('의료/건강', '치과'),
    '헬스': CategoryPair('의료/건강', '운동/피트니스'),
    '피트니스': CategoryPair('의료/건강', '운동/피트니스'),
    '짐': CategoryPair('의료/건강', '운동/피트니스'),
    '필라테스': CategoryPair('의료/건강', '운동/피트니스'),
    '요가': CategoryPair('의료/건강', '운동/피트니스'),
    '수영': CategoryPair('의료/건강', '운동/피트니스'),
    '건강원': CategoryPair('의료/건강', '건강식품'),

    // 문화/여가
    '영화': CategoryPair('문화/여가', '영화'),
    'cinema': CategoryPair('문화/여가', '영화'),
    '시네마': CategoryPair('문화/여가', '영화'),
    '서점': CategoryPair('문화/여가', '도서'),
    '문고': CategoryPair('문화/여가', '도서'),
    '북스': CategoryPair('문화/여가', '도서'),
    'books': CategoryPair('문화/여가', '도서'),
    '공연': CategoryPair('문화/여가', '공연/전시'),
    '전시': CategoryPair('문화/여가', '공연/전시'),
    '미술관': CategoryPair('문화/여가', '공연/전시'),
    '박물관': CategoryPair('문화/여가', '공연/전시'),
    '게임': CategoryPair('문화/여가', '게임'),
    'game': CategoryPair('문화/여가', '게임'),
    'pc방': CategoryPair('문화/여가', '게임'),
    '노래': CategoryPair('문화/여가', '취미'),
    '볼링': CategoryPair('문화/여가', '취미'),
    '당구': CategoryPair('문화/여가', '취미'),
    '골프': CategoryPair('문화/여가', '취미'),
    '호텔': CategoryPair('문화/여가', '숙박'),
    'hotel': CategoryPair('문화/여가', '숙박'),
    '모텔': CategoryPair('문화/여가', '숙박'),
    '펜션': CategoryPair('문화/여가', '숙박'),
    '게스트하우스': CategoryPair('문화/여가', '숙박'),
    '리조트': CategoryPair('문화/여가', '숙박'),
    '여행': CategoryPair('문화/여가', '여행'),
    '투어': CategoryPair('문화/여가', '여행'),

    // 쇼핑
    '의류': CategoryPair('쇼핑', '의류'),
    '패션': CategoryPair('쇼핑', '의류'),
    '스토어': CategoryPair('쇼핑', '온라인쇼핑'),
    '백화점': CategoryPair('쇼핑', '의류'),
    '아웃렛': CategoryPair('쇼핑', '의류'),
    '신발': CategoryPair('쇼핑', '신발/잡화'),
    '슈즈': CategoryPair('쇼핑', '신발/잡화'),
    '가방': CategoryPair('쇼핑', '신발/잡화'),
    '화장품': CategoryPair('쇼핑', '화장품'),
    '코스메틱': CategoryPair('쇼핑', '화장품'),
    '전자': CategoryPair('쇼핑', '전자기기'),
    '디지털': CategoryPair('쇼핑', '전자기기'),
    '컴퓨터': CategoryPair('쇼핑', '전자기기'),

    // 교육
    '학원': CategoryPair('교육', '학원'),
    '교습': CategoryPair('교육', '학원'),
    '아카데미': CategoryPair('교육', '학원'),
    '스터디': CategoryPair('교육', '학원'),
    '독서실': CategoryPair('교육', '학원'),
    '강의': CategoryPair('교육', '온라인강의'),
    '교재': CategoryPair('교육', '교재'),

    // 금융
    '보험': CategoryPair('금융', '보험'),
    '수수료': CategoryPair('금융', '이자/수수료'),
    '증권': CategoryPair('금융', '투자'),

    // 기타
    '장례': CategoryPair('기타', '경조사'),
    '예식': CategoryPair('기타', '경조사'),
    '화환': CategoryPair('기타', '경조사'),
    '기부': CategoryPair('기타', '기부'),
  };

  /// 긴 키워드 우선. (`동물병원` 이 `병원` 보다 먼저 검사되어야 한다)
  static final List<String> _sortedKeywords = _keywords.keys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));

  /// 항상 결과를 반환한다. 매칭되는 키워드가 없으면 `기타/미분류`.
  MerchantClassification classify(String merchantRaw) {
    final String normalized = TextNormalizer.normalize(merchantRaw);

    for (final String keyword in _sortedKeywords) {
      if (!normalized.contains(keyword)) continue;
      final CategoryPair pair = _keywords[keyword]!;
      return MerchantClassification(
        brand: _guessBrand(merchantRaw),
        category: pair.category,
        subcategory: pair.subcategory,
        source: ClassificationSource.rule,
        // 키워드 추론이므로 확신도를 낮게 잡는다.
        confidence: 0.6,
      );
    }

    return MerchantClassification(
      brand: _guessBrand(merchantRaw),
      category: CategoryTaxonomy.etcCategory,
      subcategory: '미분류',
      source: ClassificationSource.rule,
      confidence: 0.2,
    );
  }

  /// 브랜드를 알 수 없으므로 가맹점명에서 지점 표기만 떼어 대표명으로 쓴다.
  String _guessBrand(String merchantRaw) {
    final String trimmed = merchantRaw.trim();
    if (trimmed.isEmpty) return '미확인 가맹점';

    // 마지막 공백 뒤 토큰이 `~점` 이면 지점명으로 보고 제거한다.
    final int lastSpace = trimmed.lastIndexOf(' ');
    if (lastSpace > 1) {
      final String tail = trimmed.substring(lastSpace + 1);
      if (tail.endsWith('점') && tail.length <= 8) {
        return trimmed.substring(0, lastSpace).trim();
      }
    }
    return trimmed;
  }
}
