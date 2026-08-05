import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/statistics.dart';

/// "이번 달 커피값", "이번 달 배달비" 같은 단일 지표 카드.
///
/// 차트가 아니라 **헤드라인 숫자**가 맞는 자리다.
/// 값 하나를 전달하는 데 원그래프를 쓰지 않는다.
class HighlightCards extends StatelessWidget {
  const HighlightCards({required this.highlights, super.key});

  final List<SubcategoryHighlight> highlights;

  @override
  Widget build(BuildContext context) {
    final List<SubcategoryHighlight> visible = highlights
        .where((SubcategoryHighlight e) => e.count > 0)
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Row(
      children: visible
          .map(
            (SubcategoryHighlight h) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _HighlightCard(highlight: h),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight});

  final SubcategoryHighlight highlight;

  /// 서브카테고리 -> 아이콘. 색만으로 구분하지 않기 위한 보조 인코딩.
  static const Map<String, IconData> _icons = <String, IconData>{
    '카페': Icons.local_cafe_outlined,
    '배달': Icons.delivery_dining_outlined,
    '편의점': Icons.storefront_outlined,
    '택시': Icons.local_taxi_outlined,
    '주유': Icons.local_gas_station_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? rate = highlight.changeRate;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _icons[highlight.subcategory] ?? Icons.paid_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                highlight.subcategory,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            Formatters.won(highlight.amount),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${highlight.count}회',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (rate != null) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(
                  rate >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  '지난달보다 ${Formatters.changeLabel(rate)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
