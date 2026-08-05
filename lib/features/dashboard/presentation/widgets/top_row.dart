import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../statistics/domain/entities/analytics.dart';
import '../../../statistics/domain/entities/statistics.dart';
import '../../../statistics/presentation/screens/brand_detail_screen.dart';
import '../../../statistics/presentation/screens/category_detail_screen.dart';

/// 가장 많이 소비한 카테고리 / 가장 많이 방문한 브랜드.
class TopRow extends StatelessWidget {
  const TopRow({required this.summary, super.key});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final CategoryAmount? topCategory = summary.topCategory;
    final BrandStat? topBrand = summary.topVisitedBrand;

    // `CrossAxisAlignment.stretch` 를 쓰면 안 된다.
    //
    // stretch 는 non-flex 자식(여기서는 가운데 SizedBox)에게 높이를 **tight** 로
    // 강제한다. 이 Row 는 세로 스크롤(ListView) 안에 있어 높이가 무한이므로
    // `h=Infinity` 가 넘어가고 "BoxConstraints forces an infinite height" 로
    // 화면이 깨진다.
    //
    // 두 카드의 높이를 맞추는 것이 목적이므로 `IntrinsicHeight` 를 쓴다.
    // 자식들이 자기 높이를 정한 뒤, 그중 큰 값으로 둘을 맞춘다.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _TopCard(
              caption: '가장 많이 소비한 카테고리',
              title: topCategory?.name ?? '-',
              detail: topCategory == null
                  ? null
                  : Formatters.won(topCategory.amount),
              icon: Icons.category_outlined,
              onTap: topCategory == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CategoryDetailScreen(
                            category: topCategory.name,
                            initialRange: summary.range,
                          ),
                        ),
                      ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TopCard(
              caption: '가장 많이 방문한 브랜드',
              title: topBrand?.brand ?? '-',
              detail: topBrand == null ? null : '${topBrand.count}회',
              icon: Icons.storefront_outlined,
              onTap: topBrand == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BrandDetailScreen(
                            brand: topBrand.brand,
                            initialRange: summary.range,
                          ),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.caption,
    required this.title,
    required this.icon,
    this.detail,
    this.onTap,
  });

  final String caption;
  final String title;
  final IconData icon;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    caption,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                detail!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
