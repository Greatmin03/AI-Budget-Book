import 'package:intl/intl.dart';

/// 금액 / 날짜 표시 포맷 모음.
class Formatters {
  const Formatters._();

  static final NumberFormat _won = NumberFormat('#,###', 'ko_KR');
  static final DateFormat _monthDay = DateFormat('M월 d일 (E)', 'ko_KR');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _yearMonth = DateFormat('yyyy년 M월', 'ko_KR');
  static final DateFormat _monthShort = DateFormat('M월', 'ko_KR');
  static final DateFormat _yearMonthDay = DateFormat('yyyy-MM-dd');

  /// `6200` -> `6,200원`
  static String won(int amount) => '${_won.format(amount)}원';

  /// 부호를 포함한 금액. 취소 거래는 음수로 저장되므로 `-6,200원` 이 된다.
  static String signedWon(int amount) =>
      amount < 0 ? '-${_won.format(amount.abs())}원' : won(amount);

  /// 순증가처럼 **늘었다는 사실 자체가 정보인** 값에 쓴다.
  ///
  /// `285000` -> `+285,000원`. 0은 부호 없이 `0원`.
  /// 색만으로 증감을 표현하지 않기 위해 부호를 항상 붙인다.
  static String signedWonWithPlus(int amount) {
    if (amount == 0) return won(0);
    return amount > 0 ? '+${won(amount)}' : signedWon(amount);
  }

  /// 좁은 자리(차트 라벨)용 축약 금액. `145000` -> `14.5만`
  ///
  /// 만 원 미만은 축약하지 않는다. `0.5만` 보다 `5,000원` 이 읽기 쉽다.
  static String compactWon(int amount) {
    if (amount.abs() < 10000) return won(amount);
    final double man = amount / 10000;
    return man.abs() >= 100 ? '${man.round()}만' : '${man.toStringAsFixed(1)}만';
  }

  /// 거래 금액을 **부호와 함께** 표시한다.
  ///
  /// 지출도 양수로 저장되므로(방향은 `direction` 으로만 구분한다) 부호를
  /// 직접 붙여야 한다. 붙이지 않으면 `+300,000원  15,000원` 처럼 어느 쪽이
  /// 나간 돈인지 알 수 없다.
  ///
  ///  - 수입            -> `+300,000원`
  ///  - 지출            -> `-15,000원`
  ///  - 지출인데 음수    -> `+30,000원` (취소/환불이므로 실제로 돌려받았다)
  ///  - 0               -> `0원`
  ///
  /// **이 함수가 유일한 구현이다.** 위젯마다 따로 부호를 붙이면 규칙이
  /// 갈라진다(거래 타일과 날짜 바에서 실제로 그런 상태였다).
  static String flowAmount(int amount, {required bool isIncome}) {
    if (amount == 0) return won(0);
    final int signed = isIncome ? amount : -amount;
    return signed > 0 ? '+${won(signed)}' : '-${won(-signed)}';
  }

  /// `12월 25일 (수)`
  static String monthDay(DateTime dt) => _monthDay.format(dt);

  /// `14:33`
  static String time(DateTime dt) => _time.format(dt);

  /// `2026년 8월`
  static String yearMonth(DateTime dt) => _yearMonth.format(dt);

  /// `8월`
  static String monthShort(DateTime dt) => _monthShort.format(dt);

  /// `2026-08-04`
  static String yearMonthDay(DateTime dt) => _yearMonthDay.format(dt);

  /// 증감률. 이전 값이 0이면 null(비교 불가).
  static double? changeRate({required int current, required int previous}) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }

  /// `12% 증가` / `3% 감소`
  static String changeLabel(double rate) {
    final String direction = rate >= 0 ? '증가' : '감소';
    return '${rate.abs().toStringAsFixed(0)}% $direction';
  }
}
