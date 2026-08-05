import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/features/transactions/domain/usecases/apply_user_correction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 거래 수정(날짜/시간/금액/수입지출/카테고리/브랜드/계좌/메모)을 검증한다.
///
/// 수정해도 절대 바뀌지 않아야 하는 것이 두 개 있다.
///  - `merchant_raw`: 알림 원본 거래명
///  - `fingerprint`: 중복 방지 키. 바꾸면 같은 알림이 다시 저장된다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
  late ApplyUserCorrection correct;

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
    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
    correct = ApplyUserCorrection(
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      transactions: transactions,
    );
  });

  tearDown(() async => db.close());

  Future<Transaction> seed({
    int amount = 15000,
    PaymentMethodKind method = PaymentMethodKind.card,
    String merchantRaw = '스타벅스강남점',
    String brand = '스타벅스',
    DateTime? at,
  }) async {
    final Transaction? saved = await transactions.insert(
      Transaction(
        merchantRaw: merchantRaw,
        brand: brand,
        amount: amount,
        category: '식비',
        subcategory: '카페',
        method: method,
        paymentDatetime: at ?? DateTime(2026, 8, 10, 14, 30),
        rawNotification: 'KB국민카드 승인 $amount원 $merchantRaw',
        fingerprint: 'fp|$merchantRaw|$amount',
        classificationSource: ClassificationSource.seed,
      ),
    );
    return saved!;
  }

  Future<Transaction> reload(int id) async {
    final Transaction? found = await transactions.findById(id);
    return found!;
  }

  group('금액 수정', () {
    test('금액을 고치면 저장된다', () async {
      final Transaction tx = await seed(amount: 15000);

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        amount: 20000,
      );

      expect((await reload(tx.id!)).amount, 20000);
    });

    test('취소 거래(음수)는 부호를 유지한다', () async {
      final Transaction tx = await seed(amount: -30000);

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        amount: 25000,
      );

      expect(
        (await reload(tx.id!)).amount,
        -25000,
        reason: '취소는 계속 차감되어야 한다',
      );
    });

    test('금액을 주지 않으면 그대로 둔다', () async {
      final Transaction tx = await seed(amount: 15000);

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '디저트',
      );

      expect((await reload(tx.id!)).amount, 15000);
    });
  });

  group('날짜 · 시간 수정', () {
    test('날짜와 시간을 함께 고친다', () async {
      final Transaction tx = await seed();
      final DateTime moved = DateTime(2026, 7, 3, 9, 5);

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        paymentDatetime: moved,
      );

      expect((await reload(tx.id!)).paymentDatetime, moved);
    });
  });

  group('지출 / 수입 전환', () {
    test('수입으로 바꾸면 방향이 바뀌고 결제 수단이 지워진다', () async {
      final Transaction tx = await seed();

      await correct(
        transaction: tx,
        category: '기타',
        subcategory: '미분류',
        direction: TransactionDirection.income,
      );

      final Transaction after = await reload(tx.id!);
      expect(after.direction, TransactionDirection.income);
      expect(after.isIncome, isTrue);
      expect(
        after.method,
        PaymentMethodKind.unknown,
        reason: '수입에 카드 결제 수단은 의미가 없다',
      );
      expect(after.countsAsSpending, isFalse);
    });

    test('금액은 수입으로 바꿔도 양수로 남는다', () async {
      final Transaction tx = await seed(amount: 15000);

      await correct(
        transaction: tx,
        category: '기타',
        subcategory: '미분류',
        direction: TransactionDirection.income,
        amount: 300000,
      );

      expect((await reload(tx.id!)).amount, 300000);
    });

    test('지출을 유지하면 결제 수단이 보존된다', () async {
      final Transaction tx = await seed();

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        direction: TransactionDirection.expense,
      );

      expect((await reload(tx.id!)).method, PaymentMethodKind.card);
    });
  });

  group('계좌 수정', () {
    test('계좌를 지정하면 잔액 반영 대상이 된다', () async {
      final Transaction tx = await seed();

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        accountId: 7,
        accountName: 'KB 입출금',
        accountChanged: true,
      );

      final Transaction after = await reload(tx.id!);
      expect(after.accountId, 7);
      expect(after.account, 'KB 입출금');
      expect(after.affectsAccountBalance, isTrue);
    });

    test('계좌를 해제하면 잔액에서 빠진다', () async {
      final Transaction tx = await seed();
      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        accountId: 7,
        accountName: 'KB',
        accountChanged: true,
      );

      await correct(
        transaction: await reload(tx.id!),
        category: '식비',
        subcategory: '카페',
        accountId: null,
        accountName: null,
        accountChanged: true,
      );

      final Transaction after = await reload(tx.id!);
      expect(after.accountId, isNull);
      expect(after.affectsAccountBalance, isFalse);
    });

    test('accountChanged 가 false 면 계좌를 건드리지 않는다', () async {
      final Transaction tx = await seed();
      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        accountId: 7,
        accountName: 'KB',
        accountChanged: true,
      );

      // 분류만 고치는 수정.
      await correct(
        transaction: await reload(tx.id!),
        category: '식비',
        subcategory: '디저트',
      );

      expect((await reload(tx.id!)).accountId, 7);
    });
  });

  group('수정해도 바뀌지 않는 것', () {
    test('원본 거래명은 절대 바뀌지 않는다', () async {
      final Transaction tx = await seed(merchantRaw: '000 스마트폰');

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '카페',
        brand: '메가커피',
        displayName: '친구 대신 결제',
      );

      final Transaction after = await reload(tx.id!);
      expect(after.merchantRaw, '000 스마트폰');
      expect(after.brand, '메가커피');
      expect(after.userDisplayName, '친구 대신 결제');
      expect(after.secondaryName, '000 스마트폰', reason: '원본을 화면에서 잃지 않는다');
    });

    test('지문은 바뀌지 않는다 (같은 알림 재수신 시 중복 방지)', () async {
      final Transaction tx = await seed();
      final String before = tx.fingerprint;

      await correct(
        transaction: tx,
        category: '쇼핑',
        subcategory: '의류',
        amount: 99000,
        paymentDatetime: DateTime(2026, 1, 1),
        direction: TransactionDirection.income,
      );

      expect((await reload(tx.id!)).fingerprint, before);
    });

    test('원본 알림 문구는 보존된다', () async {
      final Transaction tx = await seed();

      await correct(
        transaction: tx,
        category: '식비',
        subcategory: '디저트',
        amount: 1,
      );

      expect((await reload(tx.id!)).rawNotification, tx.rawNotification);
    });
  });

  group('이체 거래 수정', () {
    test('금액·날짜는 고칠 수 있지만 브랜드는 학습하지 않는다', () async {
      final Transaction tx = await seed(
        method: PaymentMethodKind.accountTransfer,
        merchantRaw: '홍길동',
        brand: '홍길동',
        amount: 30000,
      );

      final CorrectionResult result = await correct(
        transaction: tx,
        category: '식비',
        subcategory: '한식',
        brand: '메가커피',
        amount: 25000,
        applyToBrand: true,
      );

      expect(result.learned, isFalse, reason: '이체는 학습 금지');
      expect(result.blockedReason, isNotNull);

      final Transaction after = await reload(tx.id!);
      expect(after.amount, 25000, reason: '이번 거래 수정 자체는 적용된다');
      expect(after.category, '식비');
      expect(after.subcategory, '한식');
    });
  });
}
