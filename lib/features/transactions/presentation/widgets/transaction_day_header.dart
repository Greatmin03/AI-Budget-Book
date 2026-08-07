import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';

/// 거래 목록의 날짜 구분 바 겸 **하루 요약**.
///
/// 그날 들어온 돈과 나간 돈을 **부호와 색으로 나눠** 보여 주고,
/// 누르면 그날의 거래가 펼쳐진다.
///
/// 하루 요약을 먼저 보여 주는 이유: 한 달치 거래를 한 줄씩 늘어놓으면
/// 스크롤만 길어지고 "이 날 얼마 썼나" 에 답하기 어렵다. 요약을 먼저 보고
/// 궁금한 날만 펼치는 편이 빠르다.
class TransactionDayHeader extends StatelessWidget {
  const TransactionDayHeader({
    required this.day,
    required this.items,
    this.expanded = false,
    this.onToggle,
    super.key,
  });

  final DateTime day;
  final List<Transaction> items;

  /// 이 날의 거래가 펼쳐져 있는가.
  final bool expanded;

  /// null 이면 접었다 폈다 할 수 없는(항상 펼친) 목록이다.
  final VoidCallback? onToggle;

  /// 그날 나간 돈. 수입은 섞지 않는다.
  int get _outflow => items
      .where((Transaction t) => !t.isIncome)
      .fold<int>(0, (int sum, Transaction t) => sum + t.amount);

  /// 그날 들어온 돈.
  int get _inflow => items
      .where((Transaction t) => t.isIncome)
      .fold<int>(0, (int sum, Transaction t) => sum + t.amount);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget content = _buildContent(context, scheme);

    if (onToggle == null) return content;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(onTap: onToggle, child: content),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      // Material 이 감싸면 색을 두 번 칠하지 않는다.
      color: onToggle == null ? scheme.surfaceContainerHighest : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (onToggle != null) ...<Widget>[
                // 펼침 상태를 방향으로 알린다.
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
              ],
              Text(
                Formatters.monthDay(day),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // 수입이 있는 날은 두 값을 나눠 적는다. 하나로 더하면
          // "들어온 돈 + 나간 돈" 이라는 뜻 없는 숫자가 된다.
          //
          // 부호를 반드시 붙인다. 지출도 양수로 저장되므로 부호가 없으면
          // `+300,000원  15,000원` 처럼 어느 쪽이 나간 돈인지 알 수 없다.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_outflow != 0 || _inflow == 0)
                _FlowAmount(
                  label: '지출',
                  amount: _outflow,
                  isIncome: false,
                  // 지출만 있는 날은 색을 쓰지 않는다. 대부분의 날이
                  // 그렇기 때문에 온통 빨간 화면이 된다.
                  color: _inflow == 0
                      ? scheme.onSurfaceVariant
                      : FlowColors.expense(context),
                ),
              if (_inflow != 0 && _outflow != 0) const SizedBox(width: 12),
              if (_inflow != 0)
                _FlowAmount(
                  label: '수입',
                  amount: _inflow,
                  isIncome: true,
                  color: FlowColors.income(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 하루 요약의 금액 한 칸. `지출 -42,000원`
///
/// 라벨을 붙이는 이유: 부호와 색만으로는 처음 보는 사람이 어느 쪽이
/// 나간 돈인지 바로 알기 어렵다.
class _FlowAmount extends StatelessWidget {
  const _FlowAmount({
    required this.label,
    required this.amount,
    required this.isIncome,
    required this.color,
  });

  final String label;
  final int amount;
  final bool isIncome;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          Formatters.flowAmount(amount, isIncome: isIncome),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
