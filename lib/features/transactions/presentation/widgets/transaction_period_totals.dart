import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../controllers/transaction_list_controller.dart';

/// 기간 합계.
///
/// **수입과 지출을 절대 하나로 더하지 않는다.** 그냥 더하면 300,000원 입금과
/// 15,000원 결제가 315,000원이 되어 아무 뜻이 없는 숫자가 된다.
///
/// 수입이 있는 기간에는 **순증가만** 보여 준다. 지출/수입 각각의 금액은
/// 날짜 바에서 날짜별로 확인할 수 있고, 기간 전체 내역은 대시보드에 있다.
/// 좁은 헤더에 세 줄을 넣으면 오히려 읽기 어렵다.
class TransactionPeriodTotals extends StatelessWidget {
  const TransactionPeriodTotals({
    required this.controller,
    super.key,
  });

  final TransactionListController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // 지출만 있는 기간에는 지출 합계가 곧 알고 싶은 값이다(대부분의 경우).
    if (!controller.hasIncome) {
      return Text(
        Formatters.signedWon(controller.expenseTotal),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );
    }

    final int net = controller.netChange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '순',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 5),
        // 부호를 항상 붙인다(색만으로 증감을 표현하지 않는다).
        Text(
          Formatters.signedWonWithPlus(net),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: FlowColors.net(context, net),
          ),
        ),
      ],
    );
  }
}
