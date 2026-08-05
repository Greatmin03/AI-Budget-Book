import '../../../../core/utils/date_range.dart';
import '../../../recurring/domain/entities/recurring_rule.dart';
import '../../../transactions/domain/entities/transaction.dart';
import 'statistics.dart';

/// 브랜드별 집계 한 줄.
class BrandStat {
  const BrandStat({
    required this.brand,
    required this.amount,
    required this.count,
    required this.lastPaidAt,
    this.category,
    this.subcategory,
  });

  final String brand;

  /// 부호 있는 합계(취소 차감).
  final int amount;

  /// 결제 횟수.
  final int count;

  /// 최근 결제일.
  final DateTime? lastPaidAt;

  /// 대표 카테고리(가장 많이 쓰인 분류).
  final String? category;
  final String? subcategory;

  /// 평균 결제금액.
  int get averageAmount => count == 0 ? 0 : (amount / count).round();
}

/// 카테고리 -> 서브카테고리 트리 한 노드.
///
/// 요구사항 1의 트리 표시에 그대로 대응한다.
/// ```
/// 식비
///  ├─ 카페   85,400원
///  └─ 배달   96,000원
/// ```
class CategoryNode {
  const CategoryNode({
    required this.category,
    required this.amount,
    required this.count,
    required this.children,
  });

  final String category;
  final int amount;
  final int count;

  /// 서브카테고리별 내역(금액 내림차순).
  final List<CategoryAmount> children;

  double ratioOf(int total) => total == 0 ? 0 : amount / total;

  /// 서브카테고리가 하나뿐이면 트리로 펼칠 이유가 없다.
  bool get hasBreakdown => children.length > 1;
}

/// 브랜드 상세 화면 데이터.
class BrandDetail {
  const BrandDetail({
    required this.brand,
    required this.range,
    required this.stat,
    required this.transactions,
    required this.monthlyTrend,
    required this.branchBreakdown,
  });

  final String brand;
  final DateRange range;
  final BrandStat stat;

  /// 결제 내역(최신순).
  final List<Transaction> transactions;

  /// 최근 몇 개월 소비 추이.
  final List<MonthlyTotal> monthlyTrend;

  /// 지점별 집계. 지점 정보가 없으면 비어 있다.
  final List<BranchAmount> branchBreakdown;

  bool get isEmpty => stat.count == 0;
}

/// 지점별 집계.
class BranchAmount {
  const BranchAmount({
    required this.label,
    required this.amount,
    required this.count,
  });

  /// 지점명(없으면 알림 원본 문자열).
  final String label;
  final int amount;
  final int count;
}

/// 카테고리 상세 화면 데이터.
class CategoryDetail {
  const CategoryDetail({
    required this.category,
    required this.range,
    required this.total,
    required this.count,
    required this.previousTotal,
    required this.brands,
    required this.subcategories,
    required this.monthlyTrend,
  });

  final String category;
  final DateRange range;
  final int total;
  final int count;

  /// 직전 같은 기간 합계(증감 비교).
  final int previousTotal;

  /// 이 카테고리에 속한 브랜드 목록(금액 내림차순).
  final List<BrandStat> brands;

  /// 서브카테고리별 내역.
  final List<CategoryAmount> subcategories;

  /// 카테고리별 소비 추이.
  final List<MonthlyTotal> monthlyTrend;

  bool get isEmpty => count == 0;

  double? get changeRate {
    if (previousTotal == 0) return null;
    return (total - previousTotal) / previousTotal * 100;
  }
}

/// 브랜드 검색 결과 한 줄.
class BrandSearchResult {
  const BrandSearchResult({
    required this.brand,
    required this.amount,
    required this.count,
    required this.lastPaidAt,
    this.category,
    this.subcategory,
  });

  final String brand;
  final int amount;
  final int count;
  final DateTime? lastPaidAt;
  final String? category;
  final String? subcategory;

  int get averageAmount => count == 0 ? 0 : (amount / count).round();
}

/// 대시보드 요약.
class DashboardSummary {
  const DashboardSummary({
    required this.range,
    required this.total,
    required this.previousTotal,
    required this.transactionCount,
    required this.dailyAverage,
    required this.topCategory,
    required this.topVisitedBrand,
    required this.highlights,
    required this.needsReviewCount,
    required this.pendingDepositCount,
    required this.grossTotal,
    required this.cashOutflow,
    required this.assetTransferTotal,
    required this.incomeTotal,
    required this.incomeCount,
    required this.upcomingRecurring,
    required this.recentTransactions,
  });

  const DashboardSummary.empty(this.range)
      : total = 0,
        grossTotal = 0,
        cashOutflow = 0,
        assetTransferTotal = 0,
        incomeTotal = 0,
        incomeCount = 0,
        previousTotal = 0,
        transactionCount = 0,
        dailyAverage = 0,
        topCategory = null,
        topVisitedBrand = null,
        highlights = const <SubcategoryHighlight>[],
        needsReviewCount = 0,
        pendingDepositCount = 0,
        upcomingRecurring = const <RecurringRule>[],
        recentTransactions = const <Transaction>[];

  final DateRange range;

  /// **실제 부담 합계**(정산 차감 후). 대시보드가 강조하는 값이다.
  final int total;

  /// 원본 결제 합계(정산 차감 전). 카드 명세와 비교할 때 쓴다.
  final int grossTotal;

  /// **현금 흐름** — 자산 이동까지 포함한 계좌 유출 합계.
  final int cashOutflow;

  /// 소비에서 제외된 자산 이동 합계(적금 납입 등).
  final int assetTransferTotal;

  /// 기간 내 **수입** 합계. 지출과 절대 합산하지 않는다.
  final int incomeTotal;

  final int incomeCount;

  /// **순증가** = 수입 - 나간 돈.
  ///
  /// 자산 이동(적금 납입)은 빼지 않는다. 통장에서는 나갔지만 내 자산으로
  /// 남아 있으므로 순증가를 줄이지 않는다.
  int get netChange => incomeTotal - total;

  /// 통장 기준 순증가(자산 이동까지 빠져나간 것으로 본다).
  int get netCashChange => incomeTotal - cashOutflow;

  bool get hasIncome => incomeTotal != 0;

  final int previousTotal;
  final int transactionCount;

  /// 평균 하루 소비(실제 부담 기준).
  final int dailyAverage;

  /// 가장 많이 소비한 카테고리.
  final CategoryAmount? topCategory;

  /// 가장 많이 방문한 브랜드.
  final BrandStat? topVisitedBrand;

  /// "이번 달 커피값", "이번 달 배달비" 같은 지표.
  final List<SubcategoryHighlight> highlights;

  /// 사용자 확인이 필요한 거래 수.
  final int needsReviewCount;

  /// 아직 거래에 연결되지 않은 입금 수(정산 후보).
  final int pendingDepositCount;

  /// 곧 결제될 정기결제(예정일 빠른 순).
  ///
  /// 정기결제 **후보 감지**는 비용이 크므로 여기에 넣지 않는다.
  /// 대시보드 컨트롤러가 별도로, 거래가 바뀔 때마다가 아니라 필요할 때만 계산한다.
  final List<RecurringRule> upcomingRecurring;

  final List<Transaction> recentTransactions;

  bool get isEmpty => transactionCount == 0 && incomeCount == 0;

  /// 이 기간에 정산으로 돌려받은 금액.
  int get settledTotal => grossTotal - total;

  bool get hasSettlements => settledTotal != 0;

  bool get hasAssetTransfers => assetTransferTotal != 0;

  double? get changeRate {
    if (previousTotal == 0) return null;
    return (total - previousTotal) / previousTotal * 100;
  }
}

/// 브랜드 정렬 기준.
enum BrandSortBy {
  amount('금액순'),
  count('횟수순'),
  average('평균순'),
  recent('최근순');

  const BrandSortBy(this.label);

  final String label;
}
