import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';

/// 거래 목록의 날짜 구분 바.
///
/// 그날 들어온 돈과 나간 돈을 **부호와 색으로 나눠** 보여 준다.
class TransactionDayHeader extends StatelessWidget {
  const TransactionDayHeader({
    required this.day,
    required this.items,
    super.key,
  });

  final DateTime day;
  final List<Transaction> items;

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
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            Formatters.monthDay(day),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          // 수입이 있는 날은 두 값을 나눠 적는다. 하나로 더하면
          // "들어온 돈 + 나간 돈" 이라는 뜻 없는 숫자가 된다.
          //
          // 부호를 반드시 붙인다. 지출도 양수로 저장되므로 부호가 없으면
          // `+300,000원  15,000원` 처럼 어느 쪽이 나간 돈인지 알 수 없다.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_inflow != 0)
                Text(
                  '+${Formatters.won(_inflow)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FlowColors.income(context),
                  ),
                ),
              if (_inflow != 0 && _outflow != 0)
                Text(
                  '   ',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              if (_outflow != 0 || _inflow == 0)
                Text(
                  // 나간 돈은 `-` 를 붙인다. 다만 취소로 상쇄되어 0이 된 날은
                  // `-0원` 이 아니라 `0원` 이라야 읽힌다. 취소가 결제보다 큰
                  // 날은 실제로 돌려받은 것이므로 `+` 가 맞다.
                  _outflow == 0
                      ? Formatters.won(0)
                      : _outflow > 0
                          ? '-${Formatters.won(_outflow)}'
                          : '+${Formatters.won(-_outflow)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _inflow == 0
                        ? scheme.onSurfaceVariant
                        : FlowColors.expense(context),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
