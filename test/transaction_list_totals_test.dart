import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/models/transaction_dto.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/features/transactions/domain/usecases/apply_user_correction.dart';
import 'package:budget_book/features/transactions/presentation/controllers/transaction_list_controller.dart';
import 'package:budget_book/features/transactions/presentation/widgets/transaction_day_header.dart';
import 'package:budget_book/features/transactions/presentation/widgets/transaction_period_totals.dart';
import 'package:budget_book/presentation/widgets/period_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 거래 목록 화면의 기간 합계 / 날짜별 소계를 검증한다.
///
/// 집계 SQL 은 고쳤는데 **화면이 Dart 에서 다시 더하는 경로**가 남아 있어서
/// 거래 페이지에는 여전히 수입 + 지출이 합산되어 보였다.
/// (수입도 양수로 저장되므로 그냥 `fold` 하면 더해진다)
void main() {
  setUpAll(() {
    initializeDateFormatting('ko_KR');
    Intl.defaultLocale = 'ko_KR';
  });

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionListController controller;

  final DateTime now = DateTime.now();
  late DateTime inRange;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: DbSchema.databaseVersion,
      onCreate: (Database db, int version) async {
        for (final String statement in DbSchema.createStatements) {
          await db.execute(statement);
        }
      },
    );

    inRange = DateTime(now.year, now.month, 1, 12);

    final TransactionRepositoryImpl repository =
        TransactionRepositoryImpl(TransactionLocalDataSource(db));
    controller = TransactionListController(
      repository: repository,
      applyUserCorrection: ApplyUserCorrection(
        merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
        transactions: repository,
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> insert({
    required int amount,
    TransactionDirection direction = TransactionDirection.expense,
    bool isAssetTransfer = false,
    DateTime? at,
    String brand = '테스트',
  }) async {
    final DateTime when = at ?? inRange;
    final Transaction tx = Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      category: direction.isIncome ? '급여' : '식비',
      subcategory: direction.isIncome ? '월급' : '카페',
      method: PaymentMethodKind.card,
      paymentDatetime: when,
      rawNotification: 'test',
      fingerprint: '$brand|$amount|$direction|$isAssetTransfer'
          '|${when.microsecondsSinceEpoch}',
      classificationSource: ClassificationSource.seed,
      direction: direction,
      isAssetTransfer: isAssetTransfer,
      assetKind: isAssetTransfer ? AssetKind.saving.code : null,
    );
    await db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  group('거래 목록 기간 합계', () {
    test('요구사항 예시: 수입 300,000 + 지출 15,000 이 합산되지 않는다', () async {
      await insert(amount: 300000, direction: TransactionDirection.income);
      await insert(amount: 15000);

      controller.changeRange(DateRange.month(now));
      await controller.load();

      expect(controller.expenseTotal, 15000);
      expect(controller.incomeTotal, 300000);
      expect(controller.netChange, 285000);
      expect(
        controller.expenseTotal + controller.incomeTotal,
        315000,
        reason: '두 값을 각각 들고 있어야 한다(합산해서 보여 주지 않는다)',
      );
    });

    test('수입이 없으면 수입 합계는 0이다', () async {
      await insert(amount: 15000);
      await controller.load();

      expect(controller.hasIncome, isFalse);
      expect(controller.incomeTotal, 0);
      expect(controller.expenseTotal, 15000);
    });

    test('자산 이동은 소비 합계에서 빠진다', () async {
      await insert(amount: 10000);
      await insert(amount: 500000, isAssetTransfer: true);
      await controller.load();

      expect(
        controller.expenseTotal,
        10000,
        reason: '통계 화면의 지출과 같은 기준이어야 한다',
      );
      expect(controller.assetTransferTotal, 500000);
      expect(controller.hasAssetTransfers, isTrue);
    });

    test('취소 거래는 소비 합계에서 차감된다', () async {
      await insert(amount: 30000);
      await insert(amount: -30000);
      await controller.load();

      expect(controller.expenseTotal, 0);
    });

    test('순증가는 수입 - 소비다', () async {
      await insert(amount: 2000000, direction: TransactionDirection.income);
      await insert(amount: 450000);
      await insert(amount: 700000, isAssetTransfer: true);
      await controller.load();

      expect(
        controller.netChange,
        1550000,
        reason: '적금 700,000은 내 자산으로 남으므로 순증가를 줄이지 않는다',
      );
    });

    test('수입만 있는 기간도 정상 계산된다', () async {
      await insert(amount: 500000, direction: TransactionDirection.income);
      await controller.load();

      expect(controller.expenseTotal, 0);
      expect(controller.incomeTotal, 500000);
      expect(controller.netChange, 500000);
    });
  });

  group('날짜별 소계', () {
    test('같은 날 수입과 지출이 섞여도 각각 분리된다', () async {
      final DateTime day = DateTime(now.year, now.month, 2, 10);
      await insert(amount: 300000, direction: TransactionDirection.income, at: day);
      await insert(amount: 15000, at: day);
      await controller.load();

      final List<Transaction> items =
          controller.groupedByDay.values.single;

      final int inflow = items
          .where((Transaction t) => t.isIncome)
          .fold<int>(0, (int s, Transaction t) => s + t.amount);
      final int outflow = items
          .where((Transaction t) => !t.isIncome)
          .fold<int>(0, (int s, Transaction t) => s + t.amount);

      expect(inflow, 300000);
      expect(outflow, 15000);
      expect(items.length, 2, reason: '두 건 모두 목록에는 보인다');
    });

    test('날짜별로 묶인다', () async {
      await insert(amount: 1000, at: DateTime(now.year, now.month, 2, 9));
      await insert(amount: 2000, at: DateTime(now.year, now.month, 3, 9));
      await controller.load();

      expect(controller.groupedByDay.keys.length, 2);
    });
  });
  group('화면 표시', () {
    /// 실제 화면을 띄워 헤더/날짜 바 문구를 확인한다.
    ///
    /// **DB 작업은 반드시 [WidgetTester.runAsync] 안에서 해야 한다.**
    /// `testWidgets` 는 FakeAsync 존에서 돌기 때문에 실제 SQLite I/O 를
    /// 그냥 await 하면 완료 통보가 오지 않아 테스트가 그대로 멈춘다.
    Future<void> pumpScreen(
      WidgetTester tester,
      Future<void> Function() setUpData,
    ) async {
      await tester.runAsync(() async {
        await setUpData();
        await controller.load();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (BuildContext context, Widget? child) {
                final Map<DateTime, List<Transaction>> grouped =
                    controller.groupedByDay;
                return Column(
                  children: <Widget>[
                    // 실제 화면과 같은 구성으로 헤더를 배치한다.
                    PeriodSelector(
                      range: controller.range,
                      onChanged: controller.changeRange,
                      trailing: TransactionPeriodTotals(controller: controller),
                    ),
                    Expanded(
                      child: ListView(
                        children: grouped.entries
                            .map(
                              (MapEntry<DateTime, List<Transaction>> e) =>
                                  TransactionDayHeader(
                                day: e.key,
                                items: e.value,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      // 문구만 확인하므로 몇 프레임이면 충분하다.
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('수입이 있으면 헤더에 순증가만 보인다', (WidgetTester tester) async {
      await pumpScreen(tester, () async {
        await insert(amount: 300000, direction: TransactionDirection.income);
        await insert(amount: 15000);
      });

      expect(tester.takeException(), isNull);
      expect(find.text('순'), findsOneWidget);
      expect(find.text('+285,000원'), findsOneWidget);
      // 색이 들어간 지출/수입 라벨은 **기간 합계 바에서** 없앴다.
      // (하루 요약에는 `지출 -15,000원` 처럼 라벨이 붙는다 — 다른 위젯이다)
      expect(
        find.descendant(
          of: find.byType(TransactionPeriodTotals),
          matching: find.text('지출'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(TransactionPeriodTotals),
          matching: find.text('수입'),
        ),
        findsNothing,
      );
    });

    testWidgets('지출만 있으면 헤더는 지출 합계 한 줄이다',
        (WidgetTester tester) async {
      await pumpScreen(tester, () async {
        await insert(amount: 15000);
      });

      expect(tester.takeException(), isNull);
      expect(find.text('순'), findsNothing);
      expect(find.text('15,000원'), findsOneWidget);
    });

    testWidgets('날짜 바가 수입과 지출을 부호로 나눠 보여 준다',
        (WidgetTester tester) async {
      final DateTime day = DateTime(now.year, now.month, 2, 10);
      await pumpScreen(tester, () async {
        await insert(
          amount: 300000,
          direction: TransactionDirection.income,
          at: day,
        );
        await insert(amount: 15000, at: day);
      });

      expect(tester.takeException(), isNull);
      expect(find.text('+300,000원'), findsOneWidget);
      expect(
        find.text('-15,000원'),
        findsOneWidget,
        reason: '지출도 양수로 저장되므로 부호를 직접 붙여야 구분된다',
      );
    });

    testWidgets('지출만 있는 날도 부호가 붙는다', (WidgetTester tester) async {
      await pumpScreen(tester, () async {
        await insert(amount: 15000, at: DateTime(now.year, now.month, 3, 10));
      });

      expect(tester.takeException(), isNull);
      expect(find.text('-15,000원'), findsOneWidget);
    });
  });
  group('지출 / 수입 그룹화', () {
    test('같은 날 안에서 지출 -> 수입 순으로 나뉜다', () async {
      final DateTime day = DateTime(now.year, now.month, 7, 10);
      await insert(amount: 4500, at: day, brand: '메가커피');
      await insert(
        amount: 300000,
        direction: TransactionDirection.income,
        at: day,
        brand: '장학금',
      );
      await insert(amount: 12000, at: day, brand: '행복반점');
      await controller.load();

      final DaySection section = controller.daySections.single;

      expect(section.expenses.map((Transaction t) => t.brand),
          containsAll(<String>['메가커피', '행복반점']));
      expect(section.incomes.single.brand, '장학금');
      // 화면에 그려지는 순서: 지출이 먼저다.
      expect(section.all.first.isIncome, isFalse);
      expect(section.all.last.isIncome, isTrue);
      expect(section.needsGroupLabels, isTrue);
    });

    test('지출만 있는 날은 구분 라벨을 붙이지 않는다', () async {
      await insert(amount: 4500, at: DateTime(now.year, now.month, 7, 10));
      await controller.load();

      final DaySection section = controller.daySections.single;
      expect(section.hasIncomes, isFalse);
      expect(
        section.needsGroupLabels,
        isFalse,
        reason: '거의 모든 날에 라벨이 붙으면 오히려 지저분하다',
      );
    });

    test('수입만 있는 날도 라벨을 붙이지 않는다', () async {
      await insert(
        amount: 300000,
        direction: TransactionDirection.income,
        at: DateTime(now.year, now.month, 7, 10),
      );
      await controller.load();

      final DaySection section = controller.daySections.single;
      expect(section.hasExpenses, isFalse);
      expect(section.needsGroupLabels, isFalse);
    });

    test('날짜는 내림차순으로 유지된다', () async {
      await insert(amount: 1000, at: DateTime(now.year, now.month, 5, 9));
      await insert(amount: 2000, at: DateTime(now.year, now.month, 7, 9));
      await insert(amount: 3000, at: DateTime(now.year, now.month, 6, 9));
      await controller.load();

      final List<int> days =
          controller.daySections.map((DaySection s) => s.day.day).toList();
      expect(days, <int>[7, 6, 5]);
    });

    test('자산 이동은 지출 쪽에 들어간다', () async {
      final DateTime day = DateTime(now.year, now.month, 7, 10);
      await insert(amount: 500000, isAssetTransfer: true, at: day);
      await controller.load();

      final DaySection section = controller.daySections.single;
      expect(section.expenses.length, 1);
      expect(section.incomes, isEmpty);
    });
  });
}
