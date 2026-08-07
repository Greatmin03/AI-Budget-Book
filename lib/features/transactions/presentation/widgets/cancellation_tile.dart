import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';

/// 취소 한 건과 그 원결제.
///
/// 취소 알림에는 가맹점 이름이 없다(`출금취소 3,400`). 그래서 목록만
/// 보아서는 무엇을 취소한 것인지 알 수 없다. **원결제를 함께 보여 주는
/// 것이 이 줄의 존재 이유다.**
class CancellationTile extends StatelessWidget {
  const CancellationTile({
    required this.cancellation,
    required this.original,
    required this.onLink,
    required this.onUnlink,
    super.key,
  });

  final Transaction cancellation;

  /// 이어진 원결제. null 이면 아직 못 찾았다.
  final Transaction? original;

  final VoidCallback onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Transaction? origin = original;

    return AppTheme.cardSurface(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    origin?.displayName ?? '원거래 미확인',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: origin == null ? scheme.error : null,
                    ),
                  ),
                ),
                Text(
                  Formatters.won(cancellation.amount.abs()),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (origin != null)
              _Line(
                label: '원거래',
                value: '${Formatters.monthDay(origin.paymentDatetime)} '
                    '${Formatters.time(origin.paymentDatetime)}',
              )
            else
              Text(
                '어느 결제를 취소한 것인지 찾지 못했습니다.\n'
                '연결하면 그 결제가 통계에서 빠집니다.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            _Line(
              label: '취소',
              value: '${Formatters.monthDay(cancellation.paymentDatetime)} '
                  '${Formatters.time(cancellation.paymentDatetime)}',
            ),
            if (cancellation.cardName != null)
              _Line(label: '카드', value: cancellation.cardName!),
            Align(
              alignment: Alignment.centerRight,
              child: origin == null
                  ? FilledButton.tonal(
                      onPressed: onLink,
                      child: const Text('연결'),
                    )
                  : TextButton(
                      onPressed: onUnlink,
                      child: const Text('연결 해제'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
