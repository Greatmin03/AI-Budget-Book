import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/assets/data/repositories/account_repository_impl.dart';
import 'package:budget_book/features/assets/data/repositories/asset_repository_impl.dart';
import 'package:budget_book/features/assets/domain/entities/account.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/models/transaction_dto.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 거래가 계좌 잔액에 자동 반영되는지 검증한다.
///
/// 잔액은 저장된 값이 아니라 **기준 잔액 + 기준 시각 이후 거래**의 파생값이다.
/// 그래서 거래를 지우거나 고쳐도 잔액이 어긋날 수 없다. 이 테스트는 그
/// 성질(멱등성)까지 함께 확인한다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AccountRepositoryImpl accounts;
  late AssetRepositoryImpl assets;

  /// 기준 시각. 계좌를 만든 시점으로 쓴다.
  final DateTime base = DateTime(2026, 8, 1, 9);

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
    accounts = AccountRepositoryImpl(db);
    assets = AssetRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<Account> addAccount({
    required String name,
    required int balance,
    AccountType type = AccountType.checking,
    DateTime? asOf,
  }) async {
    return accounts.save(
      Account(
        name: name,
        type: type,
        balance: balance,
        balanceAsOf: asOf ?? base,
      ),
    );
  }

  Future<int> addTransaction({
    required int amount,
    required int? accountId,
    TransactionDirection direction = TransactionDirection.expense,
    bool isAssetTransfer = false,
    String? assetKind,
    DateTime? at,
    String brand = '테스트',
  }) {
    final DateTime when = at ?? DateTime(2026, 8, 10, 12);
    final Transaction tx = Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      category: '식비',
      subcategory: '카페',
      method: PaymentMethodKind.card,
      paymentDatetime: when,
      rawNotification: 'test',
      fingerprint: '$brand|$amount|${when.microsecondsSinceEpoch}'
          '|$direction|$accountId',
      classificationSource: ClassificationSource.user,
      direction: direction,
      accountId: accountId,
      isAssetTransfer: isAssetTransfer,
      assetKind: assetKind,
    );
    return db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  Future<Account> reload(int id) async {
    final List<Account> all = await accounts.findAll();
    return all.firstWhere((Account a) => a.id == id);
  }

  group('거래 → 잔액 자동 반영', () {
    test('요구사항 예시: 1,000,000원 계좌에서 15,000원 결제 → 985,000원', () async {
      final Account account =
          await addAccount(name: 'KB 입출금', balance: 1000000);
      await addTransaction(amount: 15000, accountId: account.id);

      final Account after = await reload(account.id!);

      expect(after.currentBalance, 985000);
      expect(after.balance, 1000000, reason: '기준 잔액은 그대로 남는다');
      expect(after.transactionDelta, -15000);
    });

    test('수입은 잔액을 늘린다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(
        amount: 300000,
        accountId: account.id,
        direction: TransactionDirection.income,
      );

      expect((await reload(account.id!)).currentBalance, 1300000);
    });

    test('수입과 지출이 같은 계좌에서 상쇄된다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(
        amount: 300000,
        accountId: account.id,
        direction: TransactionDirection.income,
      );
      await addTransaction(amount: 15000, accountId: account.id);

      expect((await reload(account.id!)).currentBalance, 1285000);
    });

    test('자산 이동은 나간 계좌에서 빠진다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(
        amount: 500000,
        accountId: account.id,
        isAssetTransfer: true,
        assetKind: 'saving',
      );

      // 적금에 넣었으면 입출금 계좌에서는 실제로 빠져나간 것이다.
      // 여기를 0으로 두면 "옮겼는데 잔액이 그대로" 가 된다.
      expect((await reload(account.id!)).currentBalance, 500000);
    });

    test('받는 계좌를 지정하면 그만큼 늘고 총자산은 그대로다', () async {
      final Account from = await addAccount(name: 'KB', balance: 1000000);
      final Account to = await addAccount(
        name: '청년미래적금',
        balance: 0,
        type: AccountType.savings,
      );

      final int txId = await addTransaction(
        amount: 500000,
        accountId: from.id,
        isAssetTransfer: true,
        assetKind: 'saving',
      );
      await assets.markTransaction(
        transactionId: txId,
        fromAccount: 'KB',
        toAccount: '청년미래적금',
        toAccountId: to.id,
        amount: 500000,
        transferredAt: DateTime(2026, 8, 10, 12),
      );

      expect((await reload(from.id!)).currentBalance, 500000);
      expect((await reload(to.id!)).currentBalance, 500000);

      // 총자산이 안 변하는 것은 받는 계좌가 늘어서지, 나간 계좌가 안 줄어서가
      // 아니다.
      expect((await accounts.overview()).totalAssets, 1000000);
    });

    test('받는 계좌를 지정하지 않으면 나간 쪽만 줄어든다', () async {
      final Account from = await addAccount(name: 'KB', balance: 1000000);
      final int txId = await addTransaction(
        amount: 500000,
        accountId: from.id,
        isAssetTransfer: true,
        assetKind: 'saving',
      );
      await assets.markTransaction(
        transactionId: txId,
        fromAccount: 'KB',
        toAccount: '외부 적금',
        amount: 500000,
        transferredAt: DateTime(2026, 8, 10, 12),
      );

      // 추적하지 않는 곳으로 나갔다. 내 자산에서는 실제로 줄어든 것이 맞다.
      expect((await reload(from.id!)).currentBalance, 500000);
      expect((await accounts.overview()).totalAssets, 500000);
    });

    test('취소 거래(음수)는 잔액을 되돌린다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(amount: 30000, accountId: account.id);
      await addTransaction(amount: -30000, accountId: account.id);

      expect((await reload(account.id!)).currentBalance, 1000000);
    });

    test('계좌를 고르지 않은 거래는 어떤 잔액에도 영향이 없다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(amount: 50000, accountId: null);

      expect((await reload(account.id!)).currentBalance, 1000000);
    });

    test('다른 계좌의 거래는 서로 섞이지 않는다', () async {
      final Account kb = await addAccount(name: 'KB', balance: 1000000);
      final Account toss = await addAccount(
        name: '토스',
        balance: 500000,
        type: AccountType.cash,
      );

      await addTransaction(amount: 15000, accountId: kb.id);
      await addTransaction(amount: 7000, accountId: toss.id);

      expect((await reload(kb.id!)).currentBalance, 985000);
      expect((await reload(toss.id!)).currentBalance, 493000);
    });

    test('기준 시각 이전의 거래는 반영되지 않는다', () async {
      // 사용자가 8/1 에 "지금 잔액 100만원" 이라고 입력했다면,
      // 7월 거래는 그 100만원에 이미 반영되어 있다. 다시 빼면 이중 차감이다.
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(
        amount: 99999,
        accountId: account.id,
        at: DateTime(2026, 7, 20),
      );

      expect((await reload(account.id!)).currentBalance, 1000000);
    });

    test('잔액을 다시 입력하면 그 시점부터 새로 계산된다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(
        amount: 15000,
        accountId: account.id,
        at: DateTime(2026, 8, 2),
      );
      expect((await reload(account.id!)).currentBalance, 985000);

      // 사용자가 통장을 보고 "지금 980,000원" 이라고 고쳐 넣는다.
      await accounts.updateBalance(id: account.id!, balance: 980000);

      final Account after = await reload(account.id!);
      expect(
        after.currentBalance,
        980000,
        reason: '이미 반영된 과거 거래가 두 번 빠지면 안 된다',
      );
      expect(after.transactionDelta, 0);
    });

    test('거래를 지우면 잔액이 자동으로 되돌아온다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      final int txId = await addTransaction(
        amount: 15000,
        accountId: account.id,
      );
      expect((await reload(account.id!)).currentBalance, 985000);

      await db.delete(
        DbSchema.tableTransactions,
        where: '${DbSchema.tId} = ?',
        whereArgs: <Object?>[txId],
      );

      expect(
        (await reload(account.id!)).currentBalance,
        1000000,
        reason: '파생값이므로 되돌리는 코드가 필요 없다',
      );
    });

    test('금액을 수정하면 차액이 자동으로 반영된다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      final int txId = await addTransaction(
        amount: 15000,
        accountId: account.id,
      );

      await db.update(
        DbSchema.tableTransactions,
        <String, Object?>{DbSchema.tAmount: 20000},
        where: '${DbSchema.tId} = ?',
        whereArgs: <Object?>[txId],
      );

      expect((await reload(account.id!)).currentBalance, 980000);
    });

    test('여러 번 조회해도 값이 변하지 않는다 (멱등)', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(amount: 15000, accountId: account.id);

      for (int i = 0; i < 3; i++) {
        expect((await reload(account.id!)).currentBalance, 985000);
      }
    });

    test('정산을 받아도 잔액은 원래 결제 금액으로 빠진다', () async {
      // 카드에서 나간 돈은 30,000원이다. 친구가 보내 준 20,000원은
      // 입금으로 따로 들어온다. net 을 쓰면 환급이 두 번 반영된다.
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      final int txId = await addTransaction(
        amount: 30000,
        accountId: account.id,
      );
      await db.insert(DbSchema.tableSettlements, <String, Object?>{
        DbSchema.stTransactionId: txId,
        DbSchema.stCounterparty: '김철수',
        DbSchema.stAmount: 20000,
        DbSchema.stSettledAt: DateTime(2026, 8, 11).millisecondsSinceEpoch,
        DbSchema.stCreatedAt: DateTime(2026, 8, 11).millisecondsSinceEpoch,
      });

      expect((await reload(account.id!)).currentBalance, 970000);
    });
  });

  group('총자산과 기간별 변화', () {
    test('총자산은 모든 계좌의 현재 잔액 합이다', () async {
      final Account kb = await addAccount(name: '국민은행', balance: 1250000);
      await addAccount(name: '토스', balance: 350000, type: AccountType.cash);
      await addAccount(
        name: '카카오뱅크',
        balance: 1100000,
        type: AccountType.checking,
      );
      await addAccount(name: '현금', balance: 500000, type: AccountType.cash);

      await addTransaction(amount: 15000, accountId: kb.id);

      final AssetOverview overview = await accounts.overview();

      expect(overview.totalAssets, 1250000 + 350000 + 1100000 + 500000 - 15000);
    });

    test('오늘 / 이번 주 / 이번 달 변화를 각각 계산한다', () async {
      final DateTime now = DateTime.now();
      final Account account = await addAccount(
        name: 'KB',
        balance: 1000000,
        // 이번 달 거래가 모두 반영되도록 기준 시각을 달 시작으로 둔다.
        asOf: DateTime(now.year, now.month),
      );

      // 오늘 -15,000
      await addTransaction(
        amount: 15000,
        accountId: account.id,
        at: DateTime(now.year, now.month, now.day, 12),
      );

      final AssetOverview overview = await accounts.overview();

      expect(overview.todayChange, -15000);
      expect(
        overview.monthChange,
        -15000,
        reason: '오늘 거래는 이번 달에도 포함된다',
      );
    });

    test('기간 변화는 계좌 없는 거래를 세지 않는다', () async {
      final DateTime now = DateTime.now();
      await addTransaction(
        amount: 50000,
        accountId: null,
        at: DateTime(now.year, now.month, now.day, 10),
      );

      expect(
        await accounts.balanceChangeInRange(DateRange.today(now)),
        0,
      );
    });

    test('계좌를 지우면 그 거래는 잔액 계산에서 빠지고 거래는 남는다', () async {
      final Account account = await addAccount(name: 'KB', balance: 1000000);
      await addTransaction(amount: 15000, accountId: account.id);

      await accounts.delete(account.id!);

      final List<Map<String, Object?>> rows = await db.query(
        DbSchema.tableTransactions,
      );
      expect(rows.length, 1, reason: '거래는 지워지지 않는다');
      expect(rows.single[DbSchema.tAccountId], isNull);
    });
  });
}
