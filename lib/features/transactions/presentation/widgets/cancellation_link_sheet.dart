import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';

/// 취소가 되돌린 원결제를 **사용자가 고른다.**
///
/// 후보가 여럿이면 앱이 고르지 않는다. 틀리게 이으면 엉뚱한 결제가 통계에서
/// 조용히 사라지고, 사용자는 알아챌 방법이 없다.
class CancellationLinkSheet extends StatelessWidget {
  const CancellationLinkSheet({
    required this.cancellation,
    required this.candidates,
    super.key,
  });

  final Transaction cancellation;
  final List<Transaction> candidates;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              '${Formatters.won(cancellation.amount.abs())} 취소',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              candidates.isEmpty
                  ? '같은 카드로 같은 금액을 결제한 기록이 없습니다.'
                  : '어느 결제를 취소한 것인가요?',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '취소 알림에는 가맹점 이름이 없어서 금액과 카드로만 찾습니다.\n'
                '기간을 벗어난 결제이거나 알림을 수집하기 전의 결제일 수 있습니다.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: candidates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final Transaction tx = candidates[index];
                  final Duration gap = cancellation.paymentDatetime
                      .difference(tx.paymentDatetime);

                  return ListTile(
                    title: Text(
                      tx.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${Formatters.monthDay(tx.paymentDatetime)} '
                      '${Formatters.time(tx.paymentDatetime)} · '
                      '${tx.category}/${tx.subcategory} · '
                      '${_gapLabel(gap)} 전',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      Formatters.won(tx.amount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(tx),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 취소가 결제보다 얼마나 뒤였는지. 가까울수록 그 결제일 가능성이 높다.
  static String _gapLabel(Duration gap) {
    if (gap.inMinutes < 60) return '${gap.inMinutes}분';
    if (gap.inHours < 24) return '${gap.inHours}시간';
    return '${gap.inDays}일';
  }
}
