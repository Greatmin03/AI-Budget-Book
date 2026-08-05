import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/statistics.dart';

/// 수입 통계: 카테고리별 + 월별 추이.
///
/// 지출 통계와 **완전히 분리된 화면 구역**이다. 같은 카드에 넣으면
/// 두 값이 하나로 읽힌다.
class IncomeSection extends StatelessWidget {
  const IncomeSection({required this.income, super.key});

  final IncomeStatistics income;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = FlowColors.income(context);

    final int axisMax = income.byCategory.fold<int>(
      1,
      (int max, CategoryAmount c) => c.amount.abs() > max ? c.amount.abs() : max,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '총 수입',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.won(income.total),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Text(
                '${income.count}건',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              if (income.changeRate != null) ...<Widget>[
                const SizedBox(width: 10),
                Icon(
                  income.changeRate! >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  '직전 기간보다 '
                  '${Formatters.changeLabel(income.changeRate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),

          // ------------------------------------------------------ 카테고리별
          if (income.byCategory.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: 14),
            for (int i = 0; i < income.byCategory.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 12),
              _IncomeRow(
                item: income.byCategory[i],
                axisMax: axisMax,
                color: color,
              ),
            ],
          ],

          // ---------------------------------------------------------- 추이
          if (income.trend.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: 14),
            Text(
              '월별 수입 추이',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _IncomeTrend(trend: income.trend, color: color),
          ],
        ],
      ),
    );
  }
}

class _IncomeRow extends StatelessWidget {
  const _IncomeRow({
    required this.item,
    required this.axisMax,
    required this.color,
  });

  final CategoryAmount item;
  final int axisMax;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double ratio =
        (item.amount.abs() / axisMax).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              item.name,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Text(
              '${item.count}건',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const Spacer(),
            Text(
              Formatters.won(item.amount),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 7,
                  width: constraints.maxWidth * ratio,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 월별 수입 막대.
///
/// 모든 막대가 같은 축을 쓴다. 막대마다 축이 다르면 길이 비교가 거짓말이 된다.
class _IncomeTrend extends StatelessWidget {
  const _IncomeTrend({required this.trend, required this.color});

  final List<MonthlyTotal> trend;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int axisMax = trend.fold<int>(
      1,
      (int max, MonthlyTotal m) => m.amount > max ? m.amount : max,
    );

    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: trend.map((MonthlyTotal month) {
          final double ratio = (month.amount / axisMax).clamp(0.0, 1.0).toDouble();
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  // 값 라벨 자리는 모든 막대에 동일하게 확보한다
                  // (일부에만 있으면 막대 높이가 서로 안 맞아 비교가 깨진다).
                  SizedBox(
                    height: 14,
                    child: month.amount == 0
                        ? null
                        : FittedBox(
                            child: Text(
                              Formatters.compactWon(month.amount),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: (70 * ratio).clamp(2.0, 70.0),
                    decoration: BoxDecoration(
                      color: month.amount == 0
                          ? scheme.surfaceContainerHighest
                          : color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    Formatters.monthShort(month.month.start),
                    style: TextStyle(fontSize: 10, color: scheme.outline),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
