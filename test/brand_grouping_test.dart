import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/database/seed/brand_seed.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import 'package:budget_book/features/ingest/data/repositories/ingest_failure_repository_impl.dart';
import 'package:budget_book/features/ingest/domain/usecases/record_payment_notification.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/merchants/domain/services/brand_extractor.dart';
import 'package:budget_book/features/notifications/domain/entities/raw_notification.dart';
import 'package:budget_book/features/parsing/domain/services/payment_notification_parser.dart';
import 'package:budget_book/features/recurring/data/repositories/recurring_repository_impl.dart';
import 'package:budget_book/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:budget_book/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:budget_book/features/settlements/data/datasources/settlement_local_datasource.dart';
import 'package:budget_book/features/settlements/data/repositories/settlement_repository_impl.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/domain/usecases/add_manual_transaction.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 브랜드별 소비 통계가 **무엇으로 묶이는가**.
///
/// 집계는 `merchant_raw` 가 아니라 `transactions.brand` 로 GROUP BY 한다.
/// 그리고 `brand` 에는 [BrandExtractor] 가 뽑은 **대표 브랜드**가 들어간다.
///
/// 이 구분이 중요한 이유: 은행마다 같은 브랜드를 다르게 보낸다.
/// `merchant_raw` 로 묶으면 CU 하나가 지점 수만큼 쪼개져 "가장 많이 쓴 곳" 이
/// 의미를 잃는다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: DbSchema.databaseVersion,
      onCreate: (Database db, int version) async {
        for (final String statement in DbSchema.createStatements) {
          await db.execute(statement);
        }
        final Batch batch = db.batch();
        for (final Map<String, Object?> row in BrandSeed.rows) {
          batch.insert(
            DbSchema.tableBrandRules,
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      },
    );
  });

  tearDown(() async => db.close());

  Future<RecordPaymentNotification> buildIngest() async {
    final SettingsRepositoryImpl settings =
        SettingsRepositoryImpl(SettingsLocalDataSource(db));
    await settings.load();
    return RecordPaymentNotification(
      parser: PaymentNotificationParser(
        recognizeBrand: const BrandExtractor(BrandSeed.definitions).recognizes,
      ),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      transactions: TransactionRepositoryImpl(TransactionLocalDataSource(db)),
      failures: IngestFailureRepositoryImpl(IngestFailureLocalDataSource(db)),
      settings: settings,
      deposits: DepositRepositoryImpl(DepositLocalDataSource(db)),
      recurring: RecurringRepositoryImpl(db),
    );
  }

  RawNotification pay(String merchant, int minute) => RawNotification(
        packageName: 'com.kbcard.cxh.appcard',
        title: 'KB국민카드',
        text: 'KB국민카드 승인 홍*동 3000원 일시불 '
            '08/05 14:$minute $merchant',
        postedAt: DateTime(2026, 8, 5, 14, minute),
      );

  test('은행마다 다른 표기가 하나의 대표 브랜드로 묶인다', () async {
    final RecordPaymentNotification record = await buildIngest();

    // 같은 CU 를 은행이 보내는 세 가지 형식.
    for (final (int i, String form) in <String>[
      '씨유강원대제3학생',
      '씨유(CU) 춘천 백령점',
      'CU춘천애막골점',
    ].indexed) {
      await record(pay(form, 30 + i));
    }

    final StatisticsLocalDataSource statistics = StatisticsLocalDataSource(db);
    final List<Map<String, Object?>> top = await statistics.byBrand(
      DateRange.month(DateTime(2026, 8, 5)),
      10,
    );

    // 한 줄로 묶여야 한다. 세 줄이면 "가장 많이 쓴 곳" 이 의미를 잃는다.
    expect(top, hasLength(1));
    expect(top.first['brand'], 'CU');
    expect(top.first['cnt'], 3);
  });

  test('원본 거래명은 그대로 남는다', () async {
    final RecordPaymentNotification record = await buildIngest();
    await record(pay('씨유강원대제3학생', 30));

    final List<Map<String, Object?>> rows = await db.query(
      DbSchema.tableTransactions,
      columns: <String>[DbSchema.tBrand, DbSchema.tMerchantRaw],
    );

    // 집계는 대표 브랜드로, 근거는 원본으로. 원본을 덮어쓰면 되돌릴 수 없다.
    expect(rows.single[DbSchema.tBrand], 'CU');
    expect(rows.single[DbSchema.tMerchantRaw], '씨유강원대제3학생');
  });

  test('사전에 없는 브랜드는 지점별로 갈라진다(현재 한계)', () async {
    final RecordPaymentNotification record = await buildIngest();

    for (final (int i, String form) in <String>[
      '수제버거집춘천점',
      '수제버거집강남점',
    ].indexed) {
      await record(pay(form, 30 + i));
    }

    final StatisticsLocalDataSource statistics = StatisticsLocalDataSource(db);
    final List<Map<String, Object?>> top = await statistics.byBrand(
      DateRange.month(DateTime(2026, 8, 5)),
      10,
    );

    // 사전에 없으면 브랜드가 어디서 끝나고 지점이 어디서 시작하는지 알 수 없다.
    // 추측해서 자르면 서로 다른 브랜드가 합쳐진다. 지금은 갈라진 채 둔다.
    expect(top, hasLength(2), reason: '사전 미등록 브랜드의 알려진 한계');
  });

  test('직접 추가한 "씨유" 가 알림 거래의 CU 와 함께 묶인다', () async {
    final RecordPaymentNotification record = await buildIngest();
    await record(pay('씨유강원대제3학생', 30));

    // 사용자가 현금 결제를 직접 추가한다. 같은 편의점이다.
    final AddManualTransaction add = AddManualTransaction(
      TransactionRepositoryImpl(TransactionLocalDataSource(db)),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
    );
    await add(
      date: DateTime(2026, 8, 5, 15),
      amount: 2000,
      direction: TransactionDirection.expense,
      category: '생활',
      subcategory: '편의점',
      brand: '씨유',
    );

    final List<Map<String, Object?>> top = await StatisticsLocalDataSource(db)
        .byBrand(DateRange.month(DateTime(2026, 8, 5)), 10);

    // 사용자는 같은 가게라고 생각하고 입력했다. 두 줄로 갈라지면
    // "이번 달 CU 에서 얼마 썼나" 에 답할 수 없다.
    expect(top, hasLength(1));
    expect(top.first['brand'], 'CU');
    expect(top.first['cnt'], 2);
  });

  test('직접 추가해도 입력한 이름은 그대로 남는다', () async {
    final AddManualTransaction add = AddManualTransaction(
      TransactionRepositoryImpl(TransactionLocalDataSource(db)),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
    );
    await add(
      date: DateTime(2026, 8, 5, 15),
      amount: 2000,
      direction: TransactionDirection.expense,
      category: '생활',
      subcategory: '편의점',
      brand: '씨유',
    );

    final Map<String, Object?> row = (await db.query(
      DbSchema.tableTransactions,
      columns: <String>[DbSchema.tBrand, DbSchema.tMerchantRaw],
    ))
        .single;

    expect(row[DbSchema.tBrand], 'CU');
    // 사용자가 무엇을 입력했는지는 남아야 한다. 근거를 지우면 되돌릴 수 없다.
    expect(row[DbSchema.tMerchantRaw], '씨유');
  });

  test('사전에 없는 이름은 억지로 바꾸지 않는다', () async {
    final AddManualTransaction add = AddManualTransaction(
      TransactionRepositoryImpl(TransactionLocalDataSource(db)),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
    );
    await add(
      date: DateTime(2026, 8, 5, 15),
      amount: 9000,
      direction: TransactionDirection.expense,
      category: '식비',
      subcategory: '한식',
      brand: '학식',
    );

    final Map<String, Object?> row = (await db.query(
      DbSchema.tableTransactions,
      columns: <String>[DbSchema.tBrand],
    ))
        .single;

    expect(row[DbSchema.tBrand], '학식');
  });
}
