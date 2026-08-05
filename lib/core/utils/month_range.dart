/// 월 단위 조회 구간.
///
/// 통계/거래 목록 모두 "특정 월" 기준으로 조회하므로 계산을 한 곳에 모은다.
class MonthRange {
  MonthRange(int year, int month)
      : year = _normalizedYear(year, month),
        month = _normalizedMonth(month);

  factory MonthRange.of(DateTime dt) => MonthRange(dt.year, dt.month);

  final int year;
  final int month;

  /// 해당 월 1일 00:00:00.000
  DateTime get start => DateTime(year, month);

  /// 다음 달 1일 00:00:00.000 (미포함 상한)
  DateTime get endExclusive => DateTime(year, month + 1);

  int get startMillis => start.millisecondsSinceEpoch;
  int get endExclusiveMillis => endExclusive.millisecondsSinceEpoch;

  MonthRange previous() => MonthRange(year, month - 1);
  MonthRange next() => MonthRange(year, month + 1);

  /// 이 달을 포함해 과거 [count] 개월을 오래된 순으로 반환한다.
  List<MonthRange> lastMonths(int count) {
    final List<MonthRange> result = <MonthRange>[];
    for (int i = count - 1; i >= 0; i--) {
      result.add(MonthRange(year, month - i));
    }
    return result;
  }

  bool get isCurrentMonth {
    final DateTime now = DateTime.now();
    return now.year == year && now.month == month;
  }

  static int _normalizedYear(int year, int month) =>
      DateTime(year, month).year;

  static int _normalizedMonth(int month) => DateTime(2000, month).month;

  @override
  bool operator ==(Object other) =>
      other is MonthRange && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
