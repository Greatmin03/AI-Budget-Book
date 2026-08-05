/// 기간 필터 종류.
///
/// `today` / `week` / `month` / `year` 는 **기준 시각(anchor)이 속한 달력 구간**을
/// 뜻한다. 따라서 이전/다음 구간 이동이 자연스럽게 정의된다.
enum PeriodType {
  today('오늘'),
  week('이번 주'),
  month('이번 달'),
  year('올해'),
  custom('기간 지정');

  const PeriodType(this.chipLabel);

  /// 기간 선택 칩에 표시할 이름.
  final String chipLabel;
}

/// 조회 기간. `[start, endExclusive)` 반열린 구간.
///
/// 모든 통계/목록 조회는 이 타입 하나로 표현한다.
/// (월 단위 전용이던 `MonthRange` 는 추이 그래프의 "월 버킷" 계산에만 남는다)
class DateRange {
  DateRange._({
    required this.type,
    required this.start,
    required this.endExclusive,
    required this.anchor,
  });

  /// 기준 시각이 속한 하루.
  factory DateRange.today([DateTime? now]) {
    final DateTime anchor = now ?? DateTime.now();
    final DateTime start = DateTime(anchor.year, anchor.month, anchor.day);
    return DateRange._(
      type: PeriodType.today,
      start: start,
      endExclusive: start.add(const Duration(days: 1)),
      anchor: anchor,
    );
  }

  /// 기준 시각이 속한 주(월요일 시작).
  factory DateRange.week([DateTime? now]) {
    final DateTime anchor = now ?? DateTime.now();
    final DateTime day = DateTime(anchor.year, anchor.month, anchor.day);
    // DateTime.weekday: 월=1 ... 일=7
    final DateTime start = day.subtract(Duration(days: day.weekday - 1));
    return DateRange._(
      type: PeriodType.week,
      start: start,
      endExclusive: start.add(const Duration(days: 7)),
      anchor: anchor,
    );
  }

  /// 기준 시각이 속한 달.
  factory DateRange.month([DateTime? now]) {
    final DateTime anchor = now ?? DateTime.now();
    return DateRange._(
      type: PeriodType.month,
      start: DateTime(anchor.year, anchor.month),
      endExclusive: DateTime(anchor.year, anchor.month + 1),
      anchor: anchor,
    );
  }

  /// 기준 시각이 속한 해.
  factory DateRange.year([DateTime? now]) {
    final DateTime anchor = now ?? DateTime.now();
    return DateRange._(
      type: PeriodType.year,
      start: DateTime(anchor.year),
      endExclusive: DateTime(anchor.year + 1),
      anchor: anchor,
    );
  }

  /// 사용자 지정 기간. [last] 는 **포함**되는 마지막 날이다.
  factory DateRange.custom(DateTime first, DateTime last) {
    final DateTime start = DateTime(first.year, first.month, first.day);
    final DateTime lastDay = DateTime(last.year, last.month, last.day);
    // 뒤집혀 들어와도 정상 동작하게 한다.
    final DateTime from = start.isAfter(lastDay) ? lastDay : start;
    final DateTime to = start.isAfter(lastDay) ? start : lastDay;
    return DateRange._(
      type: PeriodType.custom,
      start: from,
      endExclusive: to.add(const Duration(days: 1)),
      anchor: from,
    );
  }

  /// 특정 연/월.
  factory DateRange.ofYearMonth(int year, int month) =>
      DateRange.month(DateTime(year, month, 1, 12));

  final PeriodType type;

  /// 포함 시작.
  final DateTime start;

  /// 미포함 끝.
  final DateTime endExclusive;

  /// 이 구간을 만든 기준 시각. 이전/다음 이동의 기준점이 된다.
  final DateTime anchor;

  int get startMillis => start.millisecondsSinceEpoch;
  int get endExclusiveMillis => endExclusive.millisecondsSinceEpoch;

  /// 화면에 표시할 마지막 날(포함).
  DateTime get lastDay => endExclusive.subtract(const Duration(days: 1));

  /// 구간에 포함된 일수.
  int get dayCount => endExclusive.difference(start).inDays;

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(endExclusive);

  bool get containsNow => contains(DateTime.now());

  /// 평균 계산에 쓰는 분모.
  ///
  /// 진행 중인 구간이면 "오늘까지 지난 일수" 를 쓴다.
  /// (8월 4일에 이번 달 평균을 31로 나누면 실제보다 훨씬 작게 나온다)
  int get elapsedDays {
    if (!containsNow) return dayCount;
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int elapsed = today.difference(start).inDays + 1;
    // clamp 는 정적 반환형이 num 이므로 직접 범위를 제한한다.
    if (elapsed < 1) return 1;
    if (elapsed > dayCount) return dayCount;
    return elapsed;
  }

  /// 직전 구간. 증감 비교에 사용한다.
  DateRange previous() {
    switch (type) {
      case PeriodType.today:
        return DateRange.today(start.subtract(const Duration(days: 1)));
      case PeriodType.week:
        return DateRange.week(start.subtract(const Duration(days: 7)));
      case PeriodType.month:
        return DateRange.month(DateTime(start.year, start.month - 1, 1, 12));
      case PeriodType.year:
        return DateRange.year(DateTime(start.year - 1, 1, 1, 12));
      case PeriodType.custom:
        // 같은 길이만큼 앞으로 옮긴다.
        final int days = dayCount;
        final DateTime newLast = start.subtract(const Duration(days: 1));
        return DateRange.custom(
          newLast.subtract(Duration(days: days - 1)),
          newLast,
        );
    }
  }

  /// 다음 구간.
  DateRange next() {
    switch (type) {
      case PeriodType.today:
        return DateRange.today(start.add(const Duration(days: 1)));
      case PeriodType.week:
        return DateRange.week(start.add(const Duration(days: 7)));
      case PeriodType.month:
        return DateRange.month(DateTime(start.year, start.month + 1, 1, 12));
      case PeriodType.year:
        return DateRange.year(DateTime(start.year + 1, 1, 1, 12));
      case PeriodType.custom:
        final int days = dayCount;
        final DateTime newFirst = endExclusive;
        return DateRange.custom(
          newFirst,
          newFirst.add(Duration(days: days - 1)),
        );
    }
  }

  /// 미래 구간으로는 이동하지 않는다.
  bool get canGoNext => endExclusive.isBefore(DateTime.now());

  /// 구간을 나타내는 사람이 읽는 문자열.
  ///
  /// intl 로케일 초기화에 의존하지 않도록 직접 조립한다
  /// (단위 테스트에서 `initializeDateFormatting` 없이도 동작해야 한다).
  String get label {
    switch (type) {
      case PeriodType.today:
        final bool isToday = containsNow;
        return isToday ? '오늘 (${start.month}월 ${start.day}일)' : '${start.year}년 ${start.month}월 ${start.day}일';
      case PeriodType.week:
        return '${start.month}월 ${start.day}일 ~ ${lastDay.month}월 ${lastDay.day}일';
      case PeriodType.month:
        return '${start.year}년 ${start.month}월';
      case PeriodType.year:
        return '${start.year}년';
      case PeriodType.custom:
        return '${_ymd(start)} ~ ${_ymd(lastDay)}';
    }
  }

  /// 직전 구간을 가리키는 짧은 말. ("지난달보다 12% 증가")
  String get previousLabel {
    switch (type) {
      case PeriodType.today:
        return '어제';
      case PeriodType.week:
        return '지난주';
      case PeriodType.month:
        return '지난달';
      case PeriodType.year:
        return '지난해';
      case PeriodType.custom:
        return '직전 같은 기간';
    }
  }

  static String _ymd(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.'
      '${dt.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.type == type &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(type, start, endExclusive);

  @override
  String toString() => 'DateRange(${type.name}, ${_ymd(start)}~${_ymd(lastDay)})';
}
