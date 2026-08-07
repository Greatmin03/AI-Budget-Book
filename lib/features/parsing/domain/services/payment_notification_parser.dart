import '../../../../core/constants/payment_sources.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../../notifications/domain/entities/raw_notification.dart';
import '../entities/parsed_payment.dart';

/// 알림 문자열 -> [ParsedPayment] 규칙 기반 파서.
///
/// 순수 Dart 로만 작성되어 있어 단위 테스트가 쉽다(`test/payment_parser_test.dart`).
///
/// 추출 전략은 "제거식(subtractive)" 이다.
/// 금액/날짜/카드사/할부/마스킹된 이름처럼 **정체가 확실한 토큰을 먼저 지우고**,
/// 남은 연속된 텍스트 덩어리 중 가장 그럴듯한 것을 가맹점으로 본다.
/// 카드사마다 문장 구조가 달라도 이 방식은 비교적 잘 버틴다.
class PaymentNotificationParser {
  const PaymentNotificationParser({this.recognizeBrand});

  /// 후보가 **아는 브랜드인지** 알려 주는 함수(선택).
  ///
  /// 파서는 도메인 사전을 모른다. 대신 호출자가 판별기를 넘겨 주면
  /// 후보 중 아는 브랜드를 우선한다.
  ///
  /// 왜 필요한가:
  /// `씨유(CU) 춘천 백령점` 은 괄호에서 잘려 `씨유` / `CU` / `춘천 백령점`
  /// 세 후보가 된다. "가장 긴 한글 후보" 규칙은 **지점명**인
  /// `춘천 백령점` 을 고른다. 브랜드를 통째로 잃어 이미 아는 가맹점인데도
  /// 카카오 API 와 AI 대기열까지 진행된다.
  ///
  /// 판별기를 주지 않으면 기존 규칙 그대로 동작한다.
  final bool Function(String candidate)? recognizeBrand;

  /// 토큰을 지운 자리에 넣는 구분자. 가맹점 후보 경계를 만든다.
  static const String _sep = '\u0001';

  // ------------------------------------------------------------------ 정규식
  /// `누적 123,456원`, `잔액 1,000원` 처럼 결제 금액이 아닌 숫자.
  static final RegExp _cumulativeAmount = RegExp(
    r'(누적|누계|잔액|한도|가용|사용가능\S*|포인트|적립|할인)\s*:?\s*[\d,]+\s*원?',
  );

  /// `6,200원`, `6200 원`
  static final RegExp _amount = RegExp(r'(\d{1,3}(?:,\d{3})+|\d+)\s*원');

  /// `2026-08-04 14:33`, `2026.08.04 14:33`
  static final RegExp _fullDateTime = RegExp(
    r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\s*(\d{1,2}):(\d{2})',
  );

  /// `08/04 14:33`, `8.4 14:33`
  static final RegExp _monthDayTime = RegExp(
    r'(\d{1,2})[-/.](\d{1,2})\s+(\d{1,2}):(\d{2})',
  );

  /// `8월 4일 14:33`
  static final RegExp _koreanDateTime = RegExp(
    r'(\d{1,2})월\s*(\d{1,2})일\s*(\d{1,2}):(\d{2})',
  );

  /// `14:33`
  static final RegExp _timeOnly = RegExp(r'(\d{1,2}):(\d{2})(:\d{2})?');

  /// `08/04`, `8.4` (시간 없는 날짜)
  static final RegExp _monthDayOnly = RegExp(r'(?:^|\s)(\d{1,2})[/.](\d{1,2})(?=\s|$)');

  /// `3개월`, `12 개월`
  static final RegExp _installment = RegExp(r'(\d{1,2})\s*개월');

  /// `(1234)`, `(1*34)` 카드 뒷번호
  static final RegExp _cardDigitsInParens = RegExp(r'\([\d*]{2,6}\)');

  /// `1234****5678`, `****1234`
  static final RegExp _maskedCardNumber = RegExp(r'[\d*]{2,}\*{2,}[\d*]*|\*{2,}\d{2,}');

  /// `홍*동`, `김**`
  static final RegExp _maskedPersonName = RegExp(r'[가-힣]\*+[가-힣]?');

  /// `[KB국민카드]` 같은 대괄호 블록
  static final RegExp _bracketBlock = RegExp(r'\[[^\]]*\]');

  /// 가맹점일 수 없는 단어들. 지운 뒤 남은 덩어리를 가맹점으로 본다.
  ///
  /// **의도적으로 짧은 단어를 넣지 않는다.**
  /// `원`, `총`, `회`, `카드` 같은 한두 글자를 지우면 실제 가맹점명이 훼손된다.
  /// (`원할머니보쌈` -> `할머니보쌈`, `총각네야채가게` -> `각네야채가게`)
  /// 금액·카드사는 이미 전용 정규식으로 제거되므로 여기서 또 지울 필요가 없고,
  /// 남은 짧은 파편은 "가장 긴 후보를 고른다" 규칙에서 자연히 탈락한다.
  static const List<String> _stopWords = <String>[
    // 순서 중요: `출금취소` 를 `출금` 보다 먼저 지워야 `취소` 가 남지 않는다.
    // 남으면 `출금취소 3,400` 에서 `취소 3` 을 가맹점으로 뽑는다.
    '승인취소',
    '결제취소',
    '출금취소',
    '입금취소',
    '취소',
    '결제완료',
    '승인',
    '결제',
    '출금',
    '입금',
    '이체',
    '지불',
    '매입',
    '일시불',
    '할부',
    '체크카드',
    '신용카드',
    '앱카드',
    '실시간',
    '고객님',
    '가맹점',
    '누적',
    '잔액',
    '전표',
    '금액',
    '내역',
    '사용',
    '거래',
  ];

  /// 가맹점명이 아닌 안내 문구를 걸러내는 패턴.
  ///
  /// "가장 긴 후보" 규칙만 두면 `확인하세요` 같은 문구가 실제 가맹점명보다
  /// 길어서 선택되는 사고가 난다.
  static final RegExp _sentenceLike = RegExp(
    r'(하세요|하십시오|습니다|합니다|됩니다|바랍니다|하기|보기|드립니다)$',
  );

  static const List<String> _noticeWords = <String>[
    '확인',
    '안내',
    '문의',
    '고객센터',
    '바로가기',
    '자세히',
    '수신거부',
    '홈페이지',
  ];

  /// 결제 알림 후보로 볼지 판단하는 최소 조건.
  static const List<String> _requiredKeywords = <String>[
    '승인',
    '결제',
    '출금',
    '취소',
    '이체',
    '지불',
    // 송금도 지출이므로 수집한다. (`카카오페이 송금`, `토스 ... 보냈어요`)
    '송금',
    '보냈',
  ];

  // -------------------------------------------------------------------- parse
  ParseOutcome parse(RawNotification notification) {
    final String text = notification.combinedText;
    if (text.trim().isEmpty) {
      return const ParseIgnored('빈 알림');
    }

    // 1) 입금 알림인지 먼저 본다.
    //    지출이 아니므로 거래로 기록하지 않고 정산 후보로 넘긴다.
    if (_looksLikeDeposit(text)) {
      return _parseDeposit(notification, text);
    }

    // 2) 결제 알림인지 1차 판별
    final bool hasKeyword =
        _requiredKeywords.any((String k) => text.contains(k));
    if (!hasKeyword) {
      return const ParseIgnored('결제 키워드 없음');
    }
    final String? excluded = PaymentSources.hardExcludeKeywords
        .where((String k) => text.contains(k))
        .firstOrNull;
    if (excluded != null) {
      return ParseIgnored('제외 키워드 포함: $excluded');
    }

    // 2) 카드사 / 결제수단
    final String? issuer = PaymentSources.issuerOf(notification.packageName) ??
        PaymentSources.issuerFromText(text);
    final String? cardName =
        (issuer == null || issuer == 'SMS') ? PaymentSources.issuerFromText(text) : issuer;

    // 3) 금액 (누적/잔액 등을 먼저 제거해야 오인식이 없다)
    final String amountScope = text.replaceAll(_cumulativeAmount, ' ');
    final RegExpMatch? amountMatch = _amount.firstMatch(amountScope);
    if (amountMatch == null) {
      return const ParseFailed('금액을 찾지 못함');
    }
    final int? amount = _toInt(amountMatch.group(1));
    if (amount == null || amount <= 0) {
      return ParseFailed('금액 해석 실패: ${amountMatch.group(0)}');
    }

    // 4) 취소 여부 / 할부
    final bool isCancellation =
        PaymentSources.cancelKeywords.any((String k) => text.contains(k));
    final int installmentMonths = _extractInstallmentMonths(text);

    // 5) 결제 시각
    final DateTime paymentDatetime =
        _extractDateTime(text, notification.postedAt);

    // 6) 가맹점
    final String merchantRaw = _extractMerchant(
      text: text,
      cardName: cardName,
    );

    return ParseSuccess(
      ParsedPayment(
        merchantRaw: merchantRaw,
        amount: amount,
        paymentDatetime: paymentDatetime,
        method: _resolveMethod(issuer: issuer, text: text),
        rawNotification: text,
        cardName: cardName,
        isCancellation: isCancellation,
        installmentMonths: installmentMonths,
        sourcePackage: notification.packageName,
        accountNumber: _extractAccountNumber(text),
        balanceAfter: _extractBalance(text),
      ),
    );
  }

  /// 은행 알림의 마스킹된 계좌번호. 예: `942902-**-***245`
  ///
  /// 마스킹된 형태 그대로 둔다. 어느 계좌에서 나갔는지 알아보는 용도이고,
  /// 원본 번호를 우리가 복원할 이유가 없다.
  static String? _extractAccountNumber(String text) {
    final Match? m = _accountNumberPattern.firstMatch(text);
    return m?.group(0);
  }

  /// 거래 직후 잔액. 예: `잔액1,394,125` -> 1394125
  ///
  /// 은행이 알려 주는 실제 값이다. 앱이 계산한 잔액과 대조할 수 있는
  /// 유일한 근거이므로 버리지 않는다.
  static int? _extractBalance(String text) {
    final Match? m = _balancePattern.firstMatch(text);
    if (m == null) return null;
    final String digits = (m.group(1) ?? '').replaceAll(',', '');
    return int.tryParse(digits);
  }

  // ------------------------------------------------------------------- 입금
  /// 입금(받은 돈) 알림인가.
  ///
  /// 입금 표현이 있고 지출 표현이 없어야 한다.
  /// `출금 후 입금` 처럼 섞인 문장은 지출로 본다(보수적).
  bool _looksLikeDeposit(String text) {
    final bool hasDeposit =
        _depositKeywords.any((String k) => text.contains(k));
    if (!hasDeposit) return false;

    final bool hasExpense =
        _expenseOnlyKeywords.any((String k) => text.contains(k));
    return !hasExpense;
  }

  /// 입금 알림 파싱.
  ParseOutcome _parseDeposit(RawNotification notification, String text) {
    final String amountScope = text.replaceAll(_cumulativeAmount, ' ');
    final RegExpMatch? amountMatch = _amount.firstMatch(amountScope);
    if (amountMatch == null) {
      return const ParseIgnored('입금 알림이지만 금액을 찾지 못함');
    }
    final int? amount = _toInt(amountMatch.group(1));
    if (amount == null || amount <= 0) {
      return const ParseIgnored('입금 금액 해석 실패');
    }

    final String? bank = PaymentSources.issuerOf(notification.packageName) ??
        PaymentSources.issuerFromText(text);

    // 보낸 사람 추출은 가맹점 추출과 같은 방식을 쓴다.
    // (카드사/금액/시각 등을 지우고 남은 덩어리)
    final String counterparty = _extractMerchant(text: text, cardName: bank);

    return ParseDepositOutcome(
      ParsedDeposit(
        counterparty: counterparty == ParsedPayment.unknownMerchantLabel
            ? '알 수 없음'
            : counterparty,
        amount: amount,
        depositedAt: _extractDateTime(text, notification.postedAt),
        rawNotification: text,
        bankName: bank == 'SMS' ? null : bank,
        sourcePackage: notification.packageName,
      ),
    );
  }

  /// 입금을 뜻하는 표현.
  static const List<String> _depositKeywords = <String>[
    '입금',
    '받았어요',
    '받으셨',
    '들어왔',
  ];

  /// 지출임이 확실한 표현. 하나라도 있으면 입금으로 보지 않는다.
  static const List<String> _expenseOnlyKeywords = <String>[
    '승인',
    '결제',
    '출금',
    '송금',
    '보냈',
    '지불',
  ];

  // ------------------------------------------------------------------ helpers
  static int? _toInt(String? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.replaceAll(',', ''));
  }

  int _extractInstallmentMonths(String text) {
    if (text.contains('일시불')) return 0;
    final RegExpMatch? match = _installment.firstMatch(text);
    if (match == null) return 0;
    final int months = int.tryParse(match.group(1) ?? '') ?? 0;
    // 60개월 초과는 오인식으로 본다.
    return (months > 0 && months <= 60) ? months : 0;
  }

  /// 알림 본문의 시각 표기를 우선하고, 없으면 알림 수신 시각을 쓴다.
  DateTime _extractDateTime(String text, DateTime postedAt) {
    final RegExpMatch? full = _fullDateTime.firstMatch(text);
    if (full != null) {
      final DateTime? dt = _safeDateTime(
        year: int.tryParse(full.group(1) ?? ''),
        month: int.tryParse(full.group(2) ?? ''),
        day: int.tryParse(full.group(3) ?? ''),
        hour: int.tryParse(full.group(4) ?? ''),
        minute: int.tryParse(full.group(5) ?? ''),
      );
      if (dt != null) return dt;
    }

    for (final RegExp pattern in <RegExp>[_monthDayTime, _koreanDateTime]) {
      final RegExpMatch? match = pattern.firstMatch(text);
      if (match == null) continue;
      final DateTime? dt = _resolveYear(
        month: int.tryParse(match.group(1) ?? ''),
        day: int.tryParse(match.group(2) ?? ''),
        hour: int.tryParse(match.group(3) ?? ''),
        minute: int.tryParse(match.group(4) ?? ''),
        reference: postedAt,
      );
      if (dt != null) return dt;
    }

    final RegExpMatch? timeMatch = _timeOnly.firstMatch(text);
    if (timeMatch != null) {
      final DateTime? dt = _safeDateTime(
        year: postedAt.year,
        month: postedAt.month,
        day: postedAt.day,
        hour: int.tryParse(timeMatch.group(1) ?? ''),
        minute: int.tryParse(timeMatch.group(2) ?? ''),
      );
      if (dt != null) return dt;
    }

    return postedAt;
  }

  /// 연도가 없는 `MM/DD` 표기의 연도를 추론한다.
  ///
  /// 12월 31일 결제 알림을 1월 1일에 처리하는 경우를 위해,
  /// 추론 결과가 기준 시각보다 크게 미래면 전년도로 본다.
  DateTime? _resolveYear({
    required int? month,
    required int? day,
    required int? hour,
    required int? minute,
    required DateTime reference,
  }) {
    final DateTime? candidate = _safeDateTime(
      year: reference.year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
    );
    if (candidate == null) return null;

    if (candidate.difference(reference).inDays > 40) {
      return _safeDateTime(
        year: reference.year - 1,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
      );
    }
    return candidate;
  }

  /// 범위를 벗어난 값이면 null. (`DateTime` 은 13월을 다음 해 1월로 넘겨버리므로 직접 검증)
  DateTime? _safeDateTime({
    required int? year,
    required int? month,
    required int? day,
    required int? hour,
    required int? minute,
  }) {
    if (year == null || month == null || day == null) return null;
    final int h = hour ?? 0;
    final int m = minute ?? 0;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;
    final DateTime dt = DateTime(year, month, day, h, m);
    if (dt.month != month || dt.day != day) return null; // 2월 30일 등
    return dt;
  }

  /// 거래 유형 판별.
  ///
  /// **순서가 중요하다.** 이체/송금 키워드를 간편결제 판별보다 먼저 본다.
  /// `카카오페이 송금 홍길동` 을 간편결제(=가맹점 결제)로 오인하면
  /// 사람 이름이 브랜드로 학습될 수 있다.
  PaymentMethodKind _resolveMethod({
    required String? issuer,
    required String text,
  }) {
    // 1) 송금: 상대방에게 보낸 돈.
    for (final String keyword in _remittanceKeywords) {
      if (text.contains(keyword)) return PaymentMethodKind.remittance;
    }

    // 2) 체크/직불카드. **이체 판별보다 먼저 본다.**
    //
    // 은행이 보내는 `... 퀴즈노스춘천 체크카드출금 9,630` 은 `출금` 이 들어
    // 있어서 이체로 오인된다. 이체로 판정되면 상대방 이름 보호 정책이
    // 걸려 카카오 조회도 AI 분류도 전부 막힌다 — 가맹점 결제인데 영영
    // 분류되지 않는다.
    for (final String keyword in _debitCardKeywords) {
      if (text.contains(keyword)) return PaymentMethodKind.card;
    }

    // 3) 계좌 이체/출금.
    for (final String keyword in _transferKeywords) {
      if (text.contains(keyword)) return PaymentMethodKind.accountTransfer;
    }

    // 4) 간편결제(가맹점 결제).
    if (issuer != null && _easyPayIssuers.contains(issuer)) {
      return PaymentMethodKind.easyPay;
    }

    // 5) 카드 승인.
    if (text.contains('카드') || (issuer != null && issuer.contains('카드'))) {
      return PaymentMethodKind.card;
    }
    if (issuer != null && issuer.contains('은행')) {
      return PaymentMethodKind.accountTransfer;
    }

    // 승인 키워드로 걸러진 알림이므로 카드 결제로 본다.
    return PaymentMethodKind.card;
  }

  /// 개인 간 송금을 뜻하는 표현.
  ///
  /// 받은 돈(`받았어요`)은 지출이 아니므로 여기에 넣지 않는다.
  static const List<String> _remittanceKeywords = <String>[
    '송금',
    '보냈',
    '더치페이',
    '정산',
  ];

  /// 마스킹된 계좌번호. `942902-**-***245`
  ///
  /// 숫자와 `*` 가 하이픈으로 이어진 형태만 잡는다. 날짜(`08/06`)나
  /// 금액과 헷갈리지 않도록 하이픈 두 개 이상을 요구한다.
  static final RegExp _accountNumberPattern =
      RegExp(r'[0-9*]{2,}-[0-9*]{2,}-[0-9*]{2,}');

  /// `잔액1,394,125` / `잔액 1,394,125원`
  static final RegExp _balancePattern =
      RegExp(r'잔액\s*([0-9,]+)');

  /// 체크/직불카드 결제를 뜻하는 표현.
  ///
  /// 은행 계좌에서 바로 빠져나가므로 알림 문구에 `출금` 이 함께 오지만,
  /// **상대방이 아니라 가맹점**에 낸 돈이다.
  static const List<String> _debitCardKeywords = <String>[
    '체크카드',
    '직불카드',
    '카드출금',
  ];

  /// 계좌 이체/출금을 뜻하는 표현.
  static const List<String> _transferKeywords = <String>[
    '이체',
    '출금',
    '입금',
    '자동납부',
    '자동이체',
  ];

  static const List<String> _easyPayIssuers = <String>[
    '카카오페이',
    '네이버페이',
    '토스',
    '페이코',
    '삼성페이',
    'SSG페이',
    'LG페이',
    'Google Pay',
  ];

  /// 확실한 토큰을 모두 [_sep] 로 치환하고, 남은 덩어리 중 최적 후보를 고른다.
  String _extractMerchant({
    required String text,
    required String? cardName,
  }) {
    String work = text;

    // 순서 중요: 긴 패턴 -> 짧은 패턴
    work = work.replaceAll(_bracketBlock, _sep);
    work = work.replaceAll(_cumulativeAmount, _sep);
    work = work.replaceAll(_fullDateTime, _sep);
    work = work.replaceAll(_monthDayTime, _sep);
    work = work.replaceAll(_koreanDateTime, _sep);
    work = work.replaceAll(_timeOnly, _sep);
    work = work.replaceAll(_monthDayOnly, _sep);
    work = work.replaceAll(_amount, _sep);
    work = work.replaceAll(_installment, _sep);
    work = work.replaceAll(_maskedCardNumber, _sep);
    work = work.replaceAll(_cardDigitsInParens, _sep);
    work = work.replaceAll(_maskedPersonName, _sep);

    // 카드사/결제수단 이름 제거
    if (cardName != null && cardName.isNotEmpty) {
      work = work.replaceAll(cardName, _sep);
    }
    for (final String issuer in PaymentSources.packageToIssuer.values.toSet()) {
      work = work.replaceAll(issuer, _sep);
    }

    for (final String word in _stopWords) {
      work = work.replaceAll(word, _sep);
    }

    // 줄바꿈 / 구두점도 경계로 취급
    work = work.replaceAll(RegExp(r'[\n\r\t,:;|/\\()<>{}"' r"']"), _sep);

    final List<String> candidates = work
        .split(_sep)
        .map((String e) => e.trim())
        .where(_isMerchantCandidate)
        .toList();

    if (candidates.isEmpty) return ParsedPayment.unknownMerchantLabel;

    // 아는 브랜드가 후보에 있으면 그것을 고른다.
    // 길이 규칙보다 우선한다 — 지점명이 브랜드보다 긴 경우가 흔하다.
    final bool Function(String)? recognize = recognizeBrand;
    if (recognize != null) {
      final List<String> known = candidates.where(recognize).toList();
      if (known.isNotEmpty) {
        // 여러 개면 더 구체적인(긴) 쪽을 고른다.
        known.sort((String a, String b) => b.length.compareTo(a.length));
        return _capped(known.first);
      }
    }

    // 한글 포함 후보를 우선하고, 그중 가장 긴 것을 고른다.
    final List<String> korean =
        candidates.where(TextNormalizer.hasKorean).toList();
    final List<String> pool = korean.isNotEmpty ? korean : candidates;
    pool.sort((String a, String b) => b.length.compareTo(a.length));

    return _capped(pool.first);
  }

  /// 가맹점명이 지나치게 길면 자른다(알림 전문이 통째로 들어오는 경우).
  static String _capped(String value) =>
      value.length > 40 ? value.substring(0, 40) : value;

  bool _isMerchantCandidate(String value) {
    if (value.length < 2) return false;
    if (TextNormalizer.isMaskedPersonName(value)) return false;

    // 안내 문구는 가맹점이 아니다.
    if (_sentenceLike.hasMatch(value)) return false;
    if (_noticeWords.any(value.contains)) return false;

    // 한글이 있거나, 영문이 2자 이상이어야 가맹점으로 본다.
    if (TextNormalizer.hasKorean(value)) return true;
    return RegExp(r'[a-zA-Z]{2,}').hasMatch(value);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
