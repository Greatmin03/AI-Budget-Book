import 'package:flutter/material.dart';

/// 연도 이동 + 12개월 그리드.
///
/// 화살표만 있으면 여섯 달 전으로 가는 데 여섯 번을 눌러야 한다.
/// 달을 바로 고를 수 있어야 "3월에 얼마 썼더라" 에 답할 수 있다.
///
/// 고른 달의 1일을 돌려준다. 취소하면 null.
class MonthPickerSheet extends StatefulWidget {
  const MonthPickerSheet({
    required this.selected,
    this.firstYear,
    this.lastMonth,
    super.key,
  });

  /// 현재 보고 있는 달.
  final DateTime selected;

  /// 고를 수 있는 가장 이른 연도. 기본값은 5년 전.
  final int? firstYear;

  /// 고를 수 있는 마지막 달. 기본값은 이번 달.
  ///
  /// 미래의 달을 고를 수 있으면 항상 빈 화면이 나온다.
  final DateTime? lastMonth;

  @override
  State<MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<MonthPickerSheet> {
  late int _year = widget.selected.year;

  DateTime get _lastMonth {
    final DateTime last = widget.lastMonth ?? DateTime.now();
    return DateTime(last.year, last.month);
  }

  int get _firstYear => widget.firstYear ?? DateTime.now().year - 5;

  bool get _canGoPrevYear => _year > _firstYear;
  bool get _canGoNextYear => _year < _lastMonth.year;

  /// 아직 오지 않은 달인가.
  bool _isFuture(int month) => DateTime(_year, month).isAfter(_lastMonth);

  bool _isSelected(int month) =>
      _year == widget.selected.year && month == widget.selected.month;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      // 시트 높이가 모자라면 넘치는 대신 스크롤한다. 작은 화면에서도
      // 12개월이 다 잘려 보이면 안 된다.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 16),
            const Text(
              '월 선택',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            // 연도 이동
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  onPressed:
                      _canGoPrevYear ? () => setState(() => _year--) : null,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '이전 해',
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _canGoNextYear ? () => setState(() => _year++) : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '다음 해',
                ),
              ],
            ),
            const SizedBox(height: 8),

            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
              children: List<Widget>.generate(12, (int i) {
                final int month = i + 1;
                return _MonthCell(
                  month: month,
                  selected: _isSelected(month),
                  // 미래의 달은 고를 수 없다. 눌러도 빈 화면만 나온다.
                  enabled: !_isFuture(month),
                  onTap: () =>
                      Navigator.of(context).pop(DateTime(_year, month)),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.month,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int month;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Center(
          child: Text(
            '$month월',
            style: TextStyle(
              fontSize: 15,
              // 선택된 달은 굵기로도 구분한다. 색만으로 표시하지 않는다.
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: !enabled
                  ? scheme.outline
                  : selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
