import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/statistics.dart';

/// 소비 / 저축 / 청약 / 투자.
///
/// 적금·청약·투자는 **소비가 아니다.** 하나로 합치면
/// "이번 달 450,000원 썼다" 가 "1,550,000원 썼다" 로 보인다.
/// 통장에서 나간 것은 같지만 내 자산으로 남아 있기 때문이다.
class FlowBreakdownCard extends StatelessWidget {
  const FlowBreakdownCard({required this.flow, super.key});

  final FlowBreakdown flow;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final List<_Row> rows = <_Row>[
      _Row('소비', flow.spending, FlowColors.expense(context)),
      if (flow.saving != 0)
        _Row('저축', flow.saving, CategoryColors.ofContext(context, '금융')),
      if (flow.housing != 0)
        _Row('청약', flow.housing, CategoryColors.ofContext(context, '주거/통신')),
      if (flow.investment != 0)
        _Row('투자', flow.investment, CategoryColors.ofContext(context, '쇼핑')),
      if (flow.otherAssetTransfer != 0)
        _Row('기타 자산 이동', flow.otherAssetTransfer,
            FlowColors.assetTransfer(context)),
    ];

    final int axisMax = rows.fold<int>(
      1,
      (int max, _Row r) => r.amount.abs() > max ? r.amount.abs() : max,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 12),
            _FlowRow(row: rows[i], axisMax: axisMax),
          ],
          const SizedBox(height: 16),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '통장에서 나간 돈',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                Formatters.won(flow.totalOutflow),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (flow.hasAssetTransfers) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '이 중 ${Formatters.won(flow.keptAsAssets)}은 내 자산으로 남아 '
              '소비 통계에서 제외했습니다'
              '${flow.savingRate == null ? '' : ' (${flow.savingRate!.toStringAsFixed(0)}%)'}.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({required this.row, required this.axisMax});

  final _Row row;
  final int axisMax;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double ratio = (row.amount.abs() / axisMax).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 색 옆에 항상 이름을 붙인다(색만으로 구분하지 않는다).
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: row.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              row.label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              Formatters.won(row.amount),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
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
                    color: row.color,
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
