import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/statistics.dart';

/// 카테고리 -> 서브카테고리 트리.
///
/// 요구사항 1의 표시 형태를 그대로 구현한다.
/// ```
/// 식비                    234,400원
///  ├─ 카페                 85,400원
///  ├─ 배달                 96,000원
///  └─ 외식                 53,000원
/// ```
/// 카테고리 이름을 누르면 상세 화면으로, 세부 항목을 누르면 그 항목으로 좁혀
/// 들어간다.
class CategoryTreeView extends StatelessWidget {
  const CategoryTreeView({
    required this.nodes,
    required this.total,
    required this.onCategoryTap,
    required this.onSubcategoryTap,
    super.key,
  });

  final List<CategoryNode> nodes;
  final int total;
  final void Function(String category) onCategoryTap;
  final void Function(String category, String subcategory) onSubcategoryTap;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Text('데이터가 없습니다.', style: TextStyle(fontSize: 13));
    }

    return Column(
      children: List<Widget>.generate(nodes.length, (int index) {
        final CategoryNode node = nodes[index];
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 14),
          child: _CategoryBlock(
            node: node,
            total: total,
            onCategoryTap: onCategoryTap,
            onSubcategoryTap: onSubcategoryTap,
          ),
        );
      }),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.node,
    required this.total,
    required this.onCategoryTap,
    required this.onSubcategoryTap,
  });

  final CategoryNode node;
  final int total;
  final void Function(String category) onCategoryTap;
  final void Function(String category, String subcategory) onSubcategoryTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = CategoryColors.ofContext(context, node.category);
    final double ratio = node.ratioOf(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ------------------------------------------------------- 카테고리 행
        InkWell(
          onTap: () => onCategoryTap(node.category),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.category,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${(ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  Formatters.won(node.amount),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: scheme.outline),
              ],
            ),
          ),
        ),

        // 비율 막대. 기준선에서 시작해 데이터 끝만 라운드 처리.
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(4),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ratio <= 0 ? 0.01 : ratio,
                child: Container(height: 4, color: color),
              ),
            ),
          ),
        ),

        // ----------------------------------------------------- 서브카테고리
        if (node.hasBreakdown)
          ...List<Widget>.generate(node.children.length, (int index) {
            final CategoryAmount child = node.children[index];
            final bool isLast = index == node.children.length - 1;
            return InkWell(
              onTap: () => onSubcategoryTap(node.category, child.name),
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3),
                child: Row(
                  children: <Widget>[
                    // 트리 가지 표시. 색이 아니라 모양으로 계층을 알린다.
                    SizedBox(
                      width: 22,
                      child: Text(
                        isLast ? '└' : '├',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        child.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${child.count}건',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      Formatters.won(child.amount),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
