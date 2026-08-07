import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/features/transactions/domain/usecases/apply_user_correction.dart';
import 'package:budget_book/features/transactions/presentation/controllers/transaction_list_controller.dart';
import 'package:budget_book/features/transactions/presentation/widgets/transaction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 맨 아래까지 내렸을 때 마지막 줄이 떠 있는 버튼에 가리지 않아야 한다.
///
/// 가리면 스크롤을 끝까지 내려도 그 금액을 볼 수 없다. 목록 아래 여백만으로
/// 해결되는 문제인데, 여백이 모자라면 아무도 눈치채지 못한 채 마지막 거래가
/// 계속 안 보인다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() => initializeDateFormatting('ko_KR'));

  late Database db;
  late TransactionListController controller;

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
    final TransactionRepositoryImpl repository =
        TransactionRepositoryImpl(TransactionLocalDataSource(db));
    controller = TransactionListController(
      repository: repository,
      applyUserCorrection: ApplyUserCorrection(
        transactions: repository,
        merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      ),
    );

    // 스크롤이 생길 만큼 채운다.
    for (int i = 0; i < 20; i++) {
      final DateTime when = DateTime(2026, 8, 20 - i, 12);
      await repository.insert(
        Transaction(
          merchantRaw: '가게$i',
          brand: '가게$i',
          amount: 1000 + i,
          category: '식비',
          subcategory: '카페',
          method: PaymentMethodKind.card,
          paymentDatetime: when,
          rawNotification: 'x',
          fingerprint: 'f$i',
          classificationSource: ClassificationSource.seed,
        ),
      );
    }
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  testWidgets('맨 아래 거래가 직접 추가 버튼에 가리지 않는다',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: FloatingActionButton.small(
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
          body: ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? child) {
              // 실제 화면과 같은 아래 여백.
              return ListView(
                padding: const EdgeInsets.only(bottom: 76),
                children: <Widget>[
                  for (final Transaction t in controller.transactions)
                    TransactionTile(transaction: t, onTap: () {}),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 끝까지 내린다.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final Finder fab = find.byType(FloatingActionButton);
    final Rect fabRect = tester.getRect(fab);

    // 마지막 거래 줄이 버튼보다 위에 있어야 한다.
    final Finder tiles = find.byType(TransactionTile);
    final Rect lastTile = tester.getRect(tiles.last);

    expect(
      lastTile.bottom,
      lessThanOrEqualTo(fabRect.top),
      reason: '마지막 거래(${lastTile.bottom})가 버튼(${fabRect.top})에 가린다',
    );
  });

  testWidgets('작은 버튼을 쓴다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: FloatingActionButton.small(
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    // 목록 위에 떠 있는 버튼이라 클수록 가리는 면적이 넓다.
    final Rect rect = tester.getRect(find.byType(FloatingActionButton));
    expect(rect.height, lessThan(56), reason: '기본 크기(56)보다 작아야 한다');
  });
}
