import 'dart:io';

import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/assets/data/repositories/account_repository_impl.dart';
import 'package:budget_book/features/assets/data/repositories/card_account_link_repository_impl.dart';
import 'package:budget_book/features/assets/domain/entities/account.dart';
import 'package:budget_book/features/assets/domain/entities/card_account_link.dart';
import 'package:budget_book/features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import 'package:budget_book/features/ingest/data/repositories/ingest_failure_repository_impl.dart';
import 'package:budget_book/features/ingest/domain/entities/ingest_result.dart';
import 'package:budget_book/features/ingest/domain/usecases/record_payment_notification.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/notifications/domain/entities/raw_notification.dart';
import 'package:budget_book/features/parsing/domain/services/payment_notification_parser.dart';
import 'package:budget_book/features/recurring/data/repositories/recurring_repository_impl.dart';
import 'package:budget_book/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:budget_book/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:budget_book/features/settlements/data/datasources/settlement_local_datasource.dart';
import 'package:budget_book/features/settlements/data/repositories/settlement_repository_impl.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/legacy_schema.dart';

/// 카드 -> 계좌 연결.
///
/// 알림으로 들어온 거래에는 `account_id` 가 없다. 이 연결이 없으면 결제가
/// 아무리 쌓여도 잔액은 움직이지 않는다. 그래서 여기서 확인하는 것은
/// **연결이 실제로 잔액을 움직이는가** 하나다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late CardAccountLinkRepositoryImpl links;
  late AccountRepositoryImpl accounts;
  late TransactionRepositoryImpl transactions;

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
      },
    );
    links = CardAccountLinkRepositoryImpl(db);
    accounts = AccountRepositoryImpl(db);
    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
  });

  tearDown(() async => db.close());

  /// [asOf] 는 기준 시각이다. 이 시각 이후의 거래만 잔액에 반영된다.
  Future<int> insertAccount(String name, int balance, {DateTime? asOf}) async {
    final Account saved = await accounts.save(
      Account(
        name: name,
        type: AccountType.checking,
        balance: balance,
        balanceAsOf: asOf,
      ),
    );
    return saved.id!;
  }

  /// 알림으로 수집된 거래를 흉내낸다. 핵심은 `account_id` 가 없다는 것이다.
  ///
  /// 실제 저장 경로(repository)를 그대로 쓴다. 원시 INSERT 로 흉내내면
  /// 저장 규칙이 바뀌었을 때 이 테스트만 조용히 통과한다.
  int seq = 0;
  Future<void> insertNotificationTransaction({
    required String cardName,
    required int amount,
    String direction = 'expense',
    int? accountId,
  }) async {
    // 잔액은 "기준 시각 이후" 거래만 더한다. 계좌를 만든 뒤 시각이어야
    // 반영된다.
    final DateTime when =
        DateTime.now().add(Duration(seconds: 1 + seq++));
    await transactions.insert(
      Transaction(
        merchantRaw: '테스트가맹점',
        brand: '테스트가맹점',
        amount: amount,
        category: '미분류',
        subcategory: '미분류',
        method: PaymentMethodKind.card,
        cardName: cardName,
        accountId: accountId,
        paymentDatetime: when,
        rawNotification: 'test',
        fingerprint: '$cardName|$amount|${when.microsecondsSinceEpoch}',
        classificationSource: ClassificationSource.seed,
        direction: direction == 'income'
            ? TransactionDirection.income
            : TransactionDirection.expense,
      ),
    );
  }

  Future<int> currentBalance(int accountId) async {
    final Account? account = await accounts.findById(accountId);
    return account!.currentBalance;
  }

  group('연결 조회', () {
    test('연결이 없으면 null 이다', () async {
      expect(await links.accountIdFor('KB국민카드'), isNull);
    });

    test('빈 카드 이름은 조회하지 않는다', () async {
      expect(await links.accountIdFor('   '), isNull);
    });

    test('거래에 등장한 카드만 목록에 나온다', () async {
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 5000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 3000);
      await insertNotificationTransaction(cardName: '신한카드', amount: 1000);

      final List<CardAccountLink> all = await links.findAll();

      // 거래가 많은 카드가 먼저 온다. 연결할 가치가 큰 것부터 보여 준다.
      expect(all.map((CardAccountLink l) => l.cardName), <String>[
        'KB국민카드',
        '신한카드',
      ]);
      expect(all.first.transactionCount, 2);
      expect(all.every((CardAccountLink l) => !l.isLinked), isTrue);
    });

    test('연결된 카드는 계좌 이름을 함께 보여 준다', () async {
      final int accountId = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 5000);
      await links.link(cardName: 'KB국민카드', accountId: accountId);

      final CardAccountLink link = (await links.findAll()).single;

      expect(link.isLinked, isTrue);
      expect(link.accountId, accountId);
      expect(link.accountName, 'KB 입출금');
    });
  });

  group('연결 시 과거 거래 소급 반영', () {
    test('연결 전에는 잔액이 움직이지 않는다', () async {
      final int accountId = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);

      expect(await currentBalance(accountId), 1000000);
    });

    test('연결하면 과거 지출이 잔액에서 빠진다', () async {
      final int accountId = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 5000);

      final int updated =
          await links.link(cardName: 'KB국민카드', accountId: accountId);

      expect(updated, 2);
      expect(await currentBalance(accountId), 1000000 - 20000);
    });

    test('수입은 잔액에 더해진다', () async {
      final int accountId = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(
        cardName: 'KB국민카드',
        amount: 300000,
        direction: 'income',
      );

      await links.link(cardName: 'KB국민카드', accountId: accountId);

      expect(await currentBalance(accountId), 1300000);
    });

    test('다른 카드의 거래는 건드리지 않는다', () async {
      final int kb = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);
      await insertNotificationTransaction(cardName: '신한카드', amount: 99000);

      final int updated = await links.link(cardName: 'KB국민카드', accountId: kb);

      expect(updated, 1);
      expect(await currentBalance(kb), 1000000 - 15000);
    });

    test('이미 계좌가 지정된 거래는 덮어쓰지 않는다', () async {
      final int kb = await insertAccount('KB 입출금', 1000000);
      final int other = await insertAccount('현금', 50000);

      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);
      // 사용자가 개별로 계좌를 고른 거래.
      await insertNotificationTransaction(
        cardName: 'KB국민카드',
        amount: 7000,
        accountId: other,
      );

      final int updated = await links.link(cardName: 'KB국민카드', accountId: kb);

      // 일괄 연결이 사용자의 선택을 덮으면 안 된다.
      expect(updated, 1);
      expect(await currentBalance(kb), 1000000 - 15000);
      expect(await currentBalance(other), 50000 - 7000);
    });

    test('다시 연결하면 계좌가 바뀐다', () async {
      final int kb = await insertAccount('KB 입출금', 1000000);
      final int cash = await insertAccount('현금', 500000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);

      await links.link(cardName: 'KB국민카드', accountId: kb);
      expect(await links.accountIdFor('KB국민카드'), kb);

      // 연결만 바꾸면 이미 붙은 거래는 그대로 남는다. 사용자가 먼저 해제해야
      // 한다 — 조용히 옮기는 것보다 명시적인 편이 안전하다.
      await links.unlink('KB국민카드');
      await links.link(cardName: 'KB국민카드', accountId: cash);

      expect(await links.accountIdFor('KB국민카드'), cash);
      expect(await currentBalance(kb), 1000000);
      expect(await currentBalance(cash), 500000 - 15000);
    });
  });

  group('연결 해제', () {
    test('해제하면 잔액도 되돌아온다', () async {
      final int accountId = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);
      await links.link(cardName: 'KB국민카드', accountId: accountId);
      expect(await currentBalance(accountId), 985000);

      final int reverted = await links.unlink('KB국민카드');

      expect(reverted, 1);
      expect(await currentBalance(accountId), 1000000);
      expect(await links.accountIdFor('KB국민카드'), isNull);
    });

    test('연결이 없으면 아무것도 하지 않는다', () async {
      expect(await links.unlink('없는카드'), 0);
    });

    test('다른 계좌로 지정된 거래는 되돌리지 않는다', () async {
      final int kb = await insertAccount('KB 입출금', 1000000);
      final int cash = await insertAccount('현금', 500000);

      await insertNotificationTransaction(
        cardName: 'KB국민카드',
        amount: 7000,
        accountId: cash,
      );
      await links.link(cardName: 'KB국민카드', accountId: kb);

      final int reverted = await links.unlink('KB국민카드');

      expect(reverted, 0);
      expect(await currentBalance(cash), 500000 - 7000);
    });
  });

  group('알림 수집 시 자동 연결', () {
    /// 실제 수집 경로. 연결이 있으면 저장 시점에 계좌가 붙어야 한다.
    /// 그래야 사용자가 매번 손대지 않아도 잔액이 따라온다.
    Future<RecordPaymentNotification> buildIngest() async {
      final SettingsRepositoryImpl settings =
          SettingsRepositoryImpl(SettingsLocalDataSource(db));
      await settings.load();

      return RecordPaymentNotification(
        parser: const PaymentNotificationParser(),
        merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
        transactions: transactions,
        failures: IngestFailureRepositoryImpl(IngestFailureLocalDataSource(db)),
        settings: settings,
        deposits: DepositRepositoryImpl(DepositLocalDataSource(db)),
        recurring: RecurringRepositoryImpl(db),
        cardLinks: links,
      );
    }

    RawNotification cardPayment(int amount) => RawNotification(
          packageName: 'com.kbcard.cxh.appcard',
          title: 'KB국민카드',
          text: 'KB국민카드 승인 홍*동 $amount원 일시불 '
              '08/05 14:33 스타벅스춘천점',
          postedAt: DateTime.now(),
        );

    test('연결이 없으면 계좌를 붙이지 않는다', () async {
      final RecordPaymentNotification record = await buildIngest();

      final IngestResult result = await record(cardPayment(5000));

      expect(result, isA<IngestSaved>());
      expect((result as IngestSaved).transaction.accountId, isNull);
    });

    test('연결이 있으면 저장 시점에 계좌가 붙는다', () async {
      // 알림의 결제 시각(`08/05 14:33`)보다 기준 시각이 앞서야 잔액에 잡힌다.
      final int accountId = await insertAccount(
        'KB 입출금',
        1000000,
        asOf: DateTime(2000),
      );
      await links.link(cardName: 'KB국민카드', accountId: accountId);

      final RecordPaymentNotification record = await buildIngest();
      final IngestResult result = await record(cardPayment(5000));

      expect(result, isA<IngestSaved>());
      expect((result as IngestSaved).transaction.accountId, accountId);
      // 사용자가 아무것도 하지 않아도 잔액이 따라온다.
      expect(await currentBalance(accountId), 1000000 - 5000);
    });
  });

  group('계좌 삭제', () {
    test('계좌를 지워도 연결이 잔액을 망가뜨리지 않는다', () async {
      final int accountId = await insertAccount('KB 입출금', 1000000);
      await insertNotificationTransaction(cardName: 'KB국민카드', amount: 15000);
      await links.link(cardName: 'KB국민카드', accountId: accountId);

      await accounts.delete(accountId);

      // 연결 행이 남아 있으면 다음 알림이 없는 계좌를 가리키게 된다.
      expect(await links.accountIdFor('KB국민카드'), isNull);
    });
  });

  group('v9 -> v10 이관', () {
    /// 기기에는 이미 v9 데이터가 있다. 이관이 깨지면 사용자의 거래가 사라진다.
    test('기존 DB 를 열어도 데이터가 남고 연결이 동작한다', () async {
      await db.close();

      final Directory dir =
          await Directory.systemTemp.createTemp('card_link_upgrade');
      final String path = '${dir.path}/budget.db';

      // v10 이 없던 시절의 DB.
      const int beforeCardLinks = 9;
      final Database old = await openDatabase(
        path,
        version: beforeCardLinks,
        onCreate: (Database db, int version) =>
            LegacySchema.createAt(db, beforeCardLinks),
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      await old.insert(DbSchema.tableAccounts, <String, Object?>{
        DbSchema.acName: '기존 계좌',
        DbSchema.acType: 'checking',
        DbSchema.acBalance: 1000000,
        DbSchema.acBalanceAsOf: 0,
        DbSchema.acCreatedAt: now,
        DbSchema.acUpdatedAt: now,
      });
      await old.close();

      // 앱 업데이트 = 같은 파일을 새 버전으로 다시 연다.
      final Database upgraded = await openDatabase(
        path,
        version: DbSchema.databaseVersion,
        onUpgrade: LegacySchema.upgrade,
      );

      final List<Map<String, Object?>> kept =
          await upgraded.query(DbSchema.tableAccounts);
      expect(kept, hasLength(1), reason: '기존 계좌가 살아 있어야 한다');

      // 새 테이블이 실제로 쓸 수 있는 상태여야 한다.
      final CardAccountLinkRepositoryImpl migrated =
          CardAccountLinkRepositoryImpl(upgraded);
      await migrated.link(cardName: 'KB국민카드', accountId: 1);
      expect(await migrated.accountIdFor('KB국민카드'), 1);

      await upgraded.close();
      await dir.delete(recursive: true);

      // tearDown 이 다시 닫아도 문제없도록 되살려 둔다.
      db = await openDatabase(inMemoryDatabasePath);
    });
  });
}
