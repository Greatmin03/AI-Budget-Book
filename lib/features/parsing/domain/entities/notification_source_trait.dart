/// 알림을 보낸 앱이 **무엇을 잘 주는가.**
///
/// 같은 결제를 여러 앱이 알린다. 그런데 담고 있는 정보가 서로 다르다.
///
/// ```
/// 토스  더스윙                          ← 브랜드가 정확하다
/// KB    ... 통신판매_NIC 체크카드출금 3,000 잔액1,264,862
///                                      ↑ 계좌·잔액이 있다
/// ```
///
/// 둘 중 하나를 버리면 반드시 무언가를 잃는다. 그래서 **버리지 않고 합친다.**
/// 이 표는 합칠 때 어느 쪽 값을 쓸지 정하는 근거다.
enum NotificationSourceTrait {
  /// 간편결제/송금 앱. 가맹점 이름을 사람이 읽을 수 있는 형태로 준다.
  ///
  /// 계좌번호나 잔액은 주지 않는다.
  wallet(brandQuality: 2, providesAccountDetails: false),

  /// 은행 앱. 계좌번호와 잔액을 준다.
  ///
  /// 가맹점 이름은 카드 전표 그대로라 잘리거나(`쿠팡(쿠페 `)
  /// 알아볼 수 없는 경우(`통신판매_NIC`)가 있다.
  bank(brandQuality: 1, providesAccountDetails: true),

  /// 카드사 앱. 가맹점 이름은 은행보다 낫지만 계좌 정보는 없다.
  cardIssuer(brandQuality: 1, providesAccountDetails: false),

  /// 모르는 앱. 아무것도 우선하지 않는다.
  unknown(brandQuality: 0, providesAccountDetails: false);

  const NotificationSourceTrait({
    required this.brandQuality,
    required this.providesAccountDetails,
  });

  /// 브랜드 이름을 얼마나 믿을 수 있는가. 클수록 좋다.
  ///
  /// 병합할 때 이 값이 큰 쪽의 가맹점명을 남긴다.
  final int brandQuality;

  /// 계좌번호·잔액을 주는가.
  final bool providesAccountDetails;

  /// 패키지 이름으로 특성을 찾는다.
  ///
  /// 모르는 앱은 [unknown] 이다. 추측해서 우선순위를 주면 엉뚱한 쪽의
  /// 가맹점명이 남는다.
  static NotificationSourceTrait of(String? packageName) {
    final String p = (packageName ?? '').toLowerCase();
    if (p.isEmpty) return unknown;

    for (final MapEntry<String, NotificationSourceTrait> entry
        in _byPackage.entries) {
      if (p.contains(entry.key)) return entry.value;
    }
    return unknown;
  }

  /// 패키지 조각 -> 특성.
  ///
  /// 정확히 일치시키지 않고 조각으로 찾는다. 같은 앱이 기기/버전에 따라
  /// 조금씩 다른 패키지명을 쓰는 경우가 있다.
  static const Map<String, NotificationSourceTrait> _byPackage =
      <String, NotificationSourceTrait>{
    // 지갑/간편결제
    'republica.toss': wallet,
    'kakaopay': wallet,
    'naverfin': wallet,
    'payco': wallet,

    // 은행
    'kbstar': bank,
    'shinhan.s?bank': bank,
    'wooribank': bank,
    'nonghyup': bank,
    'ibk': bank,
    'hanabank': bank,
    'kakaobank': bank,
    'kbanknow': bank,

    // 카드사
    'kbcard': cardIssuer,
    'shinhancard': cardIssuer,
    'samsungcard': cardIssuer,
    'hyundaicard': cardIssuer,
    'lottecard': cardIssuer,
    'hanacard': cardIssuer,
    'bccard': cardIssuer,
  };
}
