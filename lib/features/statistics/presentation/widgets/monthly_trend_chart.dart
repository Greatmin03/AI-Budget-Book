import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/statistics.dart';

/// 월별 소비 추이 막대 차트.
///
/// 설계 규칙
///  - 단일 측정값이므로 축은 하나다(이중 축을 쓰지 않는다).
///  - 모든 막대에 숫자를 찍지 않는다. 최대값과 현재 달만 직접 라벨링한다.
///  - 막대를 탭하면 해당 월의 값이 표시된다(모바일에서의 hover 대체).
///  - 막대 끝은 4px 라운드, 기준선(0)에 붙어 있다.
class MonthlyTrendChart extends StatefulWidget {
  const MonthlyTrendChart({required this.trend, super.key});

  final List<MonthlyTotal> trend;

  @override
  State<MonthlyTrendChart> createState() => _MonthlyTrendChartState();
}

class _MonthlyTrendChartState extends State<MonthlyTrendChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<MonthlyTotal> trend = widget.trend;

    if (trend.isEmpty) return const SizedBox.shrink();

    final int maxAmount = trend
        .map((MonthlyTotal e) => e.amount)
        .fold<int>(0, (int a, int b) => math.max(a, b));
    final int maxIndex =
        trend.indexWhere((MonthlyTotal e) => e.amount == maxAmount);

    final int? selected = _selectedIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 선택된 막대의 값을 상단에 보여준다(툴팁 대체).
        SizedBox(
          height: 20,
          child: selected == null
              ? Text(
                  '막대를 탭하면 금액이 표시됩니다',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                )
              : Text(
                  '${Formatters.yearMonth(trend[selected].month.start)}  '
                  '${Formatters.signedWon(trend[selected].amount)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(trend.length, (int index) {
              final MonthlyTotal item = trend[index];
              final bool isCurrent = index == trend.length - 1;
              final bool isSelected = index == selected;
              final double ratio =
                  maxAmount <= 0 ? 0 : item.amount.clamp(0, maxAmount) / maxAmount;

              // 라벨은 최대값과 이번 달에만 붙인다.
              final bool showLabel =
                  (index == maxIndex || isCurrent) && item.amount > 0;

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(
                    () => _selectedIndex = isSelected ? null : index,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        // 라벨 슬롯은 모든 막대가 동일하게 차지한다.
                        // (일부 열에만 라벨을 두면 막대에 남는 높이가 달라져
                        //  같은 금액이 다른 높이로 그려진다)
                        SizedBox(
                          height: 16,
                          child: showLabel
                              ? Text(
                                  Formatters.compactWon(item.amount),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        // 막대 본체
                        Expanded(
                          child: LayoutBuilder(
                            builder: (BuildContext context,
                                BoxConstraints constraints) {
                              // 값이 0에 가까워도 최소 3px 은 보이게 한다.
                              final double height =
                                  math.max(constraints.maxHeight * ratio, 3.0);
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: isCurrent || isSelected
                                        ? scheme.primary
                                        : scheme.primary.withValues(alpha: 0.35),
                                    // 데이터 끝만 라운드. 기준선 쪽은 각지게.
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Formatters.monthShort(item.month.start),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w400,
                            color: isCurrent
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // 기준선(0)
        Container(height: 1, color: scheme.outlineVariant),
      ],
    );
  }

}
