import 'dart:io';

import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/database/seed/brand_seed.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import 'package:budget_book/features/ingest/data/repositories/ingest_failure_repository_impl.dart';
import 'package:budget_book/features/ingest/domain/entities/ingest_result.dart';
import 'package:budget_book/features/ingest/domain/usecases/record_payment_notification.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/notifications/domain/entities/raw_notification.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/parsing/domain/services/payment_notification_parser.dart';
import 'package:budget_book/features/recurring/data/repositories/recurring_repository_impl.dart';
import 'package:budget_book/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:budget_book/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:budget_book/features/settlements/data/datasources/settlement_local_datasource.dart';
import 'package:budget_book/features/settlements/data/repositories/settlement_repository_impl.dart';
import 'package:budget_book/features/settlements/domain/entities/deposit.dart';
import 'package:budget_book/features/settlements/domain/usecases/manage_settlements.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/legacy_schema.dart';

/// 입금 알림 -> 수입 통계.
///
/// 예전에는 입금을 `deposits` 에만 넣어서 **월급도 용돈도 수입 통계에 잡히지
/// 않았다.** 들어온 돈이 어디에도 보이지 않으면 가계부가 아니다.
///
/// 반대로 정산 입금까지 수입으로 세면 같은 돈을 두 번 센다. 그 결제의
/// 정산으로 이미 내 부담이 줄어 있기 때문이다. 두 요구를 동시에 만족해야 한다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
  late DepositRepositoryImpl deposits;
  late RecordPaymentNotification record;
  late LinkDepositToTransaction linkDeposit;

  final DateRange august = DateRange.month(DateTime(2026, 8, 5));

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: DbSchema.databaseVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
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

    final SettingsRepositoryImpl settings =
        SettingsRepositoryImpl(SettingsLocalDataSource(db));
    await settings.load();

    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
    deposits = DepositRepositoryImpl(DepositLocalDataSource(db));
    final SettlementRepositoryImpl settlementRepo =
        SettlementRepositoryImpl(SettlementLocalDataSource(db));

    record = RecordPaymentNotification(
      parser: const PaymentNotificationParser(),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      transactions: transactions,
      failures: IngestFailureRepositoryImpl(IngestFailureLocalDataSource(db)),
      settings: settings,
      deposits: deposits,
      recurring: RecurringRepositoryImpl(db),
    );

    linkDeposit = LinkDepositToTransaction(
      deposits: deposits,
      settlements: ManageSettlements(
        settlements: settlementRepo,
        transactions: transactions,
      ),
      transactions: transactions,
    );
  });

  tearDown(() async => db.close());

  /// 은행 입금 알림.
  RawNotification depositNotification({
    required String from,
    required int amount,
    int minute = 30,
  }) =>
      RawNotification(
        packageName: 'com.kbstar.kbbank',
        title: 'KB국민은행',
        text: '[KB]08/05 14:$minute $from 님이 $amount원을 입금했습니다. '
            '잔액 1,000,000원',
        postedAt: DateTime(2026, 8, 5, 14, minute),
      );

  Future<int> earnedIncome() =>
      StatisticsLocalDataSource(db).incomeTotalInRange(august);

  Future<List<Map<String, Object?>>> incomeByCategory() =>
      StatisticsLocalDataSource(db).incomeByCategory(august);

  group('입금이 수입으로 잡힌다', () {
    test('입금 알림이 수입 거래를 만든다', () async {
      final IngestResult result =
          await record(depositNotification(from: '회사', amount: 3000000));

      expect(result, isA<IngestDepositRecorded>());
      expect(await earnedIncome(), 3000000);
    });

    test('정산 후보 목록에도 그대로 남는다', () async {
      await record(depositNotification(from: '김철수', amount: 20000));

      // 수입으로 잡는다고 해서 정산 매칭을 포기하는 것이 아니다.
      expect(await deposits.countPending(), 1);
    });

    test('입금과 수입 거래가 서로 연결된다', () async {
      await record(depositNotification(from: '김철수', amount: 20000));

      final Deposit deposit = (await deposits.findPending()).single;

      expect(deposit.transactionId, isNotNull);
      final Transaction? income =
          await transactions.findById(deposit.transactionId!);
      expect(income, isNotNull);
      expect(income!.direction, TransactionDirection.income);
      expect(income.amount, 20000);
    });

    test('무엇으로 번 돈인지는 사용자가 고른다', () async {
      await record(depositNotification(from: '회사', amount: 3000000));

      final Deposit deposit = (await deposits.findPending()).single;
      final Transaction income =
          (await transactions.findById(deposit.transactionId!))!;

      // 보낸 사람 이름만으로는 월급인지 정산인지 알 수 없다. 추측해서
      // 굳혀 두면 통계가 조용히 어긋난다.
      expect(income.needsReview, isTrue);
      expect(income.category, CategoryTaxonomy.etcCategory);
    });

    test('같은 알림이 두 번 와도 한 번만 센다', () async {
      await record(depositNotification(from: '회사', amount: 3000000));
      final IngestResult second =
          await record(depositNotification(from: '회사', amount: 3000000));

      expect(second, isA<IngestDuplicate>());
      expect(await earnedIncome(), 3000000);
    });
  });

  group('정산은 소득이 아니다', () {
    /// 30,000원을 결제하고 친구에게 20,000원을 돌려받는 상황.
    Future<Transaction> insertPayment() async {
      final DateTime when = DateTime(2026, 8, 5, 12);
      return (await transactions.insert(
        Transaction(
          merchantRaw: '맥도날드',
          brand: '맥도날드',
          amount: 30000,
          category: '식비',
          subcategory: '패스트푸드',
          method: PaymentMethodKind.card,
          paymentDatetime: when,
          rawNotification: 'test',
          fingerprint: 'pay|${when.microsecondsSinceEpoch}',
          classificationSource: ClassificationSource.seed,
        ),
      ))!;
    }

    test('연결하면 수입 통계에서 빠진다', () async {
      final Transaction payment = await insertPayment();
      await record(depositNotification(from: '김철수', amount: 20000));
      final Deposit deposit = (await deposits.findPending()).single;

      expect(await earnedIncome(), 20000, reason: '연결 전에는 그냥 입금이다');

      await linkDeposit.link(deposit: deposit, transaction: payment);

      // 이미 결제 쪽에서 부담이 20,000원 줄었다. 수입으로도 세면 두 번 센다.
      expect(await earnedIncome(), 0);
    });

    test('연결해도 기록은 남는다', () async {
      final Transaction payment = await insertPayment();
      await record(depositNotification(from: '김철수', amount: 20000));
      final Deposit deposit = (await deposits.findPending()).single;

      await linkDeposit.link(deposit: deposit, transaction: payment);

      final Transaction income =
          (await transactions.findById(deposit.transactionId!))!;
      // "얼마가 들어왔나" 에는 여전히 답해야 한다. 지우지 않는다.
      expect(income.category, CategoryTaxonomy.settlementCategory);
      expect(income.amount, 20000);
      expect(income.needsReview, isFalse, reason: '분류가 정해졌으므로');
    });

    test('실제 소비는 내 부담만 잡힌다', () async {
      final Transaction payment = await insertPayment();
      await record(depositNotification(from: '김철수', amount: 20000));
      final Deposit deposit = (await deposits.findPending()).single;

      await linkDeposit.link(deposit: deposit, transaction: payment);

      final int spent = await StatisticsLocalDataSource(db)
          .totalInRange(august);
      expect(spent, 10000);
    });

    test('월급과 정산이 섞여도 월급만 수입으로 센다', () async {
      final Transaction payment = await insertPayment();
      await record(
        depositNotification(from: '회사', amount: 3000000, minute: 30),
      );
      await record(
        depositNotification(from: '김철수', amount: 20000, minute: 40),
      );

      final Deposit settlement = (await deposits.findPending())
          .firstWhere((Deposit d) => d.amount == 20000);
      await linkDeposit.link(deposit: settlement, transaction: payment);

      expect(await earnedIncome(), 3000000);

      // 카테고리 통계에도 정산이 섞이지 않아야 한다.
      final List<Map<String, Object?>> byCategory = await incomeByCategory();
      expect(
        byCategory.map((Map<String, Object?> r) => r['name']),
        isNot(contains(CategoryTaxonomy.settlementCategory)),
      );
    });
  });

  group('수입 카테고리', () {
    test('정산 카테고리가 존재한다', () {
      expect(
        CategoryTaxonomy.incomeCategories,
        contains(CategoryTaxonomy.settlementCategory),
      );
      expect(
        CategoryTaxonomy.incomeSubcategoriesOf(
          CategoryTaxonomy.settlementCategory,
        ),
        contains('더치페이'),
      );
    });

    test('기존 분류는 그대로 유효하다', () {
      // 이미 저장된 거래가 화면에서 깨지면 안 된다.
      for (final (String c, String s) in <(String, String)>[
        ('급여', '월급'),
        ('용돈', '용돈'),
        ('장학금', '장학금'),
        ('부수입', '이자'),
        ('부수입', '중고거래'),
        ('기타', '미분류'),
      ]) {
        expect(
          CategoryTaxonomy.coerceIncome(c, s),
          CategoryPair(c, s),
          reason: '$c/$s 가 사라지면 기존 거래의 분류가 깨진다',
        );
      }
    });

    test('새 분류가 추가되었다', () {
      expect(CategoryTaxonomy.coerceIncome('부수입', '캐시백'),
          const CategoryPair('부수입', '캐시백'));
      expect(CategoryTaxonomy.coerceIncome('투자', '배당'),
          const CategoryPair('투자', '배당'));
      expect(CategoryTaxonomy.coerceIncome('기타', '송금'),
          const CategoryPair('기타', '송금'));
    });
  });

  group('v10 -> v11 이관', () {
    test('기존 DB 를 열어도 데이터가 남고 입금 연결이 동작한다', () async {
      await db.close();

      final Directory dir =
          await Directory.systemTemp.createTemp('deposit_income_upgrade');
      final String path = '${dir.path}/budget.db';

      // transaction_id 가 없던 시절의 DB.
      const int beforeDepositLink = 10;
      final Database old = await openDatabase(
        path,
        version: beforeDepositLink,
        onCreate: (Database db, int version) =>
            LegacySchema.createAt(db, beforeDepositLink),
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      await old.insert(DbSchema.tableDeposits, <String, Object?>{
        DbSchema.dpCounterparty: '김철수',
        DbSchema.dpAmount: 20000,
        DbSchema.dpDepositedAt: now,
        DbSchema.dpRawNotification: '기존 입금',
        DbSchema.dpStatus: 'pending',
        DbSchema.dpFingerprint: 'old|1',
        DbSchema.dpCreatedAt: now,
      });
      await old.close();

      final Database upgraded = await openDatabase(
        path,
        version: DbSchema.databaseVersion,
        onUpgrade: LegacySchema.upgrade,
      );

      final List<Map<String, Object?>> kept =
          await upgraded.query(DbSchema.tableDeposits);
      expect(kept, hasLength(1), reason: '기존 입금이 살아 있어야 한다');
      // 옛 입금에는 연결이 없다. null 이면 정산 시 분류 이동만 건너뛴다.
      expect(kept.single[DbSchema.dpTransactionId], isNull);

      await upgraded.close();
      await dir.delete(recursive: true);

      db = await openDatabase(inMemoryDatabasePath);
    });
  });
}
