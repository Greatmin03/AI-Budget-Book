import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import 'package:budget_book/features/ingest/data/repositories/ingest_failure_repository_impl.dart';
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
import 'package:budget_book/features/settlements/domain/entities/settlement.dart';
import 'package:budget_book/features/settlements/domain/usecases/manage_settlements.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 더치페이 한 바퀴 — 결제 → 분할 → 송금 수신 → 연결 → 통계.
///
/// 스펙 #5·#6·#7 이 실제로 동작하는지 **파이프라인 전체로** 확인한다.
/// 개별 단위는 이미 테스트가 있지만, 이어 붙였을 때 숫자가 맞는지는
/// 따로 확인해야 한다. 중간에 한 군데만 어긋나도 사용자에게는 틀린 값이 보인다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
  late DepositRepositoryImpl deposits;
  late ManageSettlements settlements;
  late LinkDepositToTransaction linkDeposit;
  late RecordPaymentNotification record;

  final DateRange august = DateRange.month(DateTime(2026, 8, 5));

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

    final SettingsRepositoryImpl settingsRepo =
        SettingsRepositoryImpl(SettingsLocalDataSource(db));
    await settingsRepo.load();

    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
    deposits = DepositRepositoryImpl(DepositLocalDataSource(db));
    settlements = ManageSettlements(
      settlements: SettlementRepositoryImpl(SettlementLocalDataSource(db)),
      transactions: transactions,
    );
    linkDeposit = LinkDepositToTransaction(
      deposits: deposits,
      settlements: settlements,
      transactions: transactions,
    );
    record = RecordPaymentNotification(
      parser: const PaymentNotificationParser(),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      transactions: transactions,
      failures: IngestFailureRepositoryImpl(IngestFailureLocalDataSource(db)),
      settings: settingsRepo,
      deposits: deposits,
      recurring: RecurringRepositoryImpl(db),
    );
  });

  tearDown(() async => db.close());

  /// 내가 30,000원을 대신 결제했다.
  Future<Transaction> payForEveryone({int amount = 30000}) async {
    final DateTime when = DateTime(2026, 8, 5, 19);
    return (await transactions.insert(
      Transaction(
        merchantRaw: '맥도날드 춘천점',
        brand: '맥도날드',
        amount: amount,
        category: '식비',
        subcategory: '패스트푸드',
        method: PaymentMethodKind.card,
        paymentDatetime: when,
        rawNotification: 'test',
        fingerprint: 'pay|$amount|${when.microsecondsSinceEpoch}',
        classificationSource: ClassificationSource.seed,
      ),
    ))!;
  }

  RawNotification transferIn(int amount, {int minute = 30}) => RawNotification(
        packageName: 'com.kbstar.kbbank',
        title: 'KB국민은행',
        text: '[KB]08/05 20:$minute 김철수 님이 $amount원을 입금했습니다. '
            '잔액 1,000,000원',
        postedAt: DateTime(2026, 8, 5, 20, minute),
      );

  StatisticsLocalDataSource stats() => StatisticsLocalDataSource(db);

  group('#5 더치페이 — 3명이 나눠 냈다', () {
    test('총 30,000원 / 3명 -> 내 부담 10,000원, 받을 20,000원', () async {
      final Transaction payment = await payForEveryone();

      final List<Settlement> created = await settlements.splitEvenly(
        transaction: payment,
        counterparties: <String>['김철수', '이영희'],
        totalPeople: 3,
      );

      // 본인 몫을 뺀 2명분이 정산으로 생긴다.
      expect(created, hasLength(2));
      expect(
        created.fold<int>(0, (int sum, Settlement s) => sum + s.amount),
        20000,
      );

      final Transaction after = (await transactions.findById(payment.id!))!;
      expect(after.settledAmount, 20000, reason: '받아야 할 금액');
      expect(after.netAmount, 10000, reason: '내 부담');
    });

    test('원본 거래 금액은 그대로다', () async {
      final Transaction payment = await payForEveryone();
      await settlements.splitEvenly(
        transaction: payment,
        counterparties: <String>['김철수', '이영희'],
        totalPeople: 3,
      );

      final Transaction after = (await transactions.findById(payment.id!))!;
      // 카드 명세와 항상 일치해야 한다.
      expect(after.amount, 30000);
    });

    test('나누어떨어지지 않으면 합계가 어긋나지 않는다', () async {
      final Transaction payment = await payForEveryone(amount: 10000);

      // 10,000원 / 3명 = 3,333.33...
      final List<Settlement> created = await settlements.splitEvenly(
        transaction: payment,
        counterparties: <String>['김철수', '이영희'],
        totalPeople: 3,
      );

      final int total =
          created.fold<int>(0, (int sum, Settlement s) => sum + s.amount);
      final Transaction after = (await transactions.findById(payment.id!))!;

      // 내 부담 + 받을 금액 = 원본. 1원도 새면 안 된다.
      expect(total + after.netAmount, 10000);
    });
  });

  group('#6 송금 수신 -> 더치페이 연결', () {
    test('입금이 오면 맞는 거래를 후보로 제안한다', () async {
      final Transaction payment = await payForEveryone();
      await settlements.splitEvenly(
        transaction: payment,
        counterparties: <String>['김철수', '이영희'],
        totalPeople: 3,
      );

      // 친구가 10,000원을 보냈다.
      await record(transferIn(10000));
      final Deposit deposit = (await deposits.findPending())
          .firstWhere((Deposit d) => d.amount == 10000);

      final List<Transaction> candidates =
          await linkDeposit.findCandidates(deposit);

      expect(candidates, isNotEmpty);
      expect(candidates.first.id, payment.id);
    });

    test('연결하면 받을 금액이 줄어든다', () async {
      final Transaction payment = await payForEveryone();
      await settlements.splitEvenly(
        transaction: payment,
        counterparties: <String>['김철수', '이영희'],
        totalPeople: 3,
      );
      expect(
        (await transactions.findById(payment.id!))!.settledAmount,
        20000,
      );

      await record(transferIn(10000));
      final Deposit deposit = (await deposits.findPending())
          .firstWhere((Deposit d) => d.amount == 10000);
      await linkDeposit.link(deposit: deposit, transaction: payment);

      // 이미 분할로 20,000원을 잡아 뒀는데 실제 입금까지 더하면 30,000원이
      // 되어 내 부담이 0원이 된다. 분할은 "예상", 입금은 "실제" 다.
      final Transaction after = (await transactions.findById(payment.id!))!;
      expect(after.settledAmount, 30000);
      expect(after.netAmount, 0);
    });

    test('분할 없이 입금만 연결해도 부담이 줄어든다', () async {
      final Transaction payment = await payForEveryone();

      await record(transferIn(20000));
      final Deposit deposit = (await deposits.findPending()).single;
      await linkDeposit.link(deposit: deposit, transaction: payment);

      final Transaction after = (await transactions.findById(payment.id!))!;
      expect(after.netAmount, 10000);
      expect(deposit.transactionId, isNotNull);
    });

    test('연결하면 정산 후보 목록에서 내려간다', () async {
      final Transaction payment = await payForEveryone();
      await record(transferIn(20000));
      final Deposit deposit = (await deposits.findPending()).single;

      await linkDeposit.link(deposit: deposit, transaction: payment);

      expect(await deposits.countPending(), 0);
    });

    test('"정산 아님" 으로 내릴 수도 있다', () async {
      await record(transferIn(3000000));
      final Deposit deposit = (await deposits.findPending()).single;

      await linkDeposit.ignore(deposit);

      expect(await deposits.countPending(), 0);
    });
  });

  group('#7 통계는 실제 부담만 센다', () {
    /// 30,000원 결제 → 친구 2명이 20,000원 송금 → 실제 부담 10,000원.
    Future<Transaction> fullCycle() async {
      final Transaction payment = await payForEveryone();
      await record(transferIn(10000, minute: 30));
      await record(transferIn(10000, minute: 40));

      for (final Deposit deposit in await deposits.findPending()) {
        await linkDeposit.link(deposit: deposit, transaction: payment);
      }
      return payment;
    }

    test('총 소비', () async {
      await fullCycle();
      expect(await stats().totalInRange(august), 10000);
    });

    test('카테고리 통계', () async {
      await fullCycle();
      final List<Map<String, Object?>> byCategory =
          await stats().byCategory(august);

      expect(byCategory, hasLength(1));
      expect(byCategory.single['name'], '식비');
      expect(byCategory.single['amount'], 10000);
    });

    test('브랜드 통계', () async {
      await fullCycle();
      final List<Map<String, Object?>> byBrand =
          await stats().byBrand(august, 10);

      expect(byBrand.single['brand'], '맥도날드');
      expect(byBrand.single['amount'], 10000);
    });

    test('세부항목 통계', () async {
      await fullCycle();
      final List<Map<String, Object?>> bySub =
          await stats().bySubcategory(august);

      expect(bySub.single['name'], '패스트푸드');
      expect(bySub.single['amount'], 10000);
    });

    test('원본 합계는 따로 볼 수 있다', () async {
      await fullCycle();

      // 정산을 빼기 전 금액. "카드에서 얼마가 나갔나" 에 답한다.
      expect(await stats().grossTotalInRange(august), 30000);
      expect(await stats().totalInRange(august), 10000);
    });

    test('수입에는 잡히지 않는다', () async {
      await fullCycle();

      // 돌려받은 돈은 번 돈이 아니다. 이미 부담이 줄어 있으므로 수입으로도
      // 세면 같은 돈을 두 번 센다.
      expect(await stats().incomeTotalInRange(august), 0);

      final List<Map<String, Object?>> income =
          await stats().incomeByCategory(august);
      expect(
        income.map((Map<String, Object?> r) => r['name']),
        isNot(contains(CategoryTaxonomy.settlementCategory)),
      );
    });

    test('거래 목록에는 원본과 실부담이 둘 다 남는다', () async {
      final Transaction payment = await fullCycle();

      final Transaction after = (await transactions.findById(payment.id!))!;
      expect(after.amount, 30000, reason: '카드 명세와 대조할 수 있어야 한다');
      expect(after.netAmount, 10000);
      expect(after.hasSettlements, isTrue);
    });
  });
}
