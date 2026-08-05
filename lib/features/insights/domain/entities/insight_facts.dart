import '../../../../core/utils/date_range.dart';

/// 한 항목(카테고리/세부항목/브랜드)의 기간 비교 사실.
///
/// **모든 숫자는 앱이 계산한다.** LLM 은 이 값을 문장으로 바꾸는 역할만 한다.
/// LLM 이 금액을 직접 계산하면 틀리기 때문이다.
class ItemFact {
  const ItemFact({
    required this.name,
    required this.amount,
    required this.count,
    required this.previousAmount,
    required this.previousCount,
    this.parent,
  });

  final String name;

  /// 상위 항목(세부항목이면 카테고리, 브랜드면 세부항목).
  final String? parent;

  final int amount;
  final int count;
  final int previousAmount;
  final int previousCount;

  /// 1회 평균 금액.
  int get averageAmount => count == 0 ? 0 : (amount / count).round();

  /// 증감액.
  int get amountChange => amount - previousAmount;

  /// 증감 횟수.
  int get countChange => count - previousCount;

  /// 증감률(%). 이전 기간이 0이면 비교 불가.
  double? get changeRate {
    if (previousAmount == 0) return null;
    return (amount - previousAmount) / previousAmount * 100;
  }

  bool get increased => amountChange > 0;
  bool get decreased => amountChange < 0;

  /// 새로 생긴 항목(이전 기간에 없었다).
  bool get isNew => previousAmount == 0 && amount != 0;

  /// "의미 있는" 변화인지.
  ///
  /// 금액이 작으면 비율이 커도 알릴 가치가 없다.
  /// (500원 → 1,500원은 200% 증가지만 사용자에게 무의미하다)
  bool isNotable({int minAmount = 10000, double minRate = 15}) {
    if (amount.abs() < minAmount) return false;
    final double? rate = changeRate;
    if (rate == null) return amount >= minAmount;
    return rate.abs() >= minRate;
  }
}

/// 요일별 소비 패턴.
///
/// "매주 금요일 술 평균 42,000원" 같은 사실을 만든다.
class WeekdayPattern {
  const WeekdayPattern({
    required this.weekday,
    required this.subcategory,
    required this.averageAmount,
    required this.occurrences,
    required this.weeksObserved,
  });

  /// `DateTime.monday` ~ `DateTime.sunday`
  final int weekday;

  final String subcategory;

  /// 그 요일 1회 평균 금액.
  final int averageAmount;

  /// 관측된 결제 횟수.
  final int occurrences;

  /// 관측 기간의 주 수.
  final int weeksObserved;

  /// 그 요일마다 거의 빠지지 않고 쓰는지.
  ///
  /// 관측된 주의 60% 이상에서 발생했으면 습관으로 본다.
  bool get isHabitual {
    if (weeksObserved < 3) return false;
    return occurrences / weeksObserved >= 0.6;
  }

  static const List<String> weekdayNames = <String>[
    '', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일',
  ];

  String get weekdayLabel =>
      (weekday >= 1 && weekday <= 7) ? weekdayNames[weekday] : '';
}

/// 절약 시뮬레이션 결과.
///
/// "카페를 주 2회 줄이면?" 에 대한 답. 전부 앱이 계산한 산수다.
class SavingScenario {
  const SavingScenario({
    required this.target,
    required this.currentCount,
    required this.currentAmount,
    required this.reducedCount,
    required this.averageAmount,
  });

  /// 대상 이름(브랜드 또는 세부항목).
  final String target;

  /// 현재 기간의 이용 횟수/금액.
  final int currentCount;
  final int currentAmount;

  /// 줄이려는 횟수.
  final int reducedCount;

  /// 1회 평균 금액.
  final int averageAmount;

  /// 이 기간에 절약되는 금액.
  int get savedPerPeriod => averageAmount * reducedCount;

  /// 월 기준 절약액(기간이 한 달이라고 가정한 값).
  int get savedPerMonth => savedPerPeriod;

  int get savedPer6Months => savedPerMonth * 6;
  int get savedPerYear => savedPerMonth * 12;

  /// 줄인 뒤의 예상 횟수.
  int get remainingCount {
    final int remaining = currentCount - reducedCount;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isMeaningful => savedPerMonth > 0 && reducedCount > 0;
}

/// 기간 전체의 사실 묶음.
///
/// AI 기능(소비 분석·절약 제안·습관 분석·리포트·채팅)이 모두 이 하나를 쓴다.
/// 화면마다 따로 계산하면 같은 항목의 숫자가 화면별로 어긋난다.
class InsightFacts {
  const InsightFacts({
    required this.range,
    required this.total,
    required this.previousTotal,
    required this.transactionCount,
    required this.dailyAverage,
    required this.categories,
    required this.subcategories,
    required this.brands,
    required this.weekdayPatterns,
  });

  const InsightFacts.empty(this.range)
      : total = 0,
        previousTotal = 0,
        transactionCount = 0,
        dailyAverage = 0,
        categories = const <ItemFact>[],
        subcategories = const <ItemFact>[],
        brands = const <ItemFact>[],
        weekdayPatterns = const <WeekdayPattern>[];

  final DateRange range;
  final int total;
  final int previousTotal;
  final int transactionCount;
  final int dailyAverage;

  /// 금액 내림차순.
  final List<ItemFact> categories;
  final List<ItemFact> subcategories;
  final List<ItemFact> brands;

  final List<WeekdayPattern> weekdayPatterns;

  bool get isEmpty => transactionCount == 0;

  int get amountChange => total - previousTotal;

  double? get changeRate {
    if (previousTotal == 0) return null;
    return (total - previousTotal) / previousTotal * 100;
  }

  /// 지출이 늘어난 주요 원인(증가액 큰 순).
  ///
  /// "이번 달 왜 돈을 많이 썼어?" 에 대한 답의 근거.
  List<ItemFact> topIncreases({int limit = 3}) {
    final List<ItemFact> increased = subcategories
        .where((ItemFact f) => f.increased && f.isNotable())
        .toList()
      ..sort((ItemFact a, ItemFact b) => b.amountChange.compareTo(a.amountChange));
    return increased.take(limit).toList();
  }

  /// 줄어든 항목(절약 성공).
  List<ItemFact> topDecreases({int limit = 3}) {
    final List<ItemFact> decreased = subcategories
        .where((ItemFact f) => f.decreased && f.isNotable())
        .toList()
      ..sort((ItemFact a, ItemFact b) => a.amountChange.compareTo(b.amountChange));
    return decreased.take(limit).toList();
  }

  /// 습관으로 볼 만한 요일 패턴.
  List<WeekdayPattern> habitualPatterns() =>
      weekdayPatterns.where((WeekdayPattern p) => p.isHabitual).toList();

  /// 절약 여지가 큰 항목(횟수가 많고 금액이 큰 순).
  ///
  /// 한 번에 크게 쓰는 항목(월세)보다 자주 쓰는 항목(카페)이 줄이기 쉽다.
  List<ItemFact> reducibleItems({int minCount = 5, int limit = 5}) {
    final List<ItemFact> candidates =
        brands.where((ItemFact f) => f.count >= minCount).toList()
          ..sort((ItemFact a, ItemFact b) => b.amount.compareTo(a.amount));
    return candidates.take(limit).toList();
  }

  /// 특정 항목을 [reduceBy] 회 줄이면 얼마가 절약되는지.
  SavingScenario? simulateReduction({
    required String target,
    required int reduceBy,
  }) {
    final ItemFact? fact = _findItem(target);
    if (fact == null || fact.count == 0) return null;

    return SavingScenario(
      target: fact.name,
      currentCount: fact.count,
      currentAmount: fact.amount,
      reducedCount: reduceBy > fact.count ? fact.count : reduceBy,
      averageAmount: fact.averageAmount,
    );
  }

  /// 특정 항목을 [ratio] 비율만큼 줄이면.
  SavingScenario? simulateReductionByRatio({
    required String target,
    required double ratio,
  }) {
    final ItemFact? fact = _findItem(target);
    if (fact == null || fact.count == 0) return null;

    final int reduce = (fact.count * ratio).round();
    return SavingScenario(
      target: fact.name,
      currentCount: fact.count,
      currentAmount: fact.amount,
      reducedCount: reduce < 1 ? 1 : reduce,
      averageAmount: fact.averageAmount,
    );
  }

  ItemFact? _findItem(String name) {
    for (final ItemFact fact in brands) {
      if (fact.name == name) return fact;
    }
    for (final ItemFact fact in subcategories) {
      if (fact.name == name) return fact;
    }
    for (final ItemFact fact in categories) {
      if (fact.name == name) return fact;
    }
    return null;
  }
}
