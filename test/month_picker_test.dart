import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/presentation/widgets/month_picker_sheet.dart';
import 'package:budget_book/presentation/widgets/period_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 월 선택.
///
/// 화살표만 있으면 여섯 달 전으로 가는 데 여섯 번을 눌러야 한다.
/// "3월에 얼마 썼더라" 에 한 번에 답할 수 있어야 한다.
void main() {
  Future<DateTime?> pump(
    WidgetTester tester, {
    required DateTime selected,
    DateTime? lastMonth,
  }) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                picked = await showModalBottomSheet<DateTime>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MonthPickerSheet(
                    selected: selected,
                    lastMonth: lastMonth,
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return picked;
  }

  group('월 선택 시트', () {
    testWidgets('12개월이 모두 보인다', (WidgetTester tester) async {
      await pump(
        tester,
        selected: DateTime(2026, 8),
        lastMonth: DateTime(2026, 12),
      );

      for (int m = 1; m <= 12; m++) {
        expect(find.text('$m월'), findsOneWidget);
      }
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('달을 고르면 그 달 1일을 돌려준다', (WidgetTester tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<DateTime>(
                    context: context,
                    isScrollControlled: true,
                  builder: (_) => MonthPickerSheet(
                      selected: DateTime(2026, 8),
                      lastMonth: DateTime(2026, 12),
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('3월'));
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 3));
    });

    testWidgets('연도를 옮길 수 있다', (WidgetTester tester) async {
      await pump(
        tester,
        selected: DateTime(2026, 8),
        lastMonth: DateTime(2026, 12),
      );

      await tester.tap(find.byTooltip('이전 해'));
      await tester.pumpAndSettle();

      expect(find.text('2025'), findsOneWidget);
    });

    testWidgets('미래의 달은 고를 수 없다', (WidgetTester tester) async {
      final DateTime? picked = await pump(
        tester,
        selected: DateTime(2026, 8),
        lastMonth: DateTime(2026, 8),
      );

      // 눌러도 아무 일이 없어야 한다. 고를 수 있으면 항상 빈 화면이 나온다.
      await tester.tap(find.text('12월'));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      expect(find.text('12월'), findsOneWidget, reason: '시트가 닫히지 않았다');
    });

    testWidgets('마지막 달을 넘어서는 해로는 갈 수 없다',
        (WidgetTester tester) async {
      await pump(
        tester,
        selected: DateTime(2026, 8),
        lastMonth: DateTime(2026, 12),
      );

      final IconButton next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('다음 해'),
          matching: find.byType(IconButton),
        ).first,
      );
      expect(next.onPressed, isNull);
    });
  });

  group('기간 선택기', () {
    testWidgets('월 보기에서는 달력 버튼이 보인다', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeriodSelector(
              range: DateRange.month(DateTime(2026, 8)),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });

    testWidgets('주 보기에서는 달력 버튼이 없다', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeriodSelector(
              range: DateRange.week(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // 주 보기에서 달을 고르게 하면 누른 순간 보기가 바뀌어 당황스럽다.
      expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);
    });

    testWidgets('달을 고르면 그 달로 기간이 바뀐다', (WidgetTester tester) async {
      DateRange? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeriodSelector(
              range: DateRange.month(DateTime(2026, 8)),
              onChanged: (DateRange r) => changed = r,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3월'));
      await tester.pumpAndSettle();

      expect(changed, isNotNull);
      expect(changed!.start, DateTime(2026, 3));
      expect(changed!.type, PeriodType.month);
    });
  });

  group('좁은 화면에서도 날짜가 잘리지 않는다', () {
    /// 이 줄에서 가장 중요한 글자는 날짜다.
    ///
    /// 예전에는 `Flexible` + `Spacer` 가 남는 공간을 반씩 나눠 가져서
    /// `2026년 8월` 이 `2026년...` 으로 잘렸다.
    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeriodSelector(
              range: DateRange.month(DateTime(2026, 8)),
              onChanged: (_) {},
              trailing: const Text(
                '+782,222원',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('320px 에서도 온전히 보인다', (WidgetTester tester) async {
      await pumpAt(tester, 320);

      expect(tester.takeException(), isNull);

      final RenderParagraph label = tester.renderObject<RenderParagraph>(
        find.text('2026년 8월'),
      );
      // didExceedMaxLines 가 true 면 말줄임표가 붙었다는 뜻이다.
      expect(label.didExceedMaxLines, isFalse, reason: '날짜가 잘렸다');
    });

    testWidgets('넓은 화면에서도 마찬가지다', (WidgetTester tester) async {
      await pumpAt(tester, 600);

      final RenderParagraph label = tester.renderObject<RenderParagraph>(
        find.text('2026년 8월'),
      );
      expect(label.didExceedMaxLines, isFalse);
      expect(find.text('+782,222원'), findsOneWidget);
    });
  });
}
