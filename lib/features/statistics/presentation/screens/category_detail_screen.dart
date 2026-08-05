import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/statistics.dart';
import '../widgets/monthly_trend_chart.dart';
import 'brand_detail_screen.dart';

/// 카테고리(또는 세부 항목) 상세: 총 소비 + 속한 브랜드 목록.
class CategoryDetailScreen extends StatefulWidget {
  const CategoryDetailScreen({
    required this.category,
    required this.initialRange,
    this.subcategory,
    super.key,
  });

  final String category;

  /// 주어지면 이 세부 항목으로 좁혀서 본다(예: 식비 > 카페).
  final String? subcategory;

  final DateRange initialRange;

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late DateRange _range = widget.initialRange;
  CategoryDetail? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final CategoryDetail detail =
          await Injector.instance.analytics.categoryDetail(
        widget.category,
        _range,
        subcategory: widget.subcategory,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('카테고리 상세 조회 실패', e, stack);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  void _changeRange(DateRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _detail = null;
    });
    _load();
  }

  String get _title => widget.subcategory ?? widget.category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(
        children: <Widget>[
          PeriodSelector(range: _range, onChanged: _changeRange),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final CategoryDetail? detail = _detail;

    if (_isLoading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('불러오지 못했습니다: $_error'));
    }
    if (detail == null || detail.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('이 기간에는 결제 내역이 없습니다.'),
        ),
      );
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? rate = detail.changeRate;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.cardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: CategoryColors.ofContext(
                          context,
                          widget.category,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '총 소비',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  Formatters.signedWon(detail.total),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      '${detail.count}건',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (rate != null)
                      Text(
                        '${detail.range.previousLabel}보다 '
                        '${Formatters.changeLabel(rate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const _SectionTitle('소비 추이', subtitle: '최근 6개월'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(context),
            child: MonthlyTrendChart(trend: detail.monthlyTrend),
          ),

          // 세부 항목(서브카테고리) — 카테고리 전체를 볼 때만 의미가 있다.
          if (detail.subcategories.length > 1) ...<Widget>[
            const SizedBox(height: 24),
            const _SectionTitle('세부 항목'),
            const SizedBox(height: 12),
            AppTheme.cardSurface(
              context,
              child: Column(
                children: List<Widget>.generate(
                  detail.subcategories.length,
                  (int index) {
                    final CategoryAmount sub = detail.subcategories[index];
                    return Column(
                      children: <Widget>[
                        if (index > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(
                            sub.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: Text(
                            Formatters.won(sub.amount),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CategoryDetailScreen(
                                category: widget.category,
                                subcategory: sub.name,
                                initialRange: _range,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          _SectionTitle('브랜드', subtitle: '${detail.brands.length}개'),
          const SizedBox(height: 12),
          AppTheme.cardSurface(
            context,
            child: Column(
              children: List<Widget>.generate(detail.brands.length, (int i) {
                final BrandStat brand = detail.brands[i];
                return Column(
                  children: <Widget>[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
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
                        '${brand.count}회 · 평균 '
                        '${Formatters.won(brand.averageAmount)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        Formatters.won(brand.amount),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BrandDetailScreen(
                            brand: brand.brand,
                            initialRange: _range,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
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
    );
  }
}
