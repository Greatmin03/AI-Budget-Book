/// 알림을 보내는 앱(패키지) -> 카드사/결제수단 매핑.
///
/// Notification Listener 는 모든 알림을 볼 수 있으므로,
/// 여기 등록된 패키지 또는 "결제 알림처럼 보이는 문자열" 만 처리한다.
class PaymentSources {
  const PaymentSources._();

  /// 패키지명 -> 표시할 카드사/결제수단 이름.
  static const Map<String, String> packageToIssuer = <String, String>{
    // 카드사
    'com.kbcard.cxh.appcard': 'KB국민카드',
    'com.kbstar.kbbank': 'KB국민은행',
    'com.kbstar.starpush': 'KB국민카드',
    'com.shinhancard.smartshinhan': '신한카드',
    'com.shinhan.smartcaremgr': '신한카드',
    'com.shinhan.sbanking': '신한은행',
    'kr.co.samsungcard.mpocket': '삼성카드',
    'com.samsung.android.spay': '삼성페이',
    'com.hyundaicard.appcard': '현대카드',
    'com.lcacApp': '롯데카드',
    'com.lotte.lpay': '롯데카드',
    'com.hanaskcard.paycla': '하나카드',
    'com.hanaskcard.rocomo.potal': '하나카드',
    'com.wooricard.smartapp': '우리카드',
    'com.wooribank.smart.npib': '우리은행',
    'com.wooribank.smart.mwib': '우리은행',
    'nh.smart.card': 'NH농협카드',
    'nh.smart.nhallonepay': 'NH농협카드',
    'nh.smart': 'NH농협은행',
    'com.citibank.cardapp': '씨티카드',
    'com.ibk.android.ionebank': 'IBK기업은행',
    'com.kbankwith.smartbank': '케이뱅크',
    'com.kakaobank.channel': '카카오뱅크',

    // 간편결제 / 페이
    'com.kakao.talk': '카카오페이',
    'com.kakaopay.app': '카카오페이',
    'viva.republica.toss': '토스',
    'com.nhnent.payapp': '페이코',
    'com.nhn.android.search': '네이버페이',
    'com.naver.android.ndrive': '네이버페이',
    'com.ssg.serviceapp.android.egiftcertificate': 'SSG페이',
    'com.lgcns.mobilepay': 'LG페이',
    'com.google.android.apps.walletnfcrel': 'Google Pay',

    // 문자(SMS) 앱 — 카드 승인 문자가 오는 경로
    'com.samsung.android.messaging': 'SMS',
    'com.google.android.apps.messaging': 'SMS',
  };

  /// 알림 본문에 이 중 하나라도 있어야 결제 알림 후보로 본다.
  static const List<String> approvalKeywords = <String>[
    '승인',
    '결제',
    '출금',
    '사용',
    '취소',
    '거래',
    '지불',
  ];

  /// 취소/환불 거래 판별 키워드.
  static const List<String> cancelKeywords = <String>[
    '취소',
    '승인취소',
    '환불',
    '반품',
  ];

  /// 결제 알림이 아닌데 키워드가 겹치는 알림을 걸러내기 위한 제외 키워드.
  ///
  /// 실제 승인 알림에는 거의 등장하지 않는 단어만 넣는다.
  /// ('안내', '무료', '신청' 처럼 흔한 단어를 넣으면 정상 결제를 놓친다.)
  static const List<String> hardExcludeKeywords = <String>[
    '이벤트',
    '광고',
    '쿠폰',
    '혜택',
    '인증번호',
    '본인확인',
    '할부전환',
    '명세서',
    '청구서',
    '당첨',
    '무이자',
    '수신거부',
  ];

  static bool isKnownPackage(String? packageName) =>
      packageName != null && packageToIssuer.containsKey(packageName);

  static String? issuerOf(String? packageName) =>
      packageName == null ? null : packageToIssuer[packageName];

  /// 텍스트에서 카드사 이름을 직접 찾아본다(SMS 처럼 패키지로 알 수 없는 경우).
  static String? issuerFromText(String text) {
    for (final String issuer in _issuerNamesByLength) {
      if (text.contains(issuer)) return issuer;
    }
    return null;
  }

  /// 텍스트 매칭용 카드사 표기 목록(긴 이름부터 검사).
  static final List<String> _issuerNamesByLength = <String>[
    'KB국민카드',
    'KB국민',
    '신한카드',
    '삼성카드',
    '현대카드',
    '롯데카드',
    '하나카드',
    '우리카드',
    'NH농협카드',
    '농협카드',
    '씨티카드',
    '카카오페이',
    '카카오뱅크',
    '네이버페이',
    '토스뱅크',
    '토스',
    '페이코',
    '삼성페이',
    'SSG페이',
    '전북카드',
    '광주카드',
    '수협카드',
    '새마을금고',
  ]..sort((String a, String b) => b.length.compareTo(a.length));
}
