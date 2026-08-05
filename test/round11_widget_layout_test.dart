import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/core/utils/month_range.dart';
import 'package:budget_book/features/dashboard/presentation/widgets/flow_summary_card.dart';
import 'package:budget_book/features/dashboard/presentation/widgets/top_row.dart';
import 'package:budget_book/features/recurring/domain/entities/recurring_rule.dart';
import 'package:budget_book/features/statistics/domain/entities/analytics.dart';
import 'package:budget_book/features/statistics/domain/entities/statistics.dart';
import 'package:budget_book/features/statistics/presentation/widgets/flow_breakdown_card.dart';
import 'package:budget_book/features/statistics/presentation/widgets/income_section.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Round 11 에서 추가한 위젯이 **실기기 레이아웃에서 터지지 않는지** 확인한다.
///
/// 세로 스크롤(ListView) 안에서는 높이가 무한이다. 그 안에 높이를 스스로
/// 정하지 못하는 위젯을 넣으면 `BoxConstraints forces an infinite height` 로
/// 화면이 깨진다. 단위 테스트로는 안 잡히고 기기에서만 나타난다.
void main() {
  // 앱과 같은 로케일 설정. main.dart 가 하는 일을 테스트에서도 해 준다.
  setUpAll(() {
    initializeDateFormatting('ko_KR');
    Intl.defaultLocale = 'ko_KR';
  });

  /// 실제 화면과 같은 조건: 폭은 정해져 있고 높이는 무한(스크롤).
  Future<void> pumpInScrollable(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[child],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final DateRange range = DateRange.month(DateTime(2026, 8, 15));

  DashboardSummary summary({
    int total = 15000,
    int income = 300000,
    int assetTransfer = 0,
  }) {
    return DashboardSummary(
      range: range,
      total: total,
      grossTotal: total,
      cashOutflow: total + assetTransfer,
      assetTransferTotal: assetTransfer,
      incomeTotal: income,
      incomeCount: income == 0 ? 0 : 1,
      previousTotal: 10000,
      transactionCount: 1,
      dailyAverage: 1000,
      topCategory: null,
      topVisitedBrand: null,
      highlights: const <SubcategoryHighlight>[],
      needsReviewCount: 0,
      pendingDepositCount: 0,
      upcomingRecurring: const <RecurringRule>[],
      recentTransactions: const <Transaction>[],
    );
  }

  group('FlowSummaryCard', () {
    testWidgets('스크롤 안에서 정상 배치된다', (WidgetTester tester) async {
      await pumpInScrollable(tester, FlowSummaryCard(summary: summary()));

      expect(tester.takeException(), isNull);
      expect(find.text('수입'), findsOneWidget);
      expect(find.text('지출'), findsOneWidget);
      expect(find.text('순증가'), findsOneWidget);
      expect(find.text('+285,000원'), findsOneWidget);
    });

    testWidgets('자산 이동·정산 안내가 있어도 터지지 않는다',
        (WidgetTester tester) async {
      await pumpInScrollable(
        tester,
        FlowSummaryCard(summary: summary(assetTransfer: 500000)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('수입이 0이어도 축이 깨지지 않는다', (WidgetTester tester) async {
      await pumpInScrollable(
        tester,
        FlowSummaryCard(summary: summary(income: 0, total: 0)),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FlowBreakdownCard', () {
    testWidgets('네 갈래 모두 있을 때', (WidgetTester tester) async {
      await pumpInScrollable(
        tester,
        const FlowBreakdownCard(
          flow: FlowBreakdown(
            spending: 450000,
            saving: 700000,
            housing: 100000,
            investment: 300000,
            otherAssetTransfer: 0,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('소비'), findsOneWidget);
      expect(find.text('저축'), findsOneWidget);
      expect(find.text('청약'), findsOneWidget);
      expect(find.text('투자'), findsOneWidget);
    });

    testWidgets('소비만 있을 때', (WidgetTester tester) async {
      await pumpInScrollable(
        tester,
        const FlowBreakdownCard(flow: FlowBreakdown.empty()),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('IncomeSection', () {
    IncomeStatistics income({bool withTrend = true}) {
      return IncomeStatistics(
        total: 2400000,
        previousTotal: 2000000,
        count: 3,
        byCategory: const <CategoryAmount>[
          CategoryAmount(name: '급여', amount: 2000000, count: 1),
          CategoryAmount(name: '장학금', amount: 300000, count: 1),
          CategoryAmount(name: '용돈', amount: 100000, count: 1),
        ],
        trend: withTrend
            ? <MonthlyTotal>[
                for (int m = 3; m <= 8; m++)
                  MonthlyTotal(
                    month: MonthRange.of(DateTime(2026, m)),
                    amount: m == 5 ? 0 : 2000000,
                  ),
              ]
            : const <MonthlyTotal>[],
      );
    }

    testWidgets('카테고리 + 월별 추이가 스크롤 안에서 배치된다',
        (WidgetTester tester) async {
      await pumpInScrollable(tester, IncomeSection(income: income()));

      expect(tester.takeException(), isNull);
      expect(find.text('총 수입'), findsOneWidget);
      expect(find.text('월별 수입 추이'), findsOneWidget);
    });

    testWidgets('추이가 없어도 터지지 않는다', (WidgetTester tester) async {
      await pumpInScrollable(
        tester,
        IncomeSection(income: income(withTrend: false)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('빈 수입 통계', (WidgetTester tester) async {
      await pumpInScrollable(
        tester,
        const IncomeSection(income: IncomeStatistics.empty()),
      );
      expect(tester.takeException(), isNull);
    });
  });
  group('TopRow (대시보드 상위 카드)', () {
    testWidgets('스크롤 안에서 무한 높이로 터지지 않는다',
        (WidgetTester tester) async {
      // 실기기에서 `BoxConstraints forces an infinite height` 로 대시보드가
      // 깨졌던 위젯이다. `Row + CrossAxisAlignment.stretch` 가 non-flex 자식
      // (가운데 SizedBox)에게 tight 무한 높이를 넘긴 것이 원인이었다.
      //
      // 단위 테스트로는 안 잡히고 기기에서만 나타나므로, 스크롤 안에 넣는
      // 이 테스트로 고정한다.
      await pumpInScrollable(tester, TopRow(summary: summary()));

      expect(tester.takeException(), isNull);
      expect(find.text('가장 많이 소비한 카테고리'), findsOneWidget);
      expect(find.text('가장 많이 방문한 브랜드'), findsOneWidget);
    });

    testWidgets('두 카드 높이가 서로 같다', (WidgetTester tester) async {
      // IntrinsicHeight 로 바꾼 목적이 높이 정렬이므로 그것까지 확인한다.
      await pumpInScrollable(tester, TopRow(summary: summary()));

      final Iterable<RenderBox> cards = tester
          .widgetList(find.byType(InkWell))
          .map((Widget w) => tester.renderObject<RenderBox>(find.byWidget(w)));
      if (cards.length >= 2) {
        expect(cards.first.size.height, cards.last.size.height);
      }
    });
  });
}
