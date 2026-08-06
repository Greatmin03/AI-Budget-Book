import '../../../features/merchants/domain/entities/brand_definition.dart';
import '../db_schema.dart';

/// 내장 브랜드 사전.
///
/// **대표 브랜드(canonical) 하나에 표기(alias) 여럿** 구조다.
/// 은행·카드사가 같은 브랜드를 서로 다르게 보내기 때문이다.
///
/// ```
/// 씨유강원대제3학생 · 씨유(CU) 춘천 백령점 · CU 춘천점  ->  CU
/// 지에스25춘천애막골 · 지에스25(GS25) 춘천              ->  GS25
/// 메가MGC커피강원대점 · 메가커피춘천후평점              ->  메가MGC커피
/// ```
///
/// 여기 있는 브랜드는 **카카오 API 도 LLM 도 호출하지 않는다.**
/// 새 표기가 보이면 [BrandDefinition.aliases] 에 한 줄 추가하면 된다.
///
/// alias 는 정규화(소문자 + 공백/특수문자 제거)되어 비교되므로
/// 대소문자나 띄어쓰기를 신경 쓰지 않아도 된다.
class BrandSeed {
  const BrandSeed._();

  static const List<BrandDefinition> definitions = <BrandDefinition>[
    // ------------------------------------------------------------
    // 식비 / 카페
    BrandDefinition(
      canonical: '스타벅스',
      aliases: <String>['스타벅스', 'starbucks', '스타벅스코리아'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '컴포즈커피',
      aliases: <String>['컴포즈커피'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '빽다방',
      aliases: <String>['빽다방'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '이디야커피',
      aliases: <String>['이디야', '이디야커피'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '투썸플레이스',
      aliases: <String>['투썸플레이스', '투썸'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '커피빈',
      aliases: <String>['커피빈'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '폴바셋',
      aliases: <String>['폴바셋'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '할리스커피',
      aliases: <String>['할리스'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '탐앤탐스',
      aliases: <String>['탐앤탐스'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '공차',
      aliases: <String>['공차'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '더벤티',
      aliases: <String>['더벤티'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '파스쿠찌',
      aliases: <String>['파스쿠찌'],
      category: '식비',
      subcategory: '카페',
    ),
    BrandDefinition(
      canonical: '메가MGC커피',
      aliases: <String>['메가mgc커피', '메가커피', '메가엠지씨커피', 'megamgccoffee', 'mega mgc coffee'],
      category: '식비',
      subcategory: '카페',
    ),
    // ------------------------------------------------------------
    // 식비 / 디저트
    BrandDefinition(
      canonical: '뚜레쥬르',
      aliases: <String>['뚜레쥬르'],
      category: '식비',
      subcategory: '디저트',
    ),
    BrandDefinition(
      canonical: '파리바게뜨',
      aliases: <String>['파리바게뜨', '파리바게트'],
      category: '식비',
      subcategory: '디저트',
    ),
    BrandDefinition(
      canonical: '배스킨라빈스',
      aliases: <String>['베스킨라빈스', '배스킨라빈스', '배스킨', '배라'],
      category: '식비',
      subcategory: '디저트',
    ),
    BrandDefinition(
      canonical: '설빙',
      aliases: <String>['설빙'],
      category: '식비',
      subcategory: '디저트',
    ),
    BrandDefinition(
      canonical: '크리스피크림도넛',
      aliases: <String>['크리스피크림'],
      category: '식비',
      subcategory: '디저트',
    ),
    BrandDefinition(
      canonical: '던킨',
      aliases: <String>['던킨'],
      category: '식비',
      subcategory: '디저트',
    ),
    // ------------------------------------------------------------
    // 식비 / 패스트푸드
    BrandDefinition(
      canonical: '맥도날드',
      aliases: <String>['맥도날드', 'mcdonald', '한국맥도날드'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    BrandDefinition(
      canonical: '버거킹',
      aliases: <String>['버거킹'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    BrandDefinition(
      canonical: '맘스터치',
      aliases: <String>['맘스터치'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    BrandDefinition(
      canonical: '롯데리아',
      aliases: <String>['롯데리아'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    BrandDefinition(
      canonical: 'KFC',
      aliases: <String>['kfc'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    BrandDefinition(
      canonical: '써브웨이',
      aliases: <String>['써브웨이', 'subway'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    BrandDefinition(
      canonical: '노브랜드버거',
      aliases: <String>['노브랜드버거'],
      category: '식비',
      subcategory: '패스트푸드',
    ),
    // ------------------------------------------------------------
    // 식비 / 치킨/피자
    BrandDefinition(
      canonical: 'BHC치킨',
      aliases: <String>['bhc'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: 'BBQ치킨',
      aliases: <String>['bbq'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '교촌치킨',
      aliases: <String>['교촌'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '굽네치킨',
      aliases: <String>['굽네'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '네네치킨',
      aliases: <String>['네네치킨'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '푸라닭',
      aliases: <String>['푸라닭'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '도미노피자',
      aliases: <String>['도미노피자'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '피자헛',
      aliases: <String>['피자헛'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '미스터피자',
      aliases: <String>['미스터피자'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    BrandDefinition(
      canonical: '반올림피자',
      aliases: <String>['반올림피자'],
      category: '식비',
      subcategory: '치킨/피자',
    ),
    // ------------------------------------------------------------
    // 식비 / 분식
    BrandDefinition(
      canonical: '김밥천국',
      aliases: <String>['김밥천국'],
      category: '식비',
      subcategory: '분식',
    ),
    BrandDefinition(
      canonical: '아딸',
      aliases: <String>['아딸'],
      category: '식비',
      subcategory: '분식',
    ),
    BrandDefinition(
      canonical: '신전떡볶이',
      aliases: <String>['신전떡볶이'],
      category: '식비',
      subcategory: '분식',
    ),
    // ------------------------------------------------------------
    // 식비 / 한식
    BrandDefinition(
      canonical: '원조쌈밥집',
      aliases: <String>['백종원의원조쌈밥'],
      category: '식비',
      subcategory: '한식',
    ),
    BrandDefinition(
      canonical: '한솥도시락',
      aliases: <String>['한솥도시락'],
      category: '식비',
      subcategory: '한식',
    ),
    BrandDefinition(
      canonical: '본죽',
      aliases: <String>['본죽'],
      category: '식비',
      subcategory: '한식',
    ),
    BrandDefinition(
      canonical: '새마을식당',
      aliases: <String>['새마을식당'],
      category: '식비',
      subcategory: '한식',
    ),
    // ------------------------------------------------------------
    // 식비 / 중식
    BrandDefinition(
      canonical: '홍콩반점0410',
      aliases: <String>['홍콩반점'],
      category: '식비',
      subcategory: '중식',
    ),
    BrandDefinition(
      canonical: '중식당',
      aliases: <String>['중국집'],
      category: '식비',
      subcategory: '중식',
    ),
    // ------------------------------------------------------------
    // 식비 / 일식
    BrandDefinition(
      canonical: '스시',
      aliases: <String>['스시'],
      category: '식비',
      subcategory: '일식',
    ),
    // ------------------------------------------------------------
    // 식비 / 주류
    BrandDefinition(
      canonical: '이자카야',
      aliases: <String>['이자카야'],
      category: '식비',
      subcategory: '주류',
    ),
    // ------------------------------------------------------------
    // 식비 / 양식
    BrandDefinition(
      canonical: '아웃백스테이크하우스',
      aliases: <String>['아웃백'],
      category: '식비',
      subcategory: '양식',
    ),
    BrandDefinition(
      canonical: '빕스',
      aliases: <String>['빕스'],
      category: '식비',
      subcategory: '양식',
    ),
    // ------------------------------------------------------------
    // 식비 / 배달
    BrandDefinition(
      canonical: '배달의민족',
      aliases: <String>['배달의민족', '배민', '우아한형제들'],
      category: '식비',
      subcategory: '배달',
    ),
    BrandDefinition(
      canonical: '요기요',
      aliases: <String>['요기요'],
      category: '식비',
      subcategory: '배달',
    ),
    BrandDefinition(
      canonical: '쿠팡이츠',
      aliases: <String>['쿠팡이츠'],
      category: '식비',
      subcategory: '배달',
    ),
    BrandDefinition(
      canonical: '땡겨요',
      aliases: <String>['땡겨요'],
      category: '식비',
      subcategory: '배달',
    ),
    // ------------------------------------------------------------
    // 생활 / 편의점
    BrandDefinition(
      canonical: 'GS25',
      aliases: <String>['gs25', '지에스25', '지에스이십오'],
      category: '생활',
      subcategory: '편의점',
    ),
    BrandDefinition(
      canonical: 'CU',
      aliases: <String>['cu', '씨유'],
      category: '생활',
      subcategory: '편의점',
    ),
    BrandDefinition(
      canonical: '세븐일레븐',
      aliases: <String>['세븐일레븐', '7eleven', '7일레븐'],
      category: '생활',
      subcategory: '편의점',
    ),
    BrandDefinition(
      canonical: '이마트24',
      aliases: <String>['이마트24', '이마트이십사'],
      category: '생활',
      subcategory: '편의점',
    ),
    BrandDefinition(
      canonical: '미니스톱',
      aliases: <String>['미니스톱'],
      category: '생활',
      subcategory: '편의점',
    ),
    // ------------------------------------------------------------
    // 생활 / 마트
    BrandDefinition(
      canonical: '이마트',
      aliases: <String>['이마트'],
      category: '생활',
      subcategory: '마트',
    ),
    BrandDefinition(
      canonical: '홈플러스',
      aliases: <String>['홈플러스'],
      category: '생활',
      subcategory: '마트',
    ),
    BrandDefinition(
      canonical: '롯데마트',
      aliases: <String>['롯데마트'],
      category: '생활',
      subcategory: '마트',
    ),
    BrandDefinition(
      canonical: '코스트코',
      aliases: <String>['코스트코', 'costco'],
      category: '생활',
      subcategory: '마트',
    ),
    BrandDefinition(
      canonical: '노브랜드',
      aliases: <String>['노브랜드'],
      category: '생활',
      subcategory: '마트',
    ),
    BrandDefinition(
      canonical: '하나로마트',
      aliases: <String>['하나로마트'],
      category: '생활',
      subcategory: '마트',
    ),
    BrandDefinition(
      canonical: '마켓컬리',
      aliases: <String>['컬리'],
      category: '생활',
      subcategory: '마트',
    ),
    // ------------------------------------------------------------
    // 생활 / 생활용품
    BrandDefinition(
      canonical: '다이소',
      aliases: <String>['다이소', '아성다이소'],
      category: '생활',
      subcategory: '생활용품',
    ),
    // ------------------------------------------------------------
    // 쇼핑 / 의류
    BrandDefinition(
      canonical: '무신사',
      aliases: <String>['무신사'],
      category: '쇼핑',
      subcategory: '의류',
    ),
    // ------------------------------------------------------------
    // 생활 / 미용
    BrandDefinition(
      canonical: '올리브영',
      aliases: <String>['올리브영', '씨제이올리브영'],
      category: '생활',
      subcategory: '미용',
    ),
    // ------------------------------------------------------------
    // 생활 / 가구/인테리어
    BrandDefinition(
      canonical: '이케아',
      aliases: <String>['이케아', 'ikea'],
      category: '생활',
      subcategory: '가구/인테리어',
    ),
    BrandDefinition(
      canonical: '한샘',
      aliases: <String>['한샘'],
      category: '생활',
      subcategory: '가구/인테리어',
    ),
    BrandDefinition(
      canonical: '오늘의집',
      aliases: <String>['오늘의집'],
      category: '생활',
      subcategory: '가구/인테리어',
    ),
    // ------------------------------------------------------------
    // 쇼핑 / 온라인쇼핑
    BrandDefinition(
      canonical: '쿠팡',
      aliases: <String>['쿠팡', 'coupang'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: '네이버페이',
      aliases: <String>['네이버페이'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: '11번가',
      aliases: <String>['11번가'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: 'G마켓',
      aliases: <String>['지마켓', 'gmarket'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: '옥션',
      aliases: <String>['옥션'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: '위메프',
      aliases: <String>['위메프'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: '티몬',
      aliases: <String>['티몬'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    BrandDefinition(
      canonical: '알리익스프레스',
      aliases: <String>['알리익스프레스'],
      category: '쇼핑',
      subcategory: '온라인쇼핑',
    ),
    // ------------------------------------------------------------
    // 교통 / 택시
    BrandDefinition(
      canonical: '카카오T',
      aliases: <String>['카카오티', 'kakaot', '카카오모빌리티'],
      category: '교통',
      subcategory: '택시',
    ),
    BrandDefinition(
      canonical: '타다',
      aliases: <String>['타다'],
      category: '교통',
      subcategory: '택시',
    ),
    BrandDefinition(
      canonical: '우버',
      aliases: <String>['우버'],
      category: '교통',
      subcategory: '택시',
    ),
    // ------------------------------------------------------------
    // 교통 / 대중교통
    BrandDefinition(
      canonical: '티머니',
      aliases: <String>['티머니'],
      category: '교통',
      subcategory: '대중교통',
    ),
    BrandDefinition(
      canonical: '캐시비',
      aliases: <String>['캐시비'],
      category: '교통',
      subcategory: '대중교통',
    ),
    // ------------------------------------------------------------
    // 교통 / 기차/고속버스
    BrandDefinition(
      canonical: '코레일',
      aliases: <String>['코레일'],
      category: '교통',
      subcategory: '기차/고속버스',
    ),
    BrandDefinition(
      canonical: 'SRT',
      aliases: <String>['srt'],
      category: '교통',
      subcategory: '기차/고속버스',
    ),
    // ------------------------------------------------------------
    // 교통 / 주유
    BrandDefinition(
      canonical: 'GS칼텍스',
      aliases: <String>['gs칼텍스'],
      category: '교통',
      subcategory: '주유',
    ),
    BrandDefinition(
      canonical: 'SK에너지',
      aliases: <String>['sk에너지'],
      category: '교통',
      subcategory: '주유',
    ),
    BrandDefinition(
      canonical: '현대오일뱅크',
      aliases: <String>['현대오일뱅크'],
      category: '교통',
      subcategory: '주유',
    ),
    BrandDefinition(
      canonical: 'S-OIL',
      aliases: <String>['s오일', 'soil'],
      category: '교통',
      subcategory: '주유',
    ),
    // ------------------------------------------------------------
    // 교통 / 통행료
    BrandDefinition(
      canonical: '한국도로공사',
      aliases: <String>['한국도로공사'],
      category: '교통',
      subcategory: '통행료',
    ),
    BrandDefinition(
      canonical: '하이패스',
      aliases: <String>['하이패스'],
      category: '교통',
      subcategory: '통행료',
    ),
    // ------------------------------------------------------------
    // 교통 / 주차
    BrandDefinition(
      canonical: '아이파킹',
      aliases: <String>['파킹클라우드', '아이파킹'],
      category: '교통',
      subcategory: '주차',
    ),
    // ------------------------------------------------------------
    // 주거/통신 / 통신비
    BrandDefinition(
      canonical: 'SKT',
      aliases: <String>['skt', 'sk텔레콤'],
      category: '주거/통신',
      subcategory: '통신비',
    ),
    BrandDefinition(
      canonical: 'KT',
      aliases: <String>['kt'],
      category: '주거/통신',
      subcategory: '통신비',
    ),
    BrandDefinition(
      canonical: 'LG U+',
      aliases: <String>['lg유플러스', 'uplus'],
      category: '주거/통신',
      subcategory: '통신비',
    ),
    // ------------------------------------------------------------
    // 주거/통신 / 공과금
    BrandDefinition(
      canonical: '한국전력공사',
      aliases: <String>['한국전력'],
      category: '주거/통신',
      subcategory: '공과금',
    ),
    BrandDefinition(
      canonical: '도시가스',
      aliases: <String>['도시가스'],
      category: '주거/통신',
      subcategory: '공과금',
    ),
    BrandDefinition(
      canonical: '수도사업소',
      aliases: <String>['수도요금'],
      category: '주거/통신',
      subcategory: '공과금',
    ),
    // ------------------------------------------------------------
    // 주거/통신 / 구독료
    BrandDefinition(
      canonical: '넷플릭스',
      aliases: <String>['넷플릭스', 'netflix'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '유튜브 프리미엄',
      aliases: <String>['유튜브프리미엄', 'youtubepremium', 'googleyoutube'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '티빙',
      aliases: <String>['티빙'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '웨이브',
      aliases: <String>['웨이브'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '디즈니+',
      aliases: <String>['디즈니플러스'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '왓챠',
      aliases: <String>['왓챠'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '스포티파이',
      aliases: <String>['스포티파이'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '멜론',
      aliases: <String>['멜론'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: '지니뮤직',
      aliases: <String>['지니뮤직'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: 'ChatGPT',
      aliases: <String>['chatgpt'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: 'OpenAI',
      aliases: <String>['openai'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: 'Claude',
      aliases: <String>['claudeai', 'anthropic'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: 'GitHub',
      aliases: <String>['githubcom'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: 'iCloud',
      aliases: <String>['icloud'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    BrandDefinition(
      canonical: 'Google One',
      aliases: <String>['googlestorage'],
      category: '주거/통신',
      subcategory: '구독료',
    ),
    // ------------------------------------------------------------
    // 의료/건강 / 약국
    BrandDefinition(
      canonical: '약국',
      aliases: <String>['약국'],
      category: '의료/건강',
      subcategory: '약국',
    ),
    // ------------------------------------------------------------
    // 의료/건강 / 병원
    BrandDefinition(
      canonical: '의원',
      aliases: <String>['의원'],
      category: '의료/건강',
      subcategory: '병원',
    ),
    BrandDefinition(
      canonical: '병원',
      aliases: <String>['병원'],
      category: '의료/건강',
      subcategory: '병원',
    ),
    BrandDefinition(
      canonical: '한의원',
      aliases: <String>['한의원'],
      category: '의료/건강',
      subcategory: '병원',
    ),
    BrandDefinition(
      canonical: '피부과',
      aliases: <String>['피부과'],
      category: '의료/건강',
      subcategory: '병원',
    ),
    BrandDefinition(
      canonical: '안과',
      aliases: <String>['안과'],
      category: '의료/건강',
      subcategory: '병원',
    ),
    // ------------------------------------------------------------
    // 의료/건강 / 치과
    BrandDefinition(
      canonical: '치과',
      aliases: <String>['치과'],
      category: '의료/건강',
      subcategory: '치과',
    ),
    // ------------------------------------------------------------
    // 의료/건강 / 운동/피트니스
    BrandDefinition(
      canonical: '헬스장',
      aliases: <String>['헬스'],
      category: '의료/건강',
      subcategory: '운동/피트니스',
    ),
    BrandDefinition(
      canonical: '피트니스',
      aliases: <String>['피트니스'],
      category: '의료/건강',
      subcategory: '운동/피트니스',
    ),
    BrandDefinition(
      canonical: '요가원',
      aliases: <String>['요가'],
      category: '의료/건강',
      subcategory: '운동/피트니스',
    ),
    BrandDefinition(
      canonical: '필라테스',
      aliases: <String>['필라테스'],
      category: '의료/건강',
      subcategory: '운동/피트니스',
    ),
    // ------------------------------------------------------------
    // 문화/여가 / 영화
    BrandDefinition(
      canonical: 'CGV',
      aliases: <String>['cgv'],
      category: '문화/여가',
      subcategory: '영화',
    ),
    BrandDefinition(
      canonical: '롯데시네마',
      aliases: <String>['롯데시네마'],
      category: '문화/여가',
      subcategory: '영화',
    ),
    BrandDefinition(
      canonical: '메가박스',
      aliases: <String>['메가박스'],
      category: '문화/여가',
      subcategory: '영화',
    ),
    // ------------------------------------------------------------
    // 문화/여가 / 도서
    BrandDefinition(
      canonical: '교보문고',
      aliases: <String>['교보문고'],
      category: '문화/여가',
      subcategory: '도서',
    ),
    BrandDefinition(
      canonical: 'YES24',
      aliases: <String>['예스24', 'yes24'],
      category: '문화/여가',
      subcategory: '도서',
    ),
    BrandDefinition(
      canonical: '알라딘',
      aliases: <String>['알라딘'],
      category: '문화/여가',
      subcategory: '도서',
    ),
    BrandDefinition(
      canonical: '밀리의 서재',
      aliases: <String>['밀리의서재'],
      category: '문화/여가',
      subcategory: '도서',
    ),
    // ------------------------------------------------------------
    // 문화/여가 / 게임
    BrandDefinition(
      canonical: 'Steam',
      aliases: <String>['스팀', 'steamgames'],
      category: '문화/여가',
      subcategory: '게임',
    ),
    BrandDefinition(
      canonical: '플레이스테이션',
      aliases: <String>['플레이스테이션'],
      category: '문화/여가',
      subcategory: '게임',
    ),
    BrandDefinition(
      canonical: '닌텐도',
      aliases: <String>['닌텐도'],
      category: '문화/여가',
      subcategory: '게임',
    ),
    // ------------------------------------------------------------
    // 문화/여가 / 숙박
    BrandDefinition(
      canonical: '야놀자',
      aliases: <String>['야놀자'],
      category: '문화/여가',
      subcategory: '숙박',
    ),
    BrandDefinition(
      canonical: '여기어때',
      aliases: <String>['여기어때'],
      category: '문화/여가',
      subcategory: '숙박',
    ),
    BrandDefinition(
      canonical: '아고다',
      aliases: <String>['아고다', 'agoda'],
      category: '문화/여가',
      subcategory: '숙박',
    ),
    BrandDefinition(
      canonical: '에어비앤비',
      aliases: <String>['에어비앤비', 'airbnb'],
      category: '문화/여가',
      subcategory: '숙박',
    ),
    // ------------------------------------------------------------
    // 문화/여가 / 공연/전시
    BrandDefinition(
      canonical: '인터파크',
      aliases: <String>['인터파크'],
      category: '문화/여가',
      subcategory: '공연/전시',
    ),
    BrandDefinition(
      canonical: '멜론티켓',
      aliases: <String>['멜론티켓'],
      category: '문화/여가',
      subcategory: '공연/전시',
    ),
    // ------------------------------------------------------------
    // 교육 / 온라인강의
    BrandDefinition(
      canonical: '인프런',
      aliases: <String>['인프런'],
      category: '교육',
      subcategory: '온라인강의',
    ),
    BrandDefinition(
      canonical: '패스트캠퍼스',
      aliases: <String>['패스트캠퍼스'],
      category: '교육',
      subcategory: '온라인강의',
    ),
    BrandDefinition(
      canonical: 'Udemy',
      aliases: <String>['udemy'],
      category: '교육',
      subcategory: '온라인강의',
    ),
    // ------------------------------------------------------------
    // 교육 / 학원
    BrandDefinition(
      canonical: '학원',
      aliases: <String>['학원'],
      category: '교육',
      subcategory: '학원',
    ),
    // ------------------------------------------------------------
    // 쇼핑 / 전자기기
    BrandDefinition(
      canonical: 'Apple',
      aliases: <String>['애플', 'apple'],
      category: '쇼핑',
      subcategory: '전자기기',
    ),
    BrandDefinition(
      canonical: '삼성전자',
      aliases: <String>['삼성전자'],
      category: '쇼핑',
      subcategory: '전자기기',
    ),
    BrandDefinition(
      canonical: '롯데하이마트',
      aliases: <String>['하이마트'],
      category: '쇼핑',
      subcategory: '전자기기',
    ),
    BrandDefinition(
      canonical: '전자랜드',
      aliases: <String>['전자랜드'],
      category: '쇼핑',
      subcategory: '전자기기',
    ),
  ];

  /// `brand_rules` 테이블에 넣을 행. alias 하나가 한 행이 된다.
  ///
  /// DB 매칭(부분일치)은 그대로 두고, 사전만 대표 브랜드 기준으로
  /// 관리하기 위한 변환이다.
  static List<Map<String, Object?>> get rows => <Map<String, Object?>>[
        for (final BrandDefinition definition in definitions)
          for (final String alias in definition.normalizedAliases)
            <String, Object?>{
              DbSchema.brPattern: alias,
              DbSchema.brBrand: definition.canonical,
              DbSchema.brCategory: definition.category,
              DbSchema.brSubcategory: definition.subcategory,
              DbSchema.brPriority: definition.priority,
              DbSchema.brSource: 'seed',
            },
      ];
}
