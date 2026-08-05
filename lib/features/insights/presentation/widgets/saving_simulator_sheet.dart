import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/insight_facts.dart';

/// "만약 줄이면?" 시뮬레이터.
///
/// 슬라이더로 감축 횟수를 바꾸면 1개월/6개월/1년 절약액이 즉시 바뀐다.
/// **계산은 전부 앱이 한다.** (평균 금액 × 줄이는 횟수)
class SavingSimulatorSheet extends StatefulWidget {
  const SavingSimulatorSheet({
    required this.facts,
    required this.target,
    super.key,
  });

  final InsightFacts facts;
  final String target;

  @override
  State<SavingSimulatorSheet> createState() => _SavingSimulatorSheetState();
}

class _SavingSimulatorSheetState extends State<SavingSimulatorSheet> {
  late int _reduceBy;
  late final int _maxReduce;

  @override
  void initState() {
    super.initState();
    final SavingScenario? initial = widget.facts.simulateReduction(
      target: widget.target,
      reduceBy: 1,
    );
    _maxReduce = initial?.currentCount ?? 1;
    // 기본값은 전체의 3분의 1 정도(현실적인 목표).
    _reduceBy = (_maxReduce / 3).ceil().clamp(1, _maxReduce).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SavingScenario? scenario = widget.facts.simulateReduction(
      target: widget.target,
      reduceBy: _reduceBy,
    );

    if (scenario == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('이 항목의 이용 기록이 없습니다.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Text(
            widget.target,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.facts.range.label} ${scenario.currentCount}회 · '
            '${Formatters.won(scenario.currentAmount)} · '
            '1회 평균 ${Formatters.won(scenario.averageAmount)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          Text(
            '$_reduceBy회 줄이면',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${scenario.currentCount}회 → ${scenario.remainingCount}회',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),

          // 1 ~ 전체 횟수까지 조절.
          Slider(
            value: _reduceBy.toDouble(),
            min: 1,
            max: _maxReduce.toDouble(),
            divisions: _maxReduce > 1 ? _maxReduce - 1 : null,
            label: '$_reduceBy회',
            onChanged: (double value) =>
                setState(() => _reduceBy = value.round()),
          ),
          const SizedBox(height: 12),

          _SavingRow(label: '1개월', amount: scenario.savedPerMonth, emphasize: true),
          const SizedBox(height: 10),
          _SavingRow(label: '6개월', amount: scenario.savedPer6Months),
          const SizedBox(height: 10),
          _SavingRow(label: '1년', amount: scenario.savedPerYear),
          const SizedBox(height: 20),

          Text(
            '${widget.facts.range.label} 이용 패턴이 계속된다고 가정한 값입니다.',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingRow extends StatelessWidget {
  const _SavingRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final int amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          Formatters.won(amount),
          style: TextStyle(
            fontSize: emphasize ? 24 : 16,
            fontWeight: FontWeight.w700,
            color: emphasize ? scheme.primary : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '절약',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
