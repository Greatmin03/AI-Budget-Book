import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/month_range.dart';
import '../../../transactions/data/models/transaction_dto.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../recurring/domain/entities/recurring_rule.dart';
import '../../../recurring/domain/repositories/recurring_repository.dart';
import '../../../settlements/domain/repositories/settlement_repository.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/statistics.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../datasources/analytics_local_datasource.dart';
import '../datasources/statistics_local_datasource.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  AnalyticsRepositoryImpl({
    required AnalyticsLocalDataSource analytics,
    required StatisticsLocalDataSource statistics,
    required TransactionRepository transactions,
    required DepositRepository deposits,
    required RecurringRepository recurring,
  })  : _analytics = analytics,
        _statistics = statistics,
        _transactions = transactions,
        _deposits = deposits,
        _recurring = recurring;

  final AnalyticsLocalDataSource _analytics;
  final StatisticsLocalDataSource _statistics;
  final TransactionRepository _transactions;
  final DepositRepository _deposits;
  final RecurringRepository _recurring;

  // ------------------------------------------------------------- 대시보드
  @override
  Future<DashboardSummary> dashboard(
    DateRange range, {
    List<String> highlightSubcategories = const <String>['카페', '배달'],
  }) async {
    final DateRange previous = range.previous();

    final int total = await _statistics.totalInRange(range);
    final int grossTotal = await _statistics.grossTotalInRange(range);
    final int previousTotal = await _statistics.totalInRange(previous);
    final int count = await _statistics.countInRange(range);

    final Map<String, Object?>? topCategoryRow =
        await _analytics.topCategory(range);
    final Map<String, Object?>? topBrandRow =
        await _analytics.topVisitedBrand(range);

    final List<SubcategoryHighlight> highlights = <SubcategoryHighlight>[];
    for (final String subcategory in highlightSubcategories) {
      final Map<String, Object?> current =
          await _statistics.subcategoryTotal(range, subcategory);
      final Map<String, Object?> before =
          await _statistics.subcategoryTotal(previous, subcategory);
      highlights.add(
        SubcategoryHighlight(
          subcategory: subcategory,
          amount: _int(current['amount']),
          count: _int(current['cnt']),
          previousAmount: _int(before['amount']),
        ),
      );
    }

    final int needsReview = await _transactions.countNeedingReview();
    final int pendingDeposits = await _deposits.countPending();
    final List<Transaction> recent = await _transactions.findRecent(limit: 5);

    final int cashOutflow = await _statistics.cashOutflowInRange(range);
    final int incomeTotal = await _statistics.incomeTotalInRange(range);
    final int incomeCount = await _statistics.incomeCountInRange(range);
    final int assetTransfers =
        await _statistics.assetTransferTotalInRange(range);

    // 정기결제: 곧 예정된 것 + 등록 제안 후보 수.
    final List<RecurringRule> activeRules = await _recurring.findActive();
    final List<RecurringRule> upcoming = activeRules.where((RecurringRule r) {
      final int? days = r.daysUntilNext();
      // 지난 예정일(연체)과 30일 내 예정을 함께 보여 준다.
      return days != null && days <= 30;
    }).toList();

    return DashboardSummary(
      range: range,
      total: total,
      grossTotal: grossTotal,
      cashOutflow: cashOutflow,
      assetTransferTotal: assetTransfers,
      incomeTotal: incomeTotal,
      incomeCount: incomeCount,
      upcomingRecurring: upcoming,
      pendingDepositCount: pendingDeposits,
      previousTotal: previousTotal,
      transactionCount: count,
      // 진행 중인 기간이면 지난 일수로 나눈다.
      dailyAverage: range.elapsedDays == 0
          ? 0
          : (total / range.elapsedDays).round(),
      topCategory:
          topCategoryRow == null ? null : _toCategoryAmount(topCategoryRow),
      topVisitedBrand: topBrandRow == null ? null : _toBrandStat(topBrandRow),
      highlights: highlights,
      needsReviewCount: needsReview,
      recentTransactions: recent,
    );
  }

  // ------------------------------------------------------------- 브랜드 목록
  @override
  Future<List<BrandStat>> brandStats(
    DateRange range, {
    BrandSortBy sortBy = BrandSortBy.amount,
    int limit = 50,
  }) async {
    final List<Map<String, Object?>> rows = await _analytics.brandStats(
      range: range,
      orderBy: _orderByFor(sortBy),
      limit: limit,
    );

    final Map<String, _CategoryLabel> primary =
        await _primaryCategories(range);

    return rows.map((Map<String, Object?> row) {
      final BrandStat base = _toBrandStat(row);
      final _CategoryLabel? label = primary[base.brand];
      return BrandStat(
        brand: base.brand,
        amount: base.amount,
        count: base.count,
        lastPaidAt: base.lastPaidAt,
        category: label?.category,
        subcategory: label?.subcategory,
      );
    }).toList();
  }

  /// 정렬 기준 -> ORDER BY 절.
  ///
  /// 문자열을 그대로 SQL 에 넣으므로 **enum 에서만 만들어진다**
  /// (사용자 입력이 여기로 들어오는 경로는 없다).
  static String _orderByFor(BrandSortBy sortBy) {
    switch (sortBy) {
      case BrandSortBy.amount:
        return 'amount DESC';
      case BrandSortBy.count:
        return 'cnt DESC, amount DESC';
      case BrandSortBy.average:
        return 'avg_amount DESC';
      case BrandSortBy.recent:
        return 'last_at DESC';
    }
  }

  /// 브랜드별 대표 카테고리(건수 최다) 맵.
  Future<Map<String, _CategoryLabel>> _primaryCategories(
    DateRange range,
  ) async {
    final List<Map<String, Object?>> rows =
        await _analytics.brandPrimaryCategories(range);

    // 쿼리가 brand ASC, cnt DESC 로 정렬되어 있으므로
    // 브랜드별 첫 행이 대표 카테고리다.
    final Map<String, _CategoryLabel> result = <String, _CategoryLabel>{};
    for (final Map<String, Object?> row in rows) {
      final String brand = (row['brand'] as String?) ?? '';
      if (result.containsKey(brand)) continue;
      result[brand] = _CategoryLabel(
        category: (row['category'] as String?) ?? '기타',
        subcategory: (row['subcategory'] as String?) ?? '기타',
      );
    }
    return result;
  }

  // ------------------------------------------------------------ 카테고리 트리
  @override
  Future<List<CategoryNode>> categoryTree(DateRange range) async {
    final List<Map<String, Object?>> rows =
        await _analytics.categorySubcategoryTotals(range);

    final Map<String, List<CategoryAmount>> children =
        <String, List<CategoryAmount>>{};
    final Map<String, int> totals = <String, int>{};
    final Map<String, int> counts = <String, int>{};

    for (final Map<String, Object?> row in rows) {
      final String category = (row['category'] as String?) ?? '기타';
      final int amount = _int(row['amount']);
      final int count = _int(row['cnt']);

      children.putIfAbsent(category, () => <CategoryAmount>[]).add(
            CategoryAmount(
              name: (row['subcategory'] as String?) ?? '기타',
              parentCategory: category,
              amount: amount,
              count: count,
            ),
          );
      totals[category] = (totals[category] ?? 0) + amount;
      counts[category] = (counts[category] ?? 0) + count;
    }

    final List<CategoryNode> nodes = children.keys
        .map(
          (String category) => CategoryNode(
            category: category,
            amount: totals[category] ?? 0,
            count: counts[category] ?? 0,
            children: children[category]!,
          ),
        )
        .toList();

    nodes.sort((CategoryNode a, CategoryNode b) => b.amount.compareTo(a.amount));
    return nodes;
  }

  // ------------------------------------------------------------- 브랜드 상세
  @override
  Future<BrandDetail> brandDetail(
    String brand,
    DateRange range, {
    int trendMonths = 6,
    int transactionLimit = 200,
  }) async {
    final Map<String, Object?> totals =
        await _analytics.brandTotal(range: range, brand: brand);

    final List<Map<String, Object?>> txRows =
        await _analytics.brandTransactions(
      range: range,
      brand: brand,
      limit: transactionLimit,
    );

    final List<Map<String, Object?>> branchRows =
        await _analytics.brandBranches(range: range, brand: brand);

    // 추이는 기간 필터와 무관하게 "최근 N개월" 을 보여 준다.
    final List<MonthlyTotal> trend = <MonthlyTotal>[];
    for (final MonthRange month
        in MonthRange.of(DateTime.now()).lastMonths(trendMonths)) {
      trend.add(
        MonthlyTotal(
          month: month,
          amount: await _analytics.brandAmountInRange(
            range: DateRange.ofYearMonth(month.year, month.month),
            brand: brand,
          ),
        ),
      );
    }

    return BrandDetail(
      brand: brand,
      range: range,
      stat: BrandStat(
        brand: brand,
        amount: _int(totals['amount']),
        count: _int(totals['cnt']),
        lastPaidAt: _toDate(totals['last_at']),
      ),
      transactions: txRows.map(TransactionDto.fromRow).toList(),
      monthlyTrend: trend,
      branchBreakdown: branchRows
          .map(
            (Map<String, Object?> row) => BranchAmount(
              label: (row['label'] as String?) ?? '-',
              amount: _int(row['amount']),
              count: _int(row['cnt']),
            ),
          )
          .toList(),
    );
  }

  // ----------------------------------------------------------- 카테고리 상세
  @override
  Future<CategoryDetail> categoryDetail(
    String category,
    DateRange range, {
    String? subcategory,
    int trendMonths = 6,
  }) async {
    final Map<String, Object?> totals = await _analytics.categoryTotal(
      range: range,
      category: category,
      subcategory: subcategory,
    );
    final Map<String, Object?> previousTotals = await _analytics.categoryTotal(
      range: range.previous(),
      category: category,
      subcategory: subcategory,
    );

    final List<Map<String, Object?>> brandRows =
        await _analytics.brandsInCategory(
      range: range,
      category: category,
      subcategory: subcategory,
    );

    // 서브카테고리로 좁힌 경우엔 하위 분해가 의미 없다.
    final List<CategoryAmount> subcategories = subcategory != null
        ? const <CategoryAmount>[]
        : (await _analytics.subcategoriesOfCategory(
            range: range,
            category: category,
          ))
            .map(
              (Map<String, Object?> row) => CategoryAmount(
                name: (row['name'] as String?) ?? '기타',
                parentCategory: category,
                amount: _int(row['amount']),
                count: _int(row['cnt']),
              ),
            )
            .toList();

    final List<MonthlyTotal> trend = <MonthlyTotal>[];
    for (final MonthRange month
        in MonthRange.of(DateTime.now()).lastMonths(trendMonths)) {
      trend.add(
        MonthlyTotal(
          month: month,
          amount: await _analytics.categoryAmountInRange(
            range: DateRange.ofYearMonth(month.year, month.month),
            category: category,
            subcategory: subcategory,
          ),
        ),
      );
    }

    return CategoryDetail(
      category: subcategory ?? category,
      range: range,
      total: _int(totals['amount']),
      count: _int(totals['cnt']),
      previousTotal: _int(previousTotals['amount']),
      brands: brandRows.map(_toBrandStat).toList(),
      subcategories: subcategories,
      monthlyTrend: trend,
    );
  }

  // ------------------------------------------------------------------- 검색
  @override
  Future<List<BrandSearchResult>> searchBrands(
    String query,
    DateRange range, {
    int limit = 50,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <BrandSearchResult>[];

    final List<Map<String, Object?>> rows = await _analytics.searchBrands(
      range: range,
      query: trimmed,
      limit: limit,
    );
    final Map<String, _CategoryLabel> primary = await _primaryCategories(range);

    return rows.map((Map<String, Object?> row) {
      final String brand = (row['brand'] as String?) ?? '';
      final _CategoryLabel? label = primary[brand];
      return BrandSearchResult(
        brand: brand,
        amount: _int(row['amount']),
        count: _int(row['cnt']),
        lastPaidAt: _toDate(row['last_at']),
        category: label?.category,
        subcategory: label?.subcategory,
      );
    }).toList();
  }

  // ---------------------------------------------------------------- 변환기
  static BrandStat _toBrandStat(Map<String, Object?> row) => BrandStat(
        brand: (row['brand'] as String?) ?? '미확인',
        amount: _int(row['amount']),
        count: _int(row['cnt']),
        lastPaidAt: _toDate(row['last_at']),
      );

  static CategoryAmount _toCategoryAmount(Map<String, Object?> row) =>
      CategoryAmount(
        name: (row['name'] as String?) ?? '기타',
        amount: _int(row['amount']),
        count: _int(row['cnt']),
      );

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  static DateTime? _toDate(Object? value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }
}

/// 브랜드 대표 카테고리(내부용).
class _CategoryLabel {
  const _CategoryLabel({required this.category, required this.subcategory});

  final String category;
  final String subcategory;
}
