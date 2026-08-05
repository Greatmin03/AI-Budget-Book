import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../statistics/domain/entities/analytics.dart';

/// 수입 / 지출 / 순증가.
///
/// **세 값을 절대 하나로 합치지 않는다.** 수입 300,000원과 지출 15,000원을
/// 더해 315,000원으로 보여 주던 것이 이 카드가 생긴 이유다.
///
/// 막대는 두 값의 크기를 비교하는 용도이므로 같은 축(둘 중 큰 값)을 쓴다.
/// 축이 다르면 길이 비교가 거짓말이 된다.
class FlowSummaryCard extends StatelessWidget {
  const FlowSummaryCard({required this.summary, super.key});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int income = summary.incomeTotal;
    final int expense = summary.total;
    final int net = summary.netChange;

    // 두 막대가 공유하는 축. 0으로 나누지 않도록 최소 1을 둔다.
    final int axisMax = <int>[income.abs(), expense.abs(), 1].reduce(
      (int a, int b) => a > b ? a : b,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary.range.label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          _FlowBar(
            label: '수입',
            amount: income,
            axisMax: axisMax,
            color: FlowColors.income(context),
          ),
          const SizedBox(height: 12),
          _FlowBar(
            label: '지출',
            amount: expense,
            axisMax: axisMax,
            color: FlowColors.expense(context),
          ),
          const SizedBox(height: 16),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  '순증가',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              // 부호를 항상 붙인다. 색만으로 증감을 표현하지 않는다.
              Text(
                Formatters.signedWonWithPlus(net),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: FlowColors.net(context, net),
                ),
              ),
            ],
          ),
          if (summary.hasAssetTransfers) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '자산 이동 ${Formatters.won(summary.assetTransferTotal)}은 '
              '소비와 순증가에서 제외했습니다(내 계좌에 남아 있는 돈).',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          if (summary.hasSettlements) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '총 결제 ${Formatters.won(summary.grossTotal)} 중 '
              '${Formatters.won(summary.settledTotal)}을 정산받아 '
              '실제 부담만 지출로 계산했습니다.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 라벨 + 값 + 막대 한 줄.
class _FlowBar extends StatelessWidget {
  const _FlowBar({
    required this.label,
    required this.amount,
    required this.axisMax,
    required this.color,
  });

  final String label;
  final int amount;
  final int axisMax;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double ratio = (amount.abs() / axisMax).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 색 옆에 항상 이름이 붙는다(색만으로 구분하지 않는다).
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              Formatters.won(amount),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 트랙 위에 값 막대. 얇게, 데이터 끝만 둥글게.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
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
