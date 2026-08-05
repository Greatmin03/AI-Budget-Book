import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/statistics.dart';

/// 카테고리 구성 도넛 차트 + 범례.
///
/// 설계 규칙
///  - 항목 수가 많아지면 상위 [maxSlices] 개만 색을 쓰고 나머지는 '기타'로 접는다.
///    (색을 무한정 늘리면 서로 구분이 안 된다)
///  - 색은 카테고리 이름에 고정된다. 금액 순위에 따라 색이 바뀌지 않는다.
///  - **범례가 항상 함께 표시된다.** 색만으로 항목을 구분하게 하지 않는다.
///  - 조각 사이에 2px 배경색 간격을 두어 경계를 분명히 한다.
class CategoryDonutChart extends StatelessWidget {
  const CategoryDonutChart({
    required this.items,
    required this.total,
    this.maxSlices = 7,
    super.key,
  });

  final List<CategoryAmount> items;
  final int total;
  final int maxSlices;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final List<_Slice> slices = _buildSlices(brightness);

    if (slices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: <Widget>[
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: const Size(190, 190),
                painter: _DonutPainter(
                  slices: slices,
                  gapColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              // 중앙의 헤드라인 숫자. 도넛의 구멍을 낭비하지 않는다.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '총 지출',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.signedWon(total),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 범례 = 표 역할도 겸한다(이름 + 금액 + 비율).
        ...slices.map((_Slice slice) => _LegendRow(slice: slice, total: total)),
      ],
    );
  }

  /// 음수(취소 위주) 카테고리는 원그래프에서 의미가 없으므로 제외하고,
  /// 상위 [maxSlices] 개 외에는 '기타'로 합친다.
  List<_Slice> _buildSlices(Brightness brightness) {
    final List<CategoryAmount> positive =
        items.where((CategoryAmount e) => e.amount > 0).toList()
          ..sort((CategoryAmount a, CategoryAmount b) =>
              b.amount.compareTo(a.amount));

    if (positive.isEmpty) return const <_Slice>[];

    final List<_Slice> slices = <_Slice>[];
    int foldedAmount = 0;
    int foldedCount = 0;

    for (int i = 0; i < positive.length; i++) {
      final CategoryAmount item = positive[i];
      // '기타'는 원래 항목이든 접힌 항목이든 항상 마지막 중립색으로 모은다.
      if (i >= maxSlices || item.name == '기타') {
        foldedAmount += item.amount;
        foldedCount += item.count;
        continue;
      }
      slices.add(
        _Slice(
          label: item.name,
          amount: item.amount,
          count: item.count,
          color: CategoryColors.of(item.name, brightness),
        ),
      );
    }

    if (foldedAmount > 0) {
      slices.add(
        _Slice(
          label: '기타',
          amount: foldedAmount,
          count: foldedCount,
          color: CategoryColors.of('기타', brightness),
        ),
      );
    }
    return slices;
  }
}

class _Slice {
  const _Slice({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
  });

  final String label;
  final int amount;
  final int count;
  final Color color;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.gapColor});

  final List<_Slice> slices;

  /// 조각 사이 간격에 칠할 색(= 차트 배경색).
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final int total =
        slices.fold<int>(0, (int sum, _Slice s) => sum + s.amount);
    if (total <= 0) return;

    const double strokeWidth = 26;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // 12시 방향에서 시계방향으로 그린다.
    double startAngle = -math.pi / 2;

    // 2px 배경 간격을 각도로 환산한다.
    final double gapAngle = slices.length > 1 ? 2 / radius : 0;

    for (final _Slice slice in slices) {
      final double sweep = slice.amount / total * 2 * math.pi;
      final double drawSweep = math.max(sweep - gapAngle, 0.004);

      final Paint paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle + gapAngle / 2, drawSweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.gapColor != gapColor;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.total});

  final _Slice slice;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double ratio = total == 0 ? 0 : slice.amount / total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: slice.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              slice.label,
              // 라벨은 텍스트 색을 쓴다. 항목 색은 옆의 마크가 담당한다.
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${(ratio * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Text(
            Formatters.won(slice.amount),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
