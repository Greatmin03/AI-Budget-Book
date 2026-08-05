import 'package:flutter/material.dart';

/// 같은 날짜 안에서 `지출` / `수입` 을 나누는 구분 라벨.
///
/// 글자와 얇은 선만 쓴다. 배경색이나 굵은 선을 쓰면 날짜 바(그 위의 회색 띠)와
/// 경쟁해서 어느 쪽이 상위 구분인지 알기 어려워진다.
class TransactionGroupLabel extends StatelessWidget {
  const TransactionGroupLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          // 라벨 오른쪽을 선으로 채운다. 색은 테마의 가장 연한 경계선을 쓴다
          // (다크 모드에서도 자동으로 알맞은 밝기가 된다).
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}
