import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/features/transactions/presentation/widgets/transaction_day_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 하루 요약 접기/펼치기.
///
/// 한 달치 거래를 한 줄씩 늘어놓으면 스크롤만 길어지고 "이 날 얼마 썼나" 에
/// 답하기 어렵다. 요약을 먼저 보고 궁금한 날만 펼치는 편이 빠르다.
void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  Transaction tx({
    required String brand,
    required int amount,
    bool income = false,
  }) {
    final DateTime when = DateTime(2026, 8, 10, 12, amount % 60);
    return Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      direction:
          income ? TransactionDirection.income : TransactionDirection.expense,
      category: income ? '급여' : '식비',
      subcategory: income ? '월급' : '카페',
      method: PaymentMethodKind.card,
      paymentDatetime: when,
      rawNotification: 'x',
      fingerprint: '$brand|$amount',
      classificationSource: ClassificationSource.seed,
    );
  }

  Future<void> pumpHeader(
    WidgetTester tester, {
    required List<Transaction> items,
    required bool expanded,
    VoidCallback? onToggle,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionDayHeader(
            day: DateTime(2026, 8, 10),
            items: items,
            expanded: expanded,
            onToggle: onToggle,
          ),
        ),
      ),
    );
  }

  group('하루 요약', () {
    testWidgets('지출과 수입에 라벨이 붙는다', (WidgetTester tester) async {
      await pumpHeader(
        tester,
        items: <Transaction>[
          tx(brand: 'CU', amount: 42000),
          tx(brand: '회사', amount: 300000, income: true),
        ],
        expanded: false,
        onToggle: () {},
      );

      // 부호와 색만으로는 어느 쪽이 나간 돈인지 바로 알기 어렵다.
      expect(find.text('지출'), findsOneWidget);
      expect(find.text('-42,000원'), findsOneWidget);
      expect(find.text('수입'), findsOneWidget);
      expect(find.text('+300,000원'), findsOneWidget);
    });

    testWidgets('지출만 있는 날은 수입 칸이 없다', (WidgetTester tester) async {
      await pumpHeader(
        tester,
        items: <Transaction>[tx(brand: 'CU', amount: 42000)],
        expanded: false,
        onToggle: () {},
      );

      expect(find.text('지출'), findsOneWidget);
      expect(find.text('수입'), findsNothing);
    });
  });

  group('접기/펼치기', () {
    testWidgets('접힌 상태와 펼친 상태의 아이콘이 다르다',
        (WidgetTester tester) async {
      await pumpHeader(
        tester,
        items: <Transaction>[tx(brand: 'CU', amount: 42000)],
        expanded: false,
        onToggle: () {},
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await pumpHeader(
        tester,
        items: <Transaction>[tx(brand: 'CU', amount: 42000)],
        expanded: true,
        onToggle: () {},
      );
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('누르면 토글이 불린다', (WidgetTester tester) async {
      int taps = 0;
      await pumpHeader(
        tester,
        items: <Transaction>[tx(brand: 'CU', amount: 42000)],
        expanded: false,
        onToggle: () => taps++,
      );

      await tester.tap(find.byType(TransactionDayHeader));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('토글이 없으면 화살표도 없다', (WidgetTester tester) async {
      // 다른 화면에서 항상 펼친 목록으로 쓸 수 있어야 한다.
      await pumpHeader(
        tester,
        items: <Transaction>[tx(brand: 'CU', amount: 42000)],
        expanded: false,
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.text('지출'), findsOneWidget, reason: '요약은 그대로 보인다');
    });
  });
}
