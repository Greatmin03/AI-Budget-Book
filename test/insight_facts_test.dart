import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/insights/domain/entities/insight_facts.dart';
import 'package:budget_book/features/insights/domain/services/insight_narrator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사실 계산 + 문장 생성 테스트.
///
/// **금액 계산이 이 레이어에 있는 이유가 여기 있다.**
/// LLM 이 산수를 하면 검증할 수 없지만, 코드가 하면 테스트로 고정할 수 있다.
void main() {
  final DateRange august = DateRange.ofYearMonth(2026, 8);

  ItemFact fact({
    required String name,
    required int amount,
    required int count,
    int previousAmount = 0,
    int previousCount = 0,
  }) {
    return ItemFact(
      name: name,
      amount: amount,
      count: count,
      previousAmount: previousAmount,
      previousCount: previousCount,
    );
  }

  group('ItemFact 계산', () {
    test('1회 평균 금액', () {
      expect(fact(name: '카페', amount: 95000, count: 21).averageAmount, 4524);
      expect(fact(name: '없음', amount: 0, count: 0).averageAmount, 0);
    });

    test('요구사항 예시: 카페 95,000원, 전월 대비 34% 증가', () {
      final ItemFact f = fact(
        name: '카페',
        amount: 95000,
        count: 21,
        previousAmount: 70896,
        previousCount: 16,
      );

      expect(f.amountChange, 24104);
      expect(f.countChange, 5);
      expect(f.increased, isTrue);
      expect(f.changeRate!.round(), 34);
    });

    test('이전 기간이 0이면 증감률은 계산하지 않는다', () {
      final ItemFact f = fact(name: '새항목', amount: 50000, count: 2);

      expect(f.changeRate, isNull);
      expect(f.isNew, isTrue);
    });

    test('금액이 작으면 비율이 커도 알리지 않는다', () {
      // 500 -> 1,500원은 200% 증가지만 사용자에게 무의미하다.
      final ItemFact tiny = fact(
        name: '소액',
        amount: 1500,
        count: 1,
        previousAmount: 500,
        previousCount: 1,
      );
      expect(tiny.isNotable(), isFalse);

      final ItemFact real = fact(
        name: '카페',
        amount: 95000,
        count: 21,
        previousAmount: 70000,
        previousCount: 16,
      );
      expect(real.isNotable(), isTrue);
    });

    test('변화율이 작으면 알리지 않는다', () {
      final ItemFact flat = fact(
        name: '통신비',
        amount: 55000,
        count: 1,
        previousAmount: 55000,
        previousCount: 1,
      );
      expect(flat.isNotable(), isFalse);
    });
  });

  group('절약 시뮬레이션', () {
    final InsightFacts facts = InsightFacts(
      range: august,
      total: 500000,
      previousTotal: 450000,
      transactionCount: 60,
      dailyAverage: 16100,
      categories: const <ItemFact>[],
      subcategories: const <ItemFact>[],
      brands: <ItemFact>[
        fact(name: '메가커피', amount: 88000, count: 22, previousAmount: 60000),
      ],
      weekdayPatterns: const <WeekdayPattern>[],
    );

    test('요구사항 예시: 메가커피 22회, 1회 4,000원 → 줄인 만큼 절약', () {
      final SavingScenario? s =
          facts.simulateReduction(target: '메가커피', reduceBy: 9);

      expect(s, isNotNull);
      expect(s!.averageAmount, 4000);
      expect(s.savedPerMonth, 36000, reason: '4,000원 × 9회');
      expect(s.savedPer6Months, 216000);
      expect(s.savedPerYear, 432000);
      expect(s.remainingCount, 13);
    });

    test('현재 횟수보다 많이 줄이라고 해도 전체까지만 계산한다', () {
      final SavingScenario? s =
          facts.simulateReduction(target: '메가커피', reduceBy: 100);

      expect(s!.reducedCount, 22);
      expect(s.remainingCount, 0);
    });

    test('비율로 줄이는 시뮬레이션', () {
      // 22회의 절반 = 11회
      final SavingScenario? s =
          facts.simulateReductionByRatio(target: '메가커피', ratio: 0.5);

      expect(s!.reducedCount, 11);
      expect(s.savedPerMonth, 44000);
    });

    test('없는 항목은 null', () {
      expect(facts.simulateReduction(target: '없는브랜드', reduceBy: 1), isNull);
    });
  });

  group('증가/감소 원인 추출', () {
    final InsightFacts facts = InsightFacts(
      range: august,
      total: 600000,
      previousTotal: 500000,
      transactionCount: 70,
      dailyAverage: 20000,
      categories: const <ItemFact>[],
      subcategories: <ItemFact>[
        fact(name: '배달', amount: 96000, count: 16, previousAmount: 14000),
        fact(name: '카페', amount: 95000, count: 21, previousAmount: 64000),
        fact(name: '쇼핑', amount: 40000, count: 2, previousAmount: 120000),
        fact(name: '통신비', amount: 55000, count: 1, previousAmount: 55000),
      ],
      brands: const <ItemFact>[],
      weekdayPatterns: const <WeekdayPattern>[],
    );

    test('증가액이 큰 순으로 원인을 뽑는다', () {
      final List<ItemFact> increases = facts.topIncreases();

      expect(increases.first.name, '배달', reason: '+82,000원이 가장 크다');
      expect(increases[1].name, '카페');
      // 변화 없는 통신비는 제외된다.
      expect(increases.any((ItemFact f) => f.name == '통신비'), isFalse);
    });

    test('감소한 항목도 뽑는다(절약 성공)', () {
      final List<ItemFact> decreases = facts.topDecreases();

      expect(decreases.first.name, '쇼핑');
      expect(decreases.first.amountChange, -80000);
    });

    test('전체 증감', () {
      expect(facts.amountChange, 100000);
      expect(facts.changeRate, 20);
    });
  });

  group('요일 패턴', () {
    test('관측 주의 60% 이상이면 습관으로 본다', () {
      const WeekdayPattern habitual = WeekdayPattern(
        weekday: DateTime.friday,
        subcategory: '술',
        averageAmount: 42000,
        occurrences: 6,
        weeksObserved: 8,
      );
      expect(habitual.isHabitual, isTrue);
      expect(habitual.weekdayLabel, '금요일');
    });

    test('드문 패턴은 습관이 아니다', () {
      const WeekdayPattern rare = WeekdayPattern(
        weekday: DateTime.monday,
        subcategory: '영화',
        averageAmount: 15000,
        occurrences: 2,
        weeksObserved: 8,
      );
      expect(rare.isHabitual, isFalse);
    });

    test('관측 기간이 너무 짧으면 판단하지 않는다', () {
      const WeekdayPattern tooShort = WeekdayPattern(
        weekday: DateTime.friday,
        subcategory: '술',
        averageAmount: 42000,
        occurrences: 2,
        weeksObserved: 2,
      );
      expect(tooShort.isHabitual, isFalse);
    });
  });

  group('InsightNarrator (LLM 없이 동작)', () {
    const InsightNarrator narrator = InsightNarrator();

    final InsightFacts facts = InsightFacts(
      range: august,
      total: 600000,
      previousTotal: 500000,
      transactionCount: 70,
      dailyAverage: 20000,
      categories: const <ItemFact>[],
      subcategories: <ItemFact>[
        fact(name: '배달', amount: 96000, count: 16, previousAmount: 14000),
      ],
      brands: <ItemFact>[
        fact(name: '메가커피', amount: 88000, count: 22, previousAmount: 60000),
      ],
      weekdayPatterns: const <WeekdayPattern>[
        WeekdayPattern(
          weekday: DateTime.friday,
          subcategory: '술',
          averageAmount: 42000,
          occurrences: 6,
          weeksObserved: 8,
        ),
      ],
    );

    test('분석 문장에 실제 숫자가 들어간다', () {
      final List<Insight> insights = narrator.analyze(facts);

      expect(insights, isNotEmpty);
      // 총액 요약이 먼저 온다.
      expect(insights.first.headline, contains('600,000원'));
      // 증가 원인이 포함된다.
      expect(
        insights.any((Insight i) => i.headline.contains('배달')),
        isTrue,
      );
    });

    test('절약 제안은 월 1만원 이상만 내놓는다', () {
      final List<Insight> suggestions = narrator.suggestions(facts);

      expect(suggestions, isNotEmpty);
      for (final Insight s in suggestions) {
        expect(s.savedPerMonth, isNotNull);
        expect(s.savedPerMonth!, greaterThanOrEqualTo(10000));
      }
    });

    test('습관 문장', () {
      final List<Insight> habits = narrator.habits(facts);

      expect(habits.first.headline, contains('금요일'));
      expect(habits.first.headline, contains('42,000원'));
    });

    test('거래가 없으면 아무 말도 하지 않는다', () {
      final List<Insight> insights =
          narrator.analyze(InsightFacts.empty(august));

      expect(insights, isEmpty);
    });

    test('시나리오 설명에 세 기간이 모두 들어간다', () {
      final SavingScenario? s =
          facts.simulateReduction(target: '메가커피', reduceBy: 8);
      final String text = narrator.describeScenario(s!);

      expect(text, contains('1개월'));
      expect(text, contains('6개월'));
      expect(text, contains('1년'));
    });
  });
}
