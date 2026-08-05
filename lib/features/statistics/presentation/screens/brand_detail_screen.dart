import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/analytics.dart';
import '../widgets/monthly_trend_chart.dart';

/// 브랜드 상세: 총 소비 / 방문 횟수 / 평균 / 결제 내역.
class BrandDetailScreen extends StatefulWidget {
  const BrandDetailScreen({
    required this.brand,
    required this.initialRange,
    super.key,
  });

  final String brand;
  final DateRange initialRange;

  @override
  State<BrandDetailScreen> createState() => _BrandDetailScreenState();
}

class _BrandDetailScreenState extends State<BrandDetailScreen> {
  late DateRange _range = widget.initialRange;
  BrandDetail? _detail;
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
      final BrandDetail detail = await Injector.instance.analytics
          .brandDetail(widget.brand, _range);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('브랜드 상세 조회 실패', e, stack);
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

  @override
  Widget build(BuildContext context) {
    final BrandDetail? detail = _detail;

    return Scaffold(
      appBar: AppBar(title: Text(widget.brand)),
      body: Column(
        children: <Widget>[
          PeriodSelector(range: _range, onChanged: _changeRange),
          Expanded(child: _buildBody(context, detail)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, BrandDetail? detail) {
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _SummaryCard(stat: detail.stat),
          const SizedBox(height: 24),
          const _SectionTitle('소비 추이', subtitle: '최근 6개월'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(context),
            child: MonthlyTrendChart(trend: detail.monthlyTrend),
          ),
          if (detail.branchBreakdown.length > 1) ...<Widget>[
            const SizedBox(height: 24),
            _SectionTitle('지점별', subtitle: '${detail.branchBreakdown.length}곳'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(context),
              child: Column(
                children: detail.branchBreakdown
                    .map((BranchAmount b) => _BranchRow(branch: b))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _SectionTitle('결제 내역', subtitle: '${detail.transactions.length}건'),
          const SizedBox(height: 12),
          Container(
            decoration: AppTheme.cardDecoration(context),
            child: Column(
              children: List<Widget>.generate(
                detail.transactions.length,
                (int index) => Column(
                  children: <Widget>[
                    if (index > 0) const Divider(height: 1),
                    _PaymentRow(transaction: detail.transactions[index]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stat});

  final BrandStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(caption: '총 소비', value: Formatters.signedWon(stat.amount)),
              ),
              Expanded(
                child: _Metric(caption: '총 방문', value: '${stat.count}회'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  caption: '평균 결제',
                  value: Formatters.won(stat.averageAmount),
                ),
              ),
              Expanded(
                child: _Metric(
                  caption: '최근 결제',
                  value: stat.lastPaidAt == null
                      ? '-'
                      : Formatters.yearMonthDay(stat.lastPaidAt!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.caption, required this.value});

  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.branch});

  final BranchAmount branch;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              branch.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '${branch.count}회',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Text(
            Formatters.won(branch.amount),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 요구사항 3의 결제 내역 한 줄: 날짜 / 금액 / 지점.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              '${transaction.paymentDatetime.month}/'
              '${transaction.paymentDatetime.day}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Formatters.signedWon(transaction.amount),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.merchantRaw,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            transaction.subcategory,
            style: TextStyle(fontSize: 11, color: scheme.outline),
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
