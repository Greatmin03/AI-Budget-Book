import '../../../../core/utils/formatters.dart';
import '../entities/insight_facts.dart';

/// 한 줄 인사이트.
class Insight {
  const Insight({
    required this.kind,
    required this.headline,
    this.detail,
    this.savedPerMonth,
    this.target,
  });

  final InsightKind kind;

  /// 핵심 문장.
  final String headline;

  /// 부연.
  final String? detail;

  /// 절약 제안이면 월 절약 가능액.
  final int? savedPerMonth;

  /// 대상 항목 이름(탭하면 상세로 이동).
  final String? target;
}

enum InsightKind {
  /// 늘어난 소비.
  increase('증가'),

  /// 줄어든 소비(칭찬).
  decrease('감소'),

  /// 절약 제안.
  suggestion('절약 제안'),

  /// 소비 습관.
  habit('습관'),

  /// 전체 요약.
  summary('요약');

  const InsightKind(this.label);

  final String label;
}

/// 사실 → 문장.
///
/// ## 왜 규칙 기반인가
/// 금액·횟수·절약액은 **앱이 계산한다.** LLM 은 표현만 바꾼다.
/// LLM 이 "주 2회 줄이면 36,000원" 같은 산수를 하면 틀리고,
/// 사용자는 그 숫자를 믿고 판단한다. 그래서 계산은 코드에 둔다.
///
/// 이 기본 구현은 Ollama 가 없어도 동작한다.
/// LLM 을 켜면 같은 [Insight] 목록을 더 자연스러운 문장으로 다시 쓰게 할 수 있고,
/// 그때도 **숫자는 이 클래스가 만든 값을 그대로 쓴다.**
class InsightNarrator {
  const InsightNarrator();

  /// 소비 분석: 무엇이 늘고 줄었는지.
  List<Insight> analyze(InsightFacts facts) {
    if (facts.isEmpty) return const <Insight>[];

    final List<Insight> insights = <Insight>[];

    // 전체 요약
    final double? rate = facts.changeRate;
    if (rate != null) {
      insights.add(
        Insight(
          kind: rate >= 0 ? InsightKind.increase : InsightKind.decrease,
          headline: '${facts.range.label} 총 ${Formatters.won(facts.total)} 썼습니다.',
          detail: '${facts.range.previousLabel}보다 '
              '${Formatters.won(facts.amountChange.abs())} '
              '${rate >= 0 ? '많이' : '적게'} 썼습니다 '
              '(${Formatters.changeLabel(rate)}).',
        ),
      );
    }

    // 늘어난 항목
    for (final ItemFact fact in facts.topIncreases()) {
      insights.add(
        Insight(
          kind: InsightKind.increase,
          target: fact.name,
          headline: '${fact.name} ${fact.count}회 '
              '${Formatters.won(fact.amount)}',
          detail: fact.isNew
              ? '${facts.range.previousLabel}에는 없던 지출입니다.'
              : '${facts.range.previousLabel}보다 '
                  '${Formatters.won(fact.amountChange)} 늘었습니다'
                  '${fact.changeRate == null ? '' : ' (${Formatters.changeLabel(fact.changeRate!)})'}.',
        ),
      );
    }

    // 줄어든 항목
    for (final ItemFact fact in facts.topDecreases()) {
      insights.add(
        Insight(
          kind: InsightKind.decrease,
          target: fact.name,
          headline: '${fact.name} ${Formatters.won(fact.amountChange.abs())} 줄었습니다.',
          detail: '절약이 잘 되고 있습니다.',
        ),
      );
    }

    return insights;
  }

  /// 절약 제안.
  ///
  /// 자주 쓰는 항목을 조금 줄이는 쪽이 현실적이다.
  /// 월세를 줄이라는 제안은 쓸모가 없다.
  List<Insight> suggestions(InsightFacts facts, {int limit = 3}) {
    final List<Insight> result = <Insight>[];

    for (final ItemFact fact in facts.reducibleItems()) {
      if (result.length >= limit) break;

      // 횟수에 따라 현실적인 감축량을 정한다.
      final int reduceBy = _reasonableReduction(fact.count);
      final SavingScenario? scenario = facts.simulateReduction(
        target: fact.name,
        reduceBy: reduceBy,
      );
      if (scenario == null || !scenario.isMeaningful) continue;
      // 월 1만원 미만은 제안할 가치가 없다.
      if (scenario.savedPerMonth < 10000) continue;

      result.add(
        Insight(
          kind: InsightKind.suggestion,
          target: fact.name,
          savedPerMonth: scenario.savedPerMonth,
          headline: '${fact.name} ${fact.count}회 → $reduceBy회 줄이면 '
              '월 ${Formatters.won(scenario.savedPerMonth)} 절약',
          detail: '1회 평균 ${Formatters.won(fact.averageAmount)} · '
              '1년 ${Formatters.won(scenario.savedPerYear)}',
        ),
      );
    }

    return result;
  }

  /// 소비 습관.
  List<Insight> habits(InsightFacts facts, {int limit = 3}) {
    return facts
        .habitualPatterns()
        .take(limit)
        .map(
          (WeekdayPattern p) => Insight(
            kind: InsightKind.habit,
            target: p.subcategory,
            headline: '매주 ${p.weekdayLabel} ${p.subcategory} '
                '평균 ${Formatters.won(p.averageAmount)}',
            detail: '최근 ${p.weeksObserved}주 중 ${p.occurrences}주에 있었습니다.',
          ),
        )
        .toList();
  }

  /// "만약 이만큼 줄이면?" 시뮬레이션 문장.
  String describeScenario(SavingScenario scenario) {
    return '${scenario.target}을(를) ${scenario.reducedCount}회 줄이면\n'
        '1개월 ${Formatters.won(scenario.savedPerMonth)} · '
        '6개월 ${Formatters.won(scenario.savedPer6Months)} · '
        '1년 ${Formatters.won(scenario.savedPerYear)} 절약됩니다.';
  }

  /// 횟수에 비례한 현실적인 감축량.
  ///
  /// 20회 쓰는 것을 1회 줄이라고 하면 효과가 없고,
  /// 5회를 4회 줄이라고 하면 지키기 어렵다.
  static int _reasonableReduction(int count) {
    if (count >= 20) return 8;
    if (count >= 12) return 4;
    if (count >= 8) return 3;
    return 2;
  }
}
