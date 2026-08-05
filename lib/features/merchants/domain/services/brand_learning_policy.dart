import '../../../parsing/domain/entities/parsed_payment.dart';

/// 브랜드 자동 학습 허용 여부.
enum BrandLearningStance {
  /// 학습해도 안전하다. (가맹점 결제)
  allowed,

  /// 학습이 가능하지만 위험하다. 기본값을 끄고 경고를 보여 준다.
  ///
  /// 사람 이름처럼 보이지만 실제 브랜드일 수도 있는 경우
  /// (`이마트`, `김밥천국` 처럼 성씨로 시작하는 상호가 실제로 많다).
  /// 자동으로 막아 버리면 정상 브랜드를 학습하지 못하므로 판단은 사용자에게 맡긴다.
  discouraged,

  /// 학습을 금지한다. UI 에서 선택 자체를 비활성화한다.
  blocked,
}

/// 학습 정책 판단 결과.
class BrandLearningDecision {
  const BrandLearningDecision({
    required this.stance,
    this.reason,
    this.detail,
  });

  const BrandLearningDecision.allowed()
      : stance = BrandLearningStance.allowed,
        reason = null,
        detail = null;

  final BrandLearningStance stance;

  /// 사용자에게 보여 줄 한 줄 설명.
  final String? reason;

  /// 왜 그런지에 대한 부연.
  final String? detail;

  bool get isBlocked => stance == BrandLearningStance.blocked;
  bool get isDiscouraged => stance == BrandLearningStance.discouraged;

  /// 학습 스위치를 조작할 수 있는가.
  bool get canToggle => !isBlocked;

  /// 학습 스위치의 기본값.
  bool get defaultsOn => stance == BrandLearningStance.allowed;
}

/// **브랜드 학습을 허용할지 판단하는 유일한 지점.**
///
/// 이 정책이 존재하는 이유는 하나의 사고를 막기 위해서다.
/// 이체 거래명(`000 스마트폰`, `홍길동`)을 브랜드로 학습해 버리면
/// 이후 같은 상대방에게 보내는 모든 송금이 엉뚱한 브랜드/카테고리로 분류된다.
/// 송금의 *목적*은 매번 다르지만 *상대방 이름*은 그대로이기 때문이다.
///
/// 판단은 순수 함수다. DB 를 보지 않으므로 테스트가 쉽고 호출 위치를 가리지 않는다.
class BrandLearningPolicy {
  const BrandLearningPolicy();

  /// 한국에서 흔한 성씨. 2~3글자 이름 판별에만 쓴다.
  static const Set<String> _commonSurnames = <String>{
    '김', '이', '박', '최', '정', '강', '조', '윤', '장', '임',
    '한', '오', '서', '신', '권', '황', '안', '송', '류', '전',
    '홍', '고', '문', '양', '손', '배', '백', '허', '유', '남',
    '심', '노', '하', '곽', '성', '차', '주', '우', '구', '민',
    '진', '지', '엄', '채', '원', '천', '방', '공', '현', '함',
    '변', '염', '여', '추', '도', '소', '석', '설', '마', '길',
    '연', '위', '표', '명', '기', '반', '라', '왕', '금', '옥',
    '육', '인', '맹', '제', '모', '탁', '국', '어', '은', '편',
  };

  /// 상호에 흔히 붙는 토큰. 이게 있으면 사람 이름이 아니라 가게 이름이다.
  static const List<String> _businessTokens = <String>[
    '점', '카페', '커피', '마트', '편의', '식당', '치킨', '피자', '분식',
    '약국', '병원', '의원', '학원', '주유', '세탁', '미용', '헬스', '베이커리',
    '문구', '서점', '스토어', 'store', 'mart', 'cafe', 'coffee',
    '주식회사', '(주)', '㈜', '농협', '수협', 'shop',
  ];

  static final RegExp _hangulOnly = RegExp(r'^[가-힣]+$');

  /// 전화번호처럼 보이는가. (`01012345678`, `010-1234-5678`)
  static final RegExp _phoneLike = RegExp(
    r'^(\+?82[-\s]?)?0?1[0-9][-\s]?\d{3,4}[-\s]?\d{4}$',
  );

  /// 숫자와 구분자만으로 이루어졌는가(계좌번호 등).
  static final RegExp _digitsOnly = RegExp(r'^[\d\s\-*]+$');

  /// 마스킹된 사람 이름(`홍*동`, `김**`).
  static final RegExp _maskedName = RegExp(r'^[가-힣]\*+[가-힣]?$');

  /// [method] 거래의 [brand] 를 브랜드 규칙으로 학습해도 되는지 판단한다.
  ///
  /// [merchantRaw] 는 알림 원본 거래명이다. 사용자가 브랜드명을 바꿔 놓았더라도
  /// **원본이 상대방 이름이면 학습해서는 안 되므로** 함께 검사한다.
  BrandLearningDecision evaluate({
    required PaymentMethodKind method,
    required String brand,
    String? merchantRaw,
  }) {
    // 1) 거래 유형이 최우선이다. 이체/송금은 예외 없이 금지.
    if (method.isTransfer) {
      return BrandLearningDecision(
        stance: BrandLearningStance.blocked,
        reason: '${method.label} 거래는 자동 학습할 수 없습니다.',
        detail: '상대방 이름은 거래 목적이 매번 달라질 수 있습니다.',
      );
    }

    // 2) 결제 수단을 특정하지 못한 거래도 막는다.
    //    가맹점 결제라는 근거가 없는데 학습하면 규칙이 오염된다.
    if (!method.identifiesMerchant) {
      return const BrandLearningDecision(
        stance: BrandLearningStance.blocked,
        reason: '거래 유형을 확인할 수 없어 자동 학습하지 않습니다.',
        detail: '가맹점 결제로 확인된 거래만 학습합니다.',
      );
    }

    final String trimmedBrand = brand.trim();
    if (trimmedBrand.isEmpty ||
        trimmedBrand == ParsedPayment.unknownMerchantLabel) {
      return const BrandLearningDecision(
        stance: BrandLearningStance.blocked,
        reason: '가맹점을 확인하지 못해 자동 학습하지 않습니다.',
      );
    }

    // 3) 전화번호 / 계좌번호 / 마스킹된 이름은 브랜드가 될 수 없다.
    for (final String candidate
        in <String>[trimmedBrand, merchantRaw?.trim() ?? '']) {
      if (candidate.isEmpty) continue;
      final String compact = candidate.replaceAll(' ', '');

      if (_phoneLike.hasMatch(compact)) {
        return const BrandLearningDecision(
          stance: BrandLearningStance.blocked,
          reason: '전화번호로 보이는 거래는 자동 학습하지 않습니다.',
          detail: '개인 간 송금일 가능성이 높습니다.',
        );
      }
      if (_digitsOnly.hasMatch(compact)) {
        return const BrandLearningDecision(
          stance: BrandLearningStance.blocked,
          reason: '숫자로만 된 거래명은 자동 학습하지 않습니다.',
        );
      }
      if (_maskedName.hasMatch(compact)) {
        return const BrandLearningDecision(
          stance: BrandLearningStance.blocked,
          reason: '가려진 사람 이름은 자동 학습하지 않습니다.',
          detail: '개인 간 송금일 가능성이 높습니다.',
        );
      }
    }

    // 4) 사람 이름처럼 보이면 "권하지 않음". 막지는 않는다.
    //    `이마트`, `김밥천국` 처럼 성씨로 시작하는 실제 상호가 많기 때문이다.
    if (looksLikePersonName(trimmedBrand)) {
      return const BrandLearningDecision(
        stance: BrandLearningStance.discouraged,
        reason: '사람 이름처럼 보입니다.',
        detail: '개인 간 송금이라면 학습하지 마세요. '
            '실제 가맹점이라면 켜도 됩니다.',
      );
    }

    return const BrandLearningDecision.allowed();
  }

  /// 2~3글자 한글이고 흔한 성씨로 시작하며 상호 토큰이 없으면 사람 이름으로 본다.
  ///
  /// 완벽할 수 없는 판단이므로 결과는 "금지" 가 아니라 "권하지 않음" 에만 쓴다.
  bool looksLikePersonName(String value) {
    final String compact = value.replaceAll(' ', '');
    if (compact.length < 2 || compact.length > 3) return false;
    if (!_hangulOnly.hasMatch(compact)) return false;
    if (!_commonSurnames.contains(compact[0])) return false;

    final String lowered = compact.toLowerCase();
    for (final String token in _businessTokens) {
      if (lowered.contains(token)) return false;
    }
    return true;
  }
}
