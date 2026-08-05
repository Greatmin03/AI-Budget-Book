import '../db_schema.dart';

/// 브랜드 부분일치 규칙 한 건.
///
/// [pattern] 은 **정규화된 형태**(공백/특수문자 제거, 영문 소문자)여야 한다.
/// `TextNormalizer.normalize` 를 통과한 가맹점 문자열 안에 [pattern] 이
/// 포함되면 이 규칙이 적용된다.
class BrandSeedEntry {
  const BrandSeedEntry(
    this.pattern,
    this.brand,
    this.category,
    this.subcategory, {
    this.priority = 0,
  });

  final String pattern;
  final String brand;
  final String category;
  final String subcategory;

  /// 여러 규칙이 동시에 일치할 때의 우선순위. 큰 값이 이긴다.
  /// (기본 정렬은 "패턴 길이" 이므로 대부분 0으로 둔다.)
  final int priority;

  Map<String, Object?> toRow() => <String, Object?>{
        DbSchema.brPattern: pattern,
        DbSchema.brBrand: brand,
        DbSchema.brCategory: category,
        DbSchema.brSubcategory: subcategory,
        DbSchema.brPriority: priority,
        DbSchema.brSource: 'seed',
      };
}

/// 초기 가맹점(브랜드) 사전.
///
/// 여기에 있는 브랜드는 LLM 을 호출하지 않는다.
/// 실사용 중 자주 등장하는 가맹점은 학습되어 `merchants` 테이블로 캐시된다.
class BrandSeed {
  const BrandSeed._();

  static const List<BrandSeedEntry> entries = <BrandSeedEntry>[
    // ------------------------------------------------------------ 카페 / 디저트
    BrandSeedEntry('스타벅스', '스타벅스', '식비', '카페'),
    BrandSeedEntry('starbucks', '스타벅스', '식비', '카페'),
    BrandSeedEntry('메가mgc커피', '메가커피', '식비', '카페'),
    BrandSeedEntry('메가커피', '메가커피', '식비', '카페'),
    BrandSeedEntry('컴포즈커피', '컴포즈커피', '식비', '카페'),
    BrandSeedEntry('빽다방', '빽다방', '식비', '카페'),
    BrandSeedEntry('이디야', '이디야커피', '식비', '카페'),
    BrandSeedEntry('투썸플레이스', '투썸플레이스', '식비', '카페'),
    BrandSeedEntry('투썸', '투썸플레이스', '식비', '카페'),
    BrandSeedEntry('커피빈', '커피빈', '식비', '카페'),
    BrandSeedEntry('폴바셋', '폴바셋', '식비', '카페'),
    BrandSeedEntry('할리스', '할리스커피', '식비', '카페'),
    BrandSeedEntry('탐앤탐스', '탐앤탐스', '식비', '카페'),
    BrandSeedEntry('공차', '공차', '식비', '카페'),
    BrandSeedEntry('더벤티', '더벤티', '식비', '카페'),
    BrandSeedEntry('파스쿠찌', '파스쿠찌', '식비', '카페'),
    BrandSeedEntry('뚜레쥬르', '뚜레쥬르', '식비', '디저트'),
    BrandSeedEntry('파리바게뜨', '파리바게뜨', '식비', '디저트'),
    BrandSeedEntry('파리바게트', '파리바게뜨', '식비', '디저트'),
    BrandSeedEntry('베스킨라빈스', '배스킨라빈스', '식비', '디저트'),
    BrandSeedEntry('배스킨라빈스', '배스킨라빈스', '식비', '디저트'),
    BrandSeedEntry('설빙', '설빙', '식비', '디저트'),
    BrandSeedEntry('크리스피크림', '크리스피크림도넛', '식비', '디저트'),
    BrandSeedEntry('던킨', '던킨', '식비', '디저트'),

    // ------------------------------------------------------ 패스트푸드 / 치킨 / 피자
    BrandSeedEntry('맥도날드', '맥도날드', '식비', '패스트푸드'),
    BrandSeedEntry('mcdonald', '맥도날드', '식비', '패스트푸드'),
    BrandSeedEntry('버거킹', '버거킹', '식비', '패스트푸드'),
    BrandSeedEntry('맘스터치', '맘스터치', '식비', '패스트푸드'),
    BrandSeedEntry('롯데리아', '롯데리아', '식비', '패스트푸드'),
    BrandSeedEntry('kfc', 'KFC', '식비', '패스트푸드'),
    BrandSeedEntry('써브웨이', '써브웨이', '식비', '패스트푸드'),
    BrandSeedEntry('subway', '써브웨이', '식비', '패스트푸드'),
    BrandSeedEntry('노브랜드버거', '노브랜드버거', '식비', '패스트푸드'),
    BrandSeedEntry('bhc', 'BHC치킨', '식비', '치킨/피자'),
    BrandSeedEntry('bbq', 'BBQ치킨', '식비', '치킨/피자'),
    BrandSeedEntry('교촌', '교촌치킨', '식비', '치킨/피자'),
    BrandSeedEntry('굽네', '굽네치킨', '식비', '치킨/피자'),
    BrandSeedEntry('네네치킨', '네네치킨', '식비', '치킨/피자'),
    BrandSeedEntry('푸라닭', '푸라닭', '식비', '치킨/피자'),
    BrandSeedEntry('도미노피자', '도미노피자', '식비', '치킨/피자'),
    BrandSeedEntry('피자헛', '피자헛', '식비', '치킨/피자'),
    BrandSeedEntry('미스터피자', '미스터피자', '식비', '치킨/피자'),
    BrandSeedEntry('반올림피자', '반올림피자', '식비', '치킨/피자'),

    // ------------------------------------------------------------------ 외식
    BrandSeedEntry('김밥천국', '김밥천국', '식비', '분식'),
    BrandSeedEntry('아딸', '아딸', '식비', '분식'),
    BrandSeedEntry('신전떡볶이', '신전떡볶이', '식비', '분식'),
    BrandSeedEntry('백종원의원조쌈밥', '원조쌈밥집', '식비', '한식'),
    BrandSeedEntry('한솥도시락', '한솥도시락', '식비', '한식'),
    BrandSeedEntry('본죽', '본죽', '식비', '한식'),
    BrandSeedEntry('새마을식당', '새마을식당', '식비', '한식'),
    BrandSeedEntry('홍콩반점', '홍콩반점0410', '식비', '중식'),
    BrandSeedEntry('중국집', '중식당', '식비', '중식'),
    BrandSeedEntry('스시', '스시', '식비', '일식'),
    BrandSeedEntry('이자카야', '이자카야', '식비', '주류'),
    BrandSeedEntry('아웃백', '아웃백스테이크하우스', '식비', '양식'),
    BrandSeedEntry('빕스', '빕스', '식비', '양식'),
    BrandSeedEntry('배스킨', '배스킨라빈스', '식비', '디저트'),

    // ------------------------------------------------------------------ 배달
    BrandSeedEntry('배달의민족', '배달의민족', '식비', '배달'),
    BrandSeedEntry('배민', '배달의민족', '식비', '배달'),
    BrandSeedEntry('우아한형제들', '배달의민족', '식비', '배달'),
    BrandSeedEntry('요기요', '요기요', '식비', '배달'),
    BrandSeedEntry('쿠팡이츠', '쿠팡이츠', '식비', '배달'),
    BrandSeedEntry('땡겨요', '땡겨요', '식비', '배달'),

    // -------------------------------------------------------- 편의점 / 마트 / 생활
    BrandSeedEntry('gs25', 'GS25', '생활', '편의점'),
    BrandSeedEntry('cu', 'CU', '생활', '편의점'),
    BrandSeedEntry('세븐일레븐', '세븐일레븐', '생활', '편의점'),
    BrandSeedEntry('7eleven', '세븐일레븐', '생활', '편의점'),
    BrandSeedEntry('이마트24', '이마트24', '생활', '편의점'),
    BrandSeedEntry('미니스톱', '미니스톱', '생활', '편의점'),
    BrandSeedEntry('이마트', '이마트', '생활', '마트'),
    BrandSeedEntry('홈플러스', '홈플러스', '생활', '마트'),
    BrandSeedEntry('롯데마트', '롯데마트', '생활', '마트'),
    BrandSeedEntry('코스트코', '코스트코', '생활', '마트'),
    BrandSeedEntry('costco', '코스트코', '생활', '마트'),
    BrandSeedEntry('노브랜드', '노브랜드', '생활', '마트'),
    BrandSeedEntry('하나로마트', '하나로마트', '생활', '마트'),
    BrandSeedEntry('다이소', '다이소', '생활', '생활용품'),
    BrandSeedEntry('무신사', '무신사', '쇼핑', '의류'),
    BrandSeedEntry('올리브영', '올리브영', '생활', '미용'),
    BrandSeedEntry('이케아', '이케아', '생활', '가구/인테리어'),
    BrandSeedEntry('ikea', '이케아', '생활', '가구/인테리어'),
    BrandSeedEntry('한샘', '한샘', '생활', '가구/인테리어'),

    // ------------------------------------------------------------- 온라인 쇼핑
    BrandSeedEntry('쿠팡', '쿠팡', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('coupang', '쿠팡', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('네이버페이', '네이버페이', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('11번가', '11번가', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('지마켓', 'G마켓', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('gmarket', 'G마켓', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('옥션', '옥션', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('위메프', '위메프', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('티몬', '티몬', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('알리익스프레스', '알리익스프레스', '쇼핑', '온라인쇼핑'),
    BrandSeedEntry('컬리', '마켓컬리', '생활', '마트'),
    BrandSeedEntry('오늘의집', '오늘의집', '생활', '가구/인테리어'),

    // ------------------------------------------------------------------ 교통
    BrandSeedEntry('카카오티', '카카오T', '교통', '택시'),
    BrandSeedEntry('kakaot', '카카오T', '교통', '택시'),
    BrandSeedEntry('카카오모빌리티', '카카오T', '교통', '택시'),
    BrandSeedEntry('타다', '타다', '교통', '택시'),
    BrandSeedEntry('우버', '우버', '교통', '택시'),
    BrandSeedEntry('티머니', '티머니', '교통', '대중교통'),
    BrandSeedEntry('캐시비', '캐시비', '교통', '대중교통'),
    BrandSeedEntry('코레일', '코레일', '교통', '기차/고속버스'),
    BrandSeedEntry('srt', 'SRT', '교통', '기차/고속버스'),
    BrandSeedEntry('gs칼텍스', 'GS칼텍스', '교통', '주유'),
    BrandSeedEntry('sk에너지', 'SK에너지', '교통', '주유'),
    BrandSeedEntry('현대오일뱅크', '현대오일뱅크', '교통', '주유'),
    BrandSeedEntry('s오일', 'S-OIL', '교통', '주유'),
    BrandSeedEntry('soil', 'S-OIL', '교통', '주유'),
    BrandSeedEntry('한국도로공사', '한국도로공사', '교통', '통행료'),
    BrandSeedEntry('하이패스', '하이패스', '교통', '통행료'),
    BrandSeedEntry('파킹클라우드', '아이파킹', '교통', '주차'),
    BrandSeedEntry('아이파킹', '아이파킹', '교통', '주차'),

    // ------------------------------------------------------------ 주거 / 통신
    BrandSeedEntry('skt', 'SKT', '주거/통신', '통신비'),
    BrandSeedEntry('sk텔레콤', 'SKT', '주거/통신', '통신비'),
    BrandSeedEntry('kt', 'KT', '주거/통신', '통신비'),
    BrandSeedEntry('lg유플러스', 'LG U+', '주거/통신', '통신비'),
    BrandSeedEntry('uplus', 'LG U+', '주거/통신', '통신비'),
    BrandSeedEntry('한국전력', '한국전력공사', '주거/통신', '공과금'),
    BrandSeedEntry('도시가스', '도시가스', '주거/통신', '공과금'),
    BrandSeedEntry('수도요금', '수도사업소', '주거/통신', '공과금'),

    // ------------------------------------------------------------ 구독 서비스
    BrandSeedEntry('넷플릭스', '넷플릭스', '주거/통신', '구독료'),
    BrandSeedEntry('netflix', '넷플릭스', '주거/통신', '구독료'),
    BrandSeedEntry('유튜브프리미엄', '유튜브 프리미엄', '주거/통신', '구독료'),
    BrandSeedEntry('youtubepremium', '유튜브 프리미엄', '주거/통신', '구독료'),
    BrandSeedEntry('googleyoutube', '유튜브 프리미엄', '주거/통신', '구독료'),
    BrandSeedEntry('티빙', '티빙', '주거/통신', '구독료'),
    BrandSeedEntry('웨이브', '웨이브', '주거/통신', '구독료'),
    BrandSeedEntry('디즈니플러스', '디즈니+', '주거/통신', '구독료'),
    BrandSeedEntry('왓챠', '왓챠', '주거/통신', '구독료'),
    BrandSeedEntry('스포티파이', '스포티파이', '주거/통신', '구독료'),
    BrandSeedEntry('멜론', '멜론', '주거/통신', '구독료'),
    BrandSeedEntry('지니뮤직', '지니뮤직', '주거/통신', '구독료'),
    BrandSeedEntry('chatgpt', 'ChatGPT', '주거/통신', '구독료'),
    BrandSeedEntry('openai', 'OpenAI', '주거/통신', '구독료'),
    BrandSeedEntry('claudeai', 'Claude', '주거/통신', '구독료'),
    BrandSeedEntry('anthropic', 'Claude', '주거/통신', '구독료'),
    BrandSeedEntry('githubcom', 'GitHub', '주거/통신', '구독료'),
    BrandSeedEntry('icloud', 'iCloud', '주거/통신', '구독료'),
    BrandSeedEntry('googlestorage', 'Google One', '주거/통신', '구독료'),

    // ---------------------------------------------------------- 의료 / 건강
    BrandSeedEntry('약국', '약국', '의료/건강', '약국'),
    BrandSeedEntry('의원', '의원', '의료/건강', '병원'),
    BrandSeedEntry('병원', '병원', '의료/건강', '병원'),
    BrandSeedEntry('치과', '치과', '의료/건강', '치과'),
    BrandSeedEntry('한의원', '한의원', '의료/건강', '병원'),
    BrandSeedEntry('피부과', '피부과', '의료/건강', '병원'),
    BrandSeedEntry('안과', '안과', '의료/건강', '병원'),
    BrandSeedEntry('헬스', '헬스장', '의료/건강', '운동/피트니스'),
    BrandSeedEntry('피트니스', '피트니스', '의료/건강', '운동/피트니스'),
    BrandSeedEntry('요가', '요가원', '의료/건강', '운동/피트니스'),
    BrandSeedEntry('필라테스', '필라테스', '의료/건강', '운동/피트니스'),

    // ---------------------------------------------------------- 문화 / 여가
    BrandSeedEntry('cgv', 'CGV', '문화/여가', '영화'),
    BrandSeedEntry('롯데시네마', '롯데시네마', '문화/여가', '영화'),
    BrandSeedEntry('메가박스', '메가박스', '문화/여가', '영화'),
    BrandSeedEntry('교보문고', '교보문고', '문화/여가', '도서'),
    BrandSeedEntry('예스24', 'YES24', '문화/여가', '도서'),
    BrandSeedEntry('yes24', 'YES24', '문화/여가', '도서'),
    BrandSeedEntry('알라딘', '알라딘', '문화/여가', '도서'),
    BrandSeedEntry('밀리의서재', '밀리의 서재', '문화/여가', '도서'),
    BrandSeedEntry('스팀', 'Steam', '문화/여가', '게임'),
    BrandSeedEntry('steamgames', 'Steam', '문화/여가', '게임'),
    BrandSeedEntry('플레이스테이션', '플레이스테이션', '문화/여가', '게임'),
    BrandSeedEntry('닌텐도', '닌텐도', '문화/여가', '게임'),
    BrandSeedEntry('야놀자', '야놀자', '문화/여가', '숙박'),
    BrandSeedEntry('여기어때', '여기어때', '문화/여가', '숙박'),
    BrandSeedEntry('아고다', '아고다', '문화/여가', '숙박'),
    BrandSeedEntry('agoda', '아고다', '문화/여가', '숙박'),
    BrandSeedEntry('에어비앤비', '에어비앤비', '문화/여가', '숙박'),
    BrandSeedEntry('airbnb', '에어비앤비', '문화/여가', '숙박'),
    BrandSeedEntry('인터파크', '인터파크', '문화/여가', '공연/전시'),
    BrandSeedEntry('멜론티켓', '멜론티켓', '문화/여가', '공연/전시'),

    // ---------------------------------------------------------------- 교육
    BrandSeedEntry('인프런', '인프런', '교육', '온라인강의'),
    BrandSeedEntry('패스트캠퍼스', '패스트캠퍼스', '교육', '온라인강의'),
    BrandSeedEntry('udemy', 'Udemy', '교육', '온라인강의'),
    BrandSeedEntry('학원', '학원', '교육', '학원'),

    // ---------------------------------------------------------- 전자 / 기기
    BrandSeedEntry('애플', 'Apple', '쇼핑', '전자기기'),
    BrandSeedEntry('apple', 'Apple', '쇼핑', '전자기기'),
    BrandSeedEntry('삼성전자', '삼성전자', '쇼핑', '전자기기'),
    BrandSeedEntry('하이마트', '롯데하이마트', '쇼핑', '전자기기'),
    BrandSeedEntry('전자랜드', '전자랜드', '쇼핑', '전자기기'),
  ];
}
