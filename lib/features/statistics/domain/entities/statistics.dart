import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/month_range.dart';

/// 카테고리(또는 서브카테고리)별 집계.
class CategoryAmount {
  const CategoryAmount({
    required this.name,
    required this.amount,
    required this.count,
    this.parentCategory,
  });

  final String name;

  /// 부호 있는 합계(취소 거래가 차감된 실제 지출).
  final int amount;
  final int count;

  /// 서브카테고리 집계일 때의 상위 카테고리.
  final String? parentCategory;

  /// 전체 대비 비율(0~1). [total] 이 0이면 0.
  double ratioOf(int total) => total == 0 ? 0 : amount / total;
}

/// 브랜드별 집계.
class BrandAmount {
  const BrandAmount({
    required this.brand,
    required this.amount,
    required this.count,
  });

  final String brand;
  final int amount;
  final int count;
}

/// 월별 합계(추이 그래프용).
class MonthlyTotal {
  const MonthlyTotal({required this.month, required this.amount});

  final MonthRange month;
  final int amount;
}

/// 일별 합계(월 내 소비 흐름).
class DailyTotal {
  const DailyTotal({required this.day, required this.amount});

  /// 해당 월의 일(1~31).
  final int day;
  final int amount;
}

/// 특정 서브카테고리의 이번 달 지표. ("이번 달 커피값", "이번 달 배달비")
class SubcategoryHighlight {
  const SubcategoryHighlight({
    required this.subcategory,
    required this.amount,
    required this.count,
    required this.previousAmount,
  });

  final String subcategory;
  final int amount;
  final int count;

  /// 지난달 같은 항목의 합계(증감 비교용).
  final int previousAmount;

  /// 증감률(%). 지난달이 0이면 비교 불가이므로 null.
  double? get changeRate {
    if (previousAmount == 0) return null;
    return (amount - previousAmount) / previousAmount * 100;
  }
}

/// 통계 화면이 한 번에 필요한 모든 데이터.
/// 돈이 어디로 갔는지 네 갈래로 나눈 요약.
///
/// 적금·청약·투자는 **소비가 아니다.** 소비 통계에 섞이면
/// "이번 달 450,000원 썼다" 가 "1,550,000원 썼다" 로 보인다.
class FlowBreakdown {
  const FlowBreakdown({
    required this.spending,
    required this.saving,
    required this.housing,
    required this.investment,
    required this.otherAssetTransfer,
  });

  const FlowBreakdown.empty()
      : spending = 0,
        saving = 0,
        housing = 0,
        investment = 0,
        otherAssetTransfer = 0;

  /// 소비(실제로 사라진 돈).
  final int spending;

  /// 저축(적금 등).
  final int saving;

  /// 청약.
  final int housing;

  /// 투자.
  final int investment;

  /// 종류를 지정하지 않은 자산 이동.
  final int otherAssetTransfer;

  /// 내 자산으로 남은 돈(저축 + 청약 + 투자 + 기타).
  int get keptAsAssets => saving + housing + investment + otherAssetTransfer;

  /// 통장에서 나간 돈 전체.
  int get totalOutflow => spending + keptAsAssets;

  bool get hasAssetTransfers => keptAsAssets != 0;

  bool get isEmpty => totalOutflow == 0;

  /// 나간 돈 중 자산으로 남긴 비율(%). 저축률.
  double? get savingRate {
    if (totalOutflow == 0) return null;
    return keptAsAssets / totalOutflow * 100;
  }
}

/// 수입 통계.
class IncomeStatistics {
  const IncomeStatistics({
    required this.total,
    required this.previousTotal,
    required this.count,
    required this.byCategory,
    required this.trend,
  });

  const IncomeStatistics.empty()
      : total = 0,
        previousTotal = 0,
        count = 0,
        byCategory = const <CategoryAmount>[],
        trend = const <MonthlyTotal>[];

  final int total;
  final int previousTotal;
  final int count;

  /// 급여 / 장학금 / 용돈 / 부수입 ...
  final List<CategoryAmount> byCategory;

  /// 월별 수입 추이.
  final List<MonthlyTotal> trend;

  bool get isEmpty => count == 0;

  double? get changeRate {
    if (previousTotal == 0) return null;
    return (total - previousTotal) / previousTotal * 100;
  }
}

class PeriodStatistics {
  const PeriodStatistics({
    required this.range,
    required this.total,
    required this.previousTotal,
    required this.transactionCount,
    required this.byCategory,
    required this.bySubcategory,
    required this.byBrand,
    required this.topMerchants,
    required this.trend,
    required this.dailyTotals,
    required this.highlights,
    this.flow = const FlowBreakdown.empty(),
    this.income = const IncomeStatistics.empty(),
  });

  const PeriodStatistics.empty(this.range)
      : total = 0,
        previousTotal = 0,
        transactionCount = 0,
        byCategory = const <CategoryAmount>[],
        bySubcategory = const <CategoryAmount>[],
        byBrand = const <BrandAmount>[],
        topMerchants = const <BrandAmount>[],
        trend = const <MonthlyTotal>[],
        dailyTotals = const <DailyTotal>[],
        highlights = const <SubcategoryHighlight>[],
        flow = const FlowBreakdown.empty(),
        income = const IncomeStatistics.empty();

  final DateRange range;
  final int total;
  final int previousTotal;
  final int transactionCount;

  final List<CategoryAmount> byCategory;
  final List<CategoryAmount> bySubcategory;
  final List<BrandAmount> byBrand;

  /// 방문 횟수 기준 상위 가맹점. ("가장 많이 간 가게")
  final List<BrandAmount> topMerchants;

  final List<MonthlyTotal> trend;
  final List<DailyTotal> dailyTotals;
  final List<SubcategoryHighlight> highlights;

  /// 소비 / 저축 / 청약 / 투자 분리.
  final FlowBreakdown flow;

  /// 수입 통계. 지출과 절대 합산하지 않는다.
  final IncomeStatistics income;

  bool get isEmpty => transactionCount == 0 && income.isEmpty;

  /// 직전 기간 대비 증감률(%). 직전 기간 지출이 0이면 null.
  double? get changeRate {
    if (previousTotal == 0) return null;
    return (total - previousTotal) / previousTotal * 100;
  }

  /// 일평균 지출. 진행 중인 기간이면 지난 일수로 나눈다.
  int get dailyAverage {
    final int days = range.elapsedDays;
    return days == 0 ? 0 : (total / days).round();
  }
}
