import 'package:budget_book/core/utils/date_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 기준 시각: 2026년 8월 4일 (화요일) 14:33
  final DateTime anchor = DateTime(2026, 8, 4, 14, 33);

  group('구간 경계', () {
    test('오늘: 해당 날짜의 00:00 ~ 다음 날 00:00', () {
      final DateRange range = DateRange.today(anchor);

      expect(range.start, DateTime(2026, 8, 4));
      expect(range.endExclusive, DateTime(2026, 8, 5));
      expect(range.dayCount, 1);
    });

    test('이번 주: 월요일 시작, 7일', () {
      final DateRange range = DateRange.week(anchor);

      // 2026-08-04 는 화요일 -> 주 시작은 8월 3일(월)
      expect(range.start, DateTime(2026, 8, 3));
      expect(range.start.weekday, DateTime.monday);
      expect(range.endExclusive, DateTime(2026, 8, 10));
      expect(range.dayCount, 7);
      expect(range.lastDay, DateTime(2026, 8, 9));
    });

    test('이번 달: 1일 ~ 다음 달 1일', () {
      final DateRange range = DateRange.month(anchor);

      expect(range.start, DateTime(2026, 8, 1));
      expect(range.endExclusive, DateTime(2026, 9, 1));
      expect(range.dayCount, 31);
    });

    test('올해: 1월 1일 ~ 다음 해 1월 1일', () {
      final DateRange range = DateRange.year(anchor);

      expect(range.start, DateTime(2026, 1, 1));
      expect(range.endExclusive, DateTime(2027, 1, 1));
      expect(range.dayCount, 365);
    });

    test('사용자 지정: 마지막 날이 포함된다', () {
      final DateRange range = DateRange.custom(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 15),
      );

      expect(range.start, DateTime(2026, 8, 1));
      expect(range.endExclusive, DateTime(2026, 8, 16));
      expect(range.dayCount, 15);
      expect(range.contains(DateTime(2026, 8, 15, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 8, 16)), isFalse);
    });

    test('사용자 지정: 시작/끝이 뒤집혀도 정상 동작한다', () {
      final DateRange range = DateRange.custom(
        DateTime(2026, 8, 15),
        DateTime(2026, 8, 1),
      );

      expect(range.start, DateTime(2026, 8, 1));
      expect(range.lastDay, DateTime(2026, 8, 15));
    });

    test('시간 정보는 잘려서 자정에 맞춰진다', () {
      final DateRange range = DateRange.today(anchor);

      expect(range.start.hour, 0);
      expect(range.start.minute, 0);
    });
  });

  group('contains', () {
    test('시작은 포함, 끝은 미포함', () {
      final DateRange range = DateRange.month(anchor);

      expect(range.contains(DateTime(2026, 8, 1)), isTrue);
      expect(range.contains(DateTime(2026, 8, 31, 23, 59, 59)), isTrue);
      expect(range.contains(DateTime(2026, 9, 1)), isFalse);
      expect(range.contains(DateTime(2026, 7, 31, 23, 59)), isFalse);
    });
  });

  group('직전 구간', () {
    test('오늘 -> 어제', () {
      final DateRange previous = DateRange.today(anchor).previous();

      expect(previous.start, DateTime(2026, 8, 3));
      expect(previous.dayCount, 1);
      expect(previous.type, PeriodType.today);
    });

    test('이번 주 -> 지난주', () {
      final DateRange previous = DateRange.week(anchor).previous();

      expect(previous.start, DateTime(2026, 7, 27));
      expect(previous.endExclusive, DateTime(2026, 8, 3));
    });

    test('이번 달 -> 지난달 (달력 기준)', () {
      final DateRange previous = DateRange.month(anchor).previous();

      expect(previous.start, DateTime(2026, 7, 1));
      expect(previous.endExclusive, DateTime(2026, 8, 1));
      expect(previous.dayCount, 31, reason: '7월은 31일');
    });

    test('1월의 직전은 전년 12월', () {
      final DateRange previous =
          DateRange.month(DateTime(2026, 1, 15)).previous();

      expect(previous.start, DateTime(2025, 12, 1));
    });

    test('올해 -> 지난해', () {
      final DateRange previous = DateRange.year(anchor).previous();

      expect(previous.start, DateTime(2025, 1, 1));
      expect(previous.endExclusive, DateTime(2026, 1, 1));
    });

    test('사용자 지정 -> 같은 길이만큼 앞선 기간', () {
      final DateRange range = DateRange.custom(
        DateTime(2026, 8, 11),
        DateTime(2026, 8, 20),
      );
      final DateRange previous = range.previous();

      expect(previous.dayCount, range.dayCount);
      expect(previous.lastDay, DateTime(2026, 8, 10));
      expect(previous.start, DateTime(2026, 8, 1));
    });
  });

  group('다음 구간', () {
    test('이번 달 -> 다음 달', () {
      final DateRange next = DateRange.month(anchor).next();

      expect(next.start, DateTime(2026, 9, 1));
    });

    test('12월의 다음은 다음 해 1월', () {
      final DateRange next = DateRange.month(DateTime(2026, 12, 5)).next();

      expect(next.start, DateTime(2027, 1, 1));
    });

    test('previous 와 next 는 서로를 되돌린다', () {
      final DateRange range = DateRange.month(anchor);

      expect(range.previous().next(), range);
      expect(range.next().previous(), range);
    });
  });

  group('평균 계산용 일수', () {
    test('지난 기간은 전체 일수를 쓴다', () {
      // 확실히 과거인 구간
      final DateRange past = DateRange.month(DateTime(2020, 3, 10));

      expect(past.containsNow, isFalse);
      expect(past.elapsedDays, 31);
    });

    test('진행 중인 기간은 지난 일수만 쓴다', () {
      // 이번 달은 아직 끝나지 않았으므로 전체 일수보다 작거나 같다.
      final DateRange current = DateRange.month();

      expect(current.containsNow, isTrue);
      expect(current.elapsedDays, lessThanOrEqualTo(current.dayCount));
      expect(current.elapsedDays, greaterThanOrEqualTo(1));
      expect(current.elapsedDays, DateTime.now().day);
    });

    test('오늘 구간의 일수는 1이다', () {
      expect(DateRange.today().elapsedDays, 1);
    });
  });

  group('다음 구간 이동 가능 여부', () {
    test('진행 중인 구간에서는 다음으로 갈 수 없다', () {
      expect(DateRange.month().canGoNext, isFalse);
      expect(DateRange.today().canGoNext, isFalse);
      expect(DateRange.year().canGoNext, isFalse);
    });

    test('과거 구간에서는 다음으로 갈 수 있다', () {
      expect(DateRange.month(DateTime(2020, 3, 10)).canGoNext, isTrue);
    });
  });

  group('표시 문자열', () {
    test('구간 종류별 라벨', () {
      expect(DateRange.month(anchor).label, '2026년 8월');
      expect(DateRange.year(anchor).label, '2026년');
      expect(DateRange.week(anchor).label, '8월 3일 ~ 8월 9일');
      expect(
        DateRange.custom(DateTime(2026, 8, 1), DateTime(2026, 8, 15)).label,
        '2026.08.01 ~ 2026.08.15',
      );
    });

    test('직전 구간을 가리키는 말', () {
      expect(DateRange.month(anchor).previousLabel, '지난달');
      expect(DateRange.week(anchor).previousLabel, '지난주');
      expect(DateRange.year(anchor).previousLabel, '지난해');
      expect(DateRange.today(anchor).previousLabel, '어제');
    });
  });

  group('동등성', () {
    test('같은 종류/같은 경계면 같다', () {
      expect(DateRange.month(DateTime(2026, 8, 1)),
          DateRange.month(DateTime(2026, 8, 31)));
      expect(DateRange.ofYearMonth(2026, 8), DateRange.month(anchor));
    });

    test('종류가 다르면 다르다', () {
      // 같은 날을 포함하더라도 구간 종류가 다르면 다른 필터다.
      expect(DateRange.today(anchor), isNot(DateRange.month(anchor)));
    });
  });
}
