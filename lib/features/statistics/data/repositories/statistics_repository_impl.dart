import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/month_range.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/statistics.dart';
import '../../domain/repositories/statistics_repository.dart';
import '../datasources/statistics_local_datasource.dart';

class StatisticsRepositoryImpl implements StatisticsRepository {
  StatisticsRepositoryImpl(this._local);

  final StatisticsLocalDataSource _local;

  @override
  Future<PeriodStatistics> statistics(
    DateRange range, {
    int trendMonths = 6,
    List<String> highlightSubcategories = const <String>['카페', '배달'],
  }) async {
    final DateRange previous = range.previous();

    final int total = await _local.totalInRange(range);
    final int previousTotal = await _local.totalInRange(previous);
    final int count = await _local.countInRange(range);

    final List<CategoryAmount> byCategory =
        (await _local.byCategory(range)).map(_toCategoryAmount).toList();

    final List<CategoryAmount> bySubcategory =
        (await _local.bySubcategory(range)).map(_toSubcategoryAmount).toList();

    final List<BrandAmount> byBrand =
        (await _local.byBrand(range, 10)).map(_toBrandAmount).toList();

    final List<BrandAmount> topMerchants =
        (await _local.topVisited(range, 5)).map(_toBrandAmount).toList();

    // 추이: 월별 합계를 개별 쿼리로 계산한다.
    // (SQLite 의 strftime 으로 로컬 타임존 월 경계를 계산하는 것보다 안전하다)
    final List<MonthlyTotal> trend = <MonthlyTotal>[];
    for (final MonthRange month
        in MonthRange.of(DateTime.now()).lastMonths(trendMonths)) {
      trend.add(
        MonthlyTotal(
          month: month,
          amount: await _local.totalInRange(
            DateRange.ofYearMonth(month.year, month.month),
          ),
        ),
      );
    }

    final List<DailyTotal> dailyTotals = await _dailyTotals(range);

    final FlowBreakdown flow = await _flowBreakdown(range, spending: total);
    final IncomeStatistics income = await _income(
      range,
      previous: previous,
      trendMonths: trendMonths,
    );

    final List<SubcategoryHighlight> highlights = <SubcategoryHighlight>[];
    for (final String subcategory in highlightSubcategories) {
      final Map<String, Object?> currentRow =
          await _local.subcategoryTotal(range, subcategory);
      final Map<String, Object?> previousRow =
          await _local.subcategoryTotal(previous, subcategory);
      highlights.add(
        SubcategoryHighlight(
          subcategory: subcategory,
          amount: _int(currentRow['amount']),
          count: _int(currentRow['cnt']),
          previousAmount: _int(previousRow['amount']),
        ),
      );
    }

    return PeriodStatistics(
      range: range,
      total: total,
      previousTotal: previousTotal,
      transactionCount: count,
      byCategory: byCategory,
      bySubcategory: bySubcategory,
      byBrand: byBrand,
      topMerchants: topMerchants,
      trend: trend,
      dailyTotals: dailyTotals,
      highlights: highlights,
      flow: flow,
      income: income,
    );
  }

  /// 소비 / 저축 / 청약 / 투자로 나눈다.
  ///
  /// 소비는 이미 계산된 값을 그대로 받는다(같은 값을 두 번 쿼리하지 않는다).
  Future<FlowBreakdown> _flowBreakdown(
    DateRange range, {
    required int spending,
  }) async {
    final Map<String, int> byKind = <String, int>{
      for (final Map<String, Object?> row
          in await _local.assetTransfersByKind(range))
        (row['kind'] as String?) ?? 'other': _int(row['amount']),
    };

    return FlowBreakdown(
      spending: spending,
      saving: byKind[AssetKind.saving.code] ?? 0,
      housing: byKind[AssetKind.housing.code] ?? 0,
      investment: byKind[AssetKind.investment.code] ?? 0,
      otherAssetTransfer: byKind[AssetKind.other.code] ?? 0,
    );
  }

  /// 수입 통계. 지출과 완전히 분리된 집계다.
  Future<IncomeStatistics> _income(
    DateRange range, {
    required DateRange previous,
    required int trendMonths,
  }) async {
    final List<MonthlyTotal> trend = <MonthlyTotal>[];
    for (final MonthRange month
        in MonthRange.of(DateTime.now()).lastMonths(trendMonths)) {
      trend.add(
        MonthlyTotal(
          month: month,
          amount: await _local.incomeTotalInRange(
            DateRange.ofYearMonth(month.year, month.month),
          ),
        ),
      );
    }

    return IncomeStatistics(
      total: await _local.incomeTotalInRange(range),
      previousTotal: await _local.incomeTotalInRange(previous),
      count: await _local.incomeCountInRange(range),
      byCategory: (await _local.incomeByCategory(range))
          .map(_toCategoryAmount)
          .toList(),
      trend: trend,
    );
  }

  Future<List<DailyTotal>> _dailyTotals(DateRange range) async {
    final List<Map<String, Object?>> rows =
        await _local.paymentTimesInRange(range);

    final Map<int, int> byDay = <int, int>{};
    for (final Map<String, Object?> row in rows) {
      final int ts = _int(row['ts']);
      if (ts == 0) continue;
      final int day = DateTime.fromMillisecondsSinceEpoch(ts).day;
      byDay[day] = (byDay[day] ?? 0) + _int(row['amount']);
    }

    final List<int> days = byDay.keys.toList()..sort();
    return days
        .map((int day) => DailyTotal(day: day, amount: byDay[day]!))
        .toList();
  }

  static CategoryAmount _toCategoryAmount(Map<String, Object?> row) {
    return CategoryAmount(
      name: (row['name'] as String?) ?? '기타',
      amount: _int(row['amount']),
      count: _int(row['cnt']),
    );
  }

  static CategoryAmount _toSubcategoryAmount(Map<String, Object?> row) {
    return CategoryAmount(
      name: (row['name'] as String?) ?? '기타',
      parentCategory: row['parent'] as String?,
      amount: _int(row['amount']),
      count: _int(row['cnt']),
    );
  }

  static BrandAmount _toBrandAmount(Map<String, Object?> row) {
    return BrandAmount(
      brand: (row['brand'] as String?) ?? '미확인',
      amount: _int(row['amount']),
      count: _int(row['cnt']),
    );
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}
