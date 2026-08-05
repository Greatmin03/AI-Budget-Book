import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/statistics.dart';
import '../controllers/statistics_controller.dart';
import '../widgets/category_donut_chart.dart';
import '../widgets/category_tree_view.dart';
import '../widgets/flow_breakdown_card.dart';
import '../widgets/income_section.dart';
import '../widgets/monthly_trend_chart.dart';
import 'brand_detail_screen.dart';
import 'category_detail_screen.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late final StatisticsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = StatisticsController(
      repository: Injector.instance.statistics,
      analytics: Injector.instance.analytics,
      transactions: Injector.instance.transactions,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openCategory(String category, {String? subcategory}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailScreen(
          category: category,
          subcategory: subcategory,
          initialRange: _controller.range,
        ),
      ),
    );
  }

  void _openBrand(String brand) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrandDetailScreen(
          brand: brand,
          initialRange: _controller.range,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final PeriodStatistics stats = _controller.statistics;

        return Column(
          children: <Widget>[
            // 검색은 셸의 AppBar 에 있으므로 여기서 또 노출하지 않는다.
            PeriodSelector(
              range: _controller.range,
              onChanged: _controller.changeRange,
            ),
            Expanded(
              child: _controller.isLoading && !_controller.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _controller.load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: <Widget>[
                          _TotalSummary(stats: stats),
                          if (stats.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(
                                child: Text('이 기간에는 기록된 거래가 없습니다.'),
                              ),
                            )
                          else ...<Widget>[
                            // 소비/저축/청약/투자 분리는 카테고리 비율보다
                            // 먼저 보여 준다. "얼마 썼나" 의 정의가 여기서 정해진다.
                            if (stats.flow.hasAssetTransfers) ...<Widget>[
                              const SizedBox(height: 24),
                              _Section(
                                title: '돈이 어디로 갔나',
                                subtitle: '저축·청약·투자는 소비가 아닙니다',
                                child: FlowBreakdownCard(flow: stats.flow),
                              ),
                            ],
                            if (!stats.income.isEmpty) ...<Widget>[
                              const SizedBox(height: 24),
                              _Section(
                                title: '수입',
                                child: IncomeSection(income: stats.income),
                              ),
                            ],
                            const SizedBox(height: 24),
                            _Section(
                              title: '카테고리별 소비',
                              child: CategoryDonutChart(
                                items: stats.byCategory,
                                total: stats.total,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _Section(
                              title: '카테고리 상세',
                              subtitle: '눌러서 더 보기',
                              child: CategoryTreeView(
                                nodes: _controller.categoryTree,
                                total: stats.total,
                                onCategoryTap: (String c) => _openCategory(c),
                                onSubcategoryTap: (String c, String s) =>
                                    _openCategory(c, subcategory: s),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _Section(
                              title: '소비 추이',
                              subtitle: '최근 6개월',
                              child: MonthlyTrendChart(trend: stats.trend),
                            ),
                            const SizedBox(height: 24),
                            _BrandSection(
                              brands: _controller.brands,
                              sortBy: _controller.brandSortBy,
                              onSortChanged: _controller.changeBrandSort,
                              onBrandTap: _openBrand,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 기간 총액 + 직전 기간 대비 + 일평균.
class _TotalSummary extends StatelessWidget {
  const _TotalSummary({required this.stats});

  final PeriodStatistics stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? rate = stats.changeRate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${stats.range.label} 총 지출',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.signedWon(stats.total),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: <Widget>[
              _Meta(label: '${stats.transactionCount}건'),
              _Meta(label: '일평균 ${Formatters.won(stats.dailyAverage)}'),
              if (rate != null)
                _Meta(
                  label: '${stats.range.previousLabel}보다 '
                      '${Formatters.changeLabel(rate)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(context),
          child: child,
        ),
      ],
    );
  }
}

/// 브랜드별 분석: 금액 / 횟수 / 평균 / 최근 결제일.
class _BrandSection extends StatelessWidget {
  const _BrandSection({
    required this.brands,
    required this.sortBy,
    required this.onSortChanged,
    required this.onBrandTap,
  });

  final List<BrandStat> brands;
  final BrandSortBy sortBy;
  final ValueChanged<BrandSortBy> onSortChanged;
  final void Function(String brand) onBrandTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '브랜드별 소비',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            // 정렬 기준 전환. 색이 아니라 라벨로 현재 상태를 알린다.
            PopupMenuButton<BrandSortBy>(
              initialValue: sortBy,
              onSelected: onSortChanged,
              tooltip: '정렬 기준',
              itemBuilder: (BuildContext context) => BrandSortBy.values
                  .map(
                    (BrandSortBy value) => PopupMenuItem<BrandSortBy>(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              child: Row(
                children: <Widget>[
                  Text(
                    sortBy.label,
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppTheme.cardSurface(
          context,
          child: brands.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('데이터가 없습니다.', style: TextStyle(fontSize: 13)),
                )
              : Column(
                  children: List<Widget>.generate(brands.length, (int index) {
                    final BrandStat brand = brands[index];
                    return Column(
                      children: <Widget>[
                        if (index > 0) const Divider(height: 1),
                        ListTile(
                          onTap: () => onBrandTap(brand.brand),
                          title: Text(
                            brand.brand,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            <String>[
                              '${brand.count}회',
                              '평균 ${Formatters.won(brand.averageAmount)}',
                              if (brand.lastPaidAt != null)
                                '최근 ${brand.lastPaidAt!.month}/'
                                    '${brand.lastPaidAt!.day}',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            Formatters.won(brand.amount),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
        ),
      ],
    );
  }
}
