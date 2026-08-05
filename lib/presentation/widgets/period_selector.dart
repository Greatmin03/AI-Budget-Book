import 'package:flutter/material.dart';

import '../../core/utils/date_range.dart';

/// 기간 필터 UI.
///
/// 위: 오늘 / 이번 주 / 이번 달 / 올해 / 기간 지정 칩
/// 아래: 현재 구간 표시 + 이전/다음 이동
///
/// 요구사항 7("모든 통계는 이 기간 기준으로 조회")을 만족시키기 위해
/// 대시보드·통계·검색·상세 화면이 모두 이 위젯을 공유한다.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    required this.range,
    required this.onChanged,
    this.showNavigation = true,
    this.trailing,
    super.key,
  });

  final DateRange range;
  final ValueChanged<DateRange> onChanged;

  /// 이전/다음 구간 이동 화살표를 보여줄지.
  final bool showNavigation;

  final Widget? trailing;

  Future<void> _pickCustomRange(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime firstAllowed = DateTime(now.year - 5);
    final DateTime lastAllowed = DateTime(now.year, now.month, now.day);

    // 초기값은 반드시 [firstAllowed, lastAllowed] 안에 있어야 한다.
    // 진행 중인 달의 lastDay 는 미래이므로(8월 4일에 8월 31일) 그대로 넘기면
    // showDateRangePicker 가 assert 로 죽는다.
    final DateTime initialEnd =
        range.lastDay.isAfter(lastAllowed) ? lastAllowed : range.lastDay;
    DateTime initialStart =
        range.start.isBefore(firstAllowed) ? firstAllowed : range.start;
    if (initialStart.isAfter(initialEnd)) initialStart = initialEnd;

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstAllowed,
      lastDate: lastAllowed,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: '기간 선택',
      saveText: '적용',
    );
    if (picked == null) return;
    onChanged(DateRange.custom(picked.start, picked.end));
  }

  void _select(BuildContext context, PeriodType type) {
    switch (type) {
      case PeriodType.today:
        onChanged(DateRange.today());
      case PeriodType.week:
        onChanged(DateRange.week());
      case PeriodType.month:
        onChanged(DateRange.month());
      case PeriodType.year:
        onChanged(DateRange.year());
      case PeriodType.custom:
        _pickCustomRange(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: PeriodType.values.map((PeriodType type) {
              final bool selected = range.type == type;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(type.chipLabel),
                  selected: selected,
                  onSelected: (_) => _select(context, type),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
          child: Row(
            children: <Widget>[
              if (showNavigation)
                IconButton(
                  onPressed: () => onChanged(range.previous()),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '이전 기간',
                )
              else
                const SizedBox(width: 12),
              Flexible(
                child: Text(
                  range.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showNavigation)
                IconButton(
                  onPressed:
                      range.canGoNext ? () => onChanged(range.next()) : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '다음 기간',
                ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}
