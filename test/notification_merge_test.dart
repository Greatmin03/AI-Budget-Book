import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/database/seed/brand_seed.dart';
import 'package:budget_book/features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import 'package:budget_book/features/ingest/data/repositories/ingest_failure_repository_impl.dart';
import 'package:budget_book/features/ingest/domain/entities/ingest_result.dart';
import 'package:budget_book/features/ingest/domain/usecases/record_payment_notification.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/merchants/domain/services/brand_extractor.dart';
import 'package:budget_book/features/notifications/domain/entities/raw_notification.dart';
import 'package:budget_book/features/parsing/domain/entities/notification_source_trait.dart';
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

/// 같은 결제를 여러 앱이 알린다.
///
/// ```
/// 토스   더스윙                                  ← 브랜드가 정확하다
/// KB     ... 통신판매_NIC 체크카드출금 3,000 잔액1,264,862
///                                              ↑ 계좌·잔액이 있다
/// ```
///
/// 둘 다 저장하면 가계부가 두 배가 되고, 하나를 버리면 무언가를 잃는다.
/// **거래는 하나만 남기고 정보만 합친다.**
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
  late RecordPaymentNotification record;

  const String tossPackage = 'viva.republica.toss';
  const String kbPackage = 'com.kbstar.kbbank';

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

    final SettingsRepositoryImpl settings =
        SettingsRepositoryImpl(SettingsLocalDataSource(db));
    await settings.load();

    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
    record = RecordPaymentNotification(
      parser: PaymentNotificationParser(
        recognizeBrand: const BrandExtractor(BrandSeed.definitions).recognizes,
      ),
      merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      transactions: transactions,
      failures: IngestFailureRepositoryImpl(IngestFailureLocalDataSource(db)),
      settings: settings,
      deposits: DepositRepositoryImpl(DepositLocalDataSource(db)),
      recurring: RecurringRepositoryImpl(db),
    );
  });

  tearDown(() async => db.close());

  /// 토스 알림. **실제 기기에서 오는 형식 그대로.**
  ///
  /// ```
  /// 3,000원 결제
  /// KB국민체크        <- 카드 이름
  /// 더스윙(일시불)     <- 가맹점
  /// ```
  ///
  /// 카드 이름이 가맹점보다 길어서, 길이로 고르면 카드 이름이 이긴다.
  RawNotification toss(
    String merchant,
    int amount, {
    int minute = 7,
    bool cancel = false,
  }) =>
      RawNotification(
        packageName: tossPackage,
        title: '토스',
        text: '$amount원 결제${cancel ? ' 취소' : ''}\n'
            'KB국민체크\n'
            '$merchant(일시불)',
        postedAt: DateTime(2026, 8, 6, 10, minute),
      );

  /// KB 은행 알림. 가맹점 이름은 전표 그대로지만 계좌와 잔액이 있다.
  RawNotification kb(String merchant, int amount, {int minute = 7}) =>
      RawNotification(
        packageName: kbPackage,
        title: 'KB국민은행',
        text: '출금 $amount원\n박*민님 08/06 10:$minute 942902-**-***245 '
            '$merchant 체크카드출금 $amount 잔액1,264,862',
        postedAt: DateTime(2026, 8, 6, 10, minute),
      );

  /// KB 취소 알림. 가맹점 이름이 없다.
  RawNotification kbCancel(int amount, {int minute = 43}) => RawNotification(
        packageName: kbPackage,
        title: 'KB국민은행',
        text: '입금 $amount원\n박*민님 08/06 10:$minute 942902-**-***245 '
            '출금취소 $amount 잔액1,264,223',
        postedAt: DateTime(2026, 8, 6, 10, minute),
      );

  Future<List<Transaction>> all() => transactions.findRecent(limit: 50);

  group('앱 특성', () {
    test('토스는 브랜드를, 은행은 계좌를 담당한다', () {
      expect(NotificationSourceTrait.of(tossPackage),
          NotificationSourceTrait.wallet);
      expect(NotificationSourceTrait.of(kbPackage),
          NotificationSourceTrait.bank);

      expect(
        NotificationSourceTrait.wallet.brandQuality,
        greaterThan(NotificationSourceTrait.bank.brandQuality),
      );
      expect(NotificationSourceTrait.bank.providesAccountDetails, isTrue);
      expect(NotificationSourceTrait.wallet.providesAccountDetails, isFalse);
    });

    test('모르는 앱은 아무것도 우선하지 않는다', () {
      expect(NotificationSourceTrait.of('com.unknown.app'),
          NotificationSourceTrait.unknown);
      expect(NotificationSourceTrait.of(null),
          NotificationSourceTrait.unknown);
    });
  });

  group('은행 알림에서 계좌·잔액을 뽑는다', () {
    test('계좌번호와 잔액이 저장된다', () async {
      await record(kb('더스윙', 3000));

      final Transaction tx = (await all()).single;
      expect(tx.accountNumber, '942902-**-***245');
      expect(tx.balanceAfter, 1264862);
    });

    test('토스 알림에는 계좌 정보가 없다', () async {
      await record(toss('더스윙', 3000));

      final Transaction tx = (await all()).single;
      expect(tx.accountNumber, isNull);
      expect(tx.balanceAfter, isNull);
    });
  });

  group('병합 — 거래는 하나만 남는다', () {
    test('KB 먼저, 토스 나중', () async {
      await record(kb('통신판매_NIC', 3000));
      final IngestResult second = await record(toss('더스윙', 3000));

      expect(second, isA<IngestMerged>());

      final List<Transaction> list = await all();
      expect(list, hasLength(1), reason: '거래는 하나여야 한다');

      final Transaction tx = list.single;
      // 브랜드는 토스 것으로 바뀌고
      expect(tx.brand, '더스윙');
      // 계좌 정보는 KB 것이 남는다
      expect(tx.accountNumber, '942902-**-***245');
      expect(tx.balanceAfter, 1264862);
      // 원본 거래명은 먼저 온 알림 그대로 — 감사 기록이다
      expect(tx.merchantRaw, '통신판매_NIC');
      expect(tx.mergedSources, containsAll(<String>[kbPackage, tossPackage]));
    });

    test('토스 먼저, KB 나중', () async {
      await record(toss('더스윙', 3000));
      final IngestResult second = await record(kb('통신판매_NIC', 3000));

      expect(second, isA<IngestMerged>());

      final Transaction tx = (await all()).single;
      // 이미 좋은 브랜드가 있으므로 은행 이름으로 덮지 않는다
      expect(tx.brand, '더스윙');
      expect(tx.merchantRaw, '더스윙');
      // 계좌 정보는 나중에 온 은행 알림에서 채운다
      expect(tx.accountNumber, '942902-**-***245');
      expect(tx.balanceAfter, 1264862);
    });

    test('브랜드가 좋아지면 분류도 함께 갱신된다', () async {
      // 은행이 준 이름은 사전에 없어 미분류로 들어간다.
      await record(kb('통신판매_NIC', 1100));
      Transaction tx = (await all()).single;
      expect(tx.needsReview, isTrue);

      // 토스가 알아볼 수 있는 이름을 준다.
      await record(toss('GS25', 1100));
      tx = (await all()).single;

      expect(tx.brand, 'GS25');
      expect(tx.category, '생활');
      expect(tx.subcategory, '편의점');
      expect(tx.needsReview, isFalse, reason: '더 물어볼 것이 없다');
    });
  });

  group('합치지 말아야 할 것은 합치지 않는다', () {
    test('금액이 다르면 각각 저장된다', () async {
      await record(kb('통신판매_NIC', 3000));
      await record(toss('더스윙', 5000));

      expect(await all(), hasLength(2));
    });

    test('시각이 멀면 각각 저장된다', () async {
      await record(kb('통신판매_NIC', 3000, minute: 7));
      await record(toss('더스윙', 3000, minute: 30));

      expect(await all(), hasLength(2));
    });

    test('같은 앱에서 두 번 오면 병합하지 않는다', () async {
      // 같은 앱이 같은 금액을 두 번 알렸다면 진짜 두 번 결제했거나
      // 중복이다. 중복은 지문으로 걸러진다.
      await record(kb('GS25', 1100, minute: 7));
      final IngestResult second = await record(kb('CU', 1100, minute: 8));

      expect(second, isNot(isA<IngestMerged>()));
      expect(await all(), hasLength(2));
    });

    test('같은 알림이 두 번 오면 여전히 중복이다', () async {
      await record(kb('GS25', 1100));
      final IngestResult second = await record(kb('GS25', 1100));

      expect(second, isA<IngestDuplicate>());
      expect(await all(), hasLength(1));
    });
  });

  group('병합해도 금액은 한 번만 센다', () {
    test('합계가 두 배가 되지 않는다', () async {
      await record(kb('통신판매_NIC', 3000));
      await record(toss('더스윙', 3000));

      final int total = (await all())
          .fold<int>(0, (int sum, Transaction t) => sum + t.amount);
      expect(total, 3000);
    });
  });

  group('실제 기기에서 온 형식 — 토스 결제 후 취소', () {
    /// 8/7 에 실제로 일어난 일.
    ///
    /// ```
    /// 21:38  KB    통신판매_NIC 체크카드출금 3,000 잔액1,261,863
    /// 21:38  토스   3,000원 결제 / KB국민체크 / 더스윙(일시불)
    /// 21:43  토스   3,000원 결제 취소 / KB국민체크 / 더스윙(일시불)
    /// 21:43  KB    출금취소 3,000 잔액1,264,223
    /// ```
    test('브랜드는 더스윙, 카드는 은행 이름, 취소는 자동 연결', () async {
      // --- 결제 ---
      await record(kb('통신판매_NIC', 3000, minute: 38));
      await record(toss('더스윙', 3000, minute: 38));

      final List<Transaction> afterPayment = await all();
      expect(afterPayment, hasLength(1), reason: '거래는 하나');

      final Transaction payment = afterPayment.single;
      // 카드 이름을 가맹점으로 착각하면 안 된다.
      expect(payment.brand, '더스윙');
      // 카드 -> 계좌 연결은 은행 이름으로 등록돼 있다. 토스 이름이 남으면
      // 이 거래는 잔액에 반영되지 않는다.
      expect(payment.cardName, 'KB국민은행');
      expect(payment.accountNumber, '942902-**-***245');

      // --- 취소 ---
      await record(toss('더스윙', 3000, minute: 43, cancel: true));
      await record(kbCancel(3000, minute: 43));

      final List<Transaction> afterCancel = await all();
      expect(afterCancel, hasLength(2), reason: '결제 하나 + 취소 하나');

      final Transaction cancellation =
          afterCancel.firstWhere((Transaction t) => t.amount < 0);
      expect(
        cancellation.cancelsTransactionId,
        payment.id,
        reason: '취소가 원결제와 이어져야 한다',
      );

      final Transaction original =
          afterCancel.firstWhere((Transaction t) => t.amount > 0);
      expect(original.isCancelled, isTrue, reason: '원결제도 통계에서 빠진다');
    });

    test('토스만 취소를 알려도 원결제를 찾는다', () async {
      await record(kb('통신판매_NIC', 3000, minute: 38));
      await record(toss('더스윙', 3000, minute: 38));

      // 취소는 토스만 알렸다. 계좌번호가 없고 카드 이름도 `토스` 라 다르다.
      await record(toss('더스윙', 3000, minute: 43, cancel: true));

      final List<Transaction> list = await all();
      final Transaction cancellation =
          list.firstWhere((Transaction t) => t.amount < 0);
      final Transaction original =
          list.firstWhere((Transaction t) => t.amount > 0);

      // 카드 이름이 달라도 브랜드로 찾아낸다. 카드 이름을 **조건**으로
      // 걸었다면 영영 못 만났을 것이다.
      expect(cancellation.cancelsTransactionId, original.id);
      expect(original.isCancelled, isTrue);
    });

    test('금액이 같은 다른 가게는 건드리지 않는다', () async {
      await record(kb('통신판매_NIC', 3000, minute: 30));
      await record(toss('더스윙', 3000, minute: 30));
      await record(kb('통신판매_NIC', 3000, minute: 35));
      await record(toss('메가커피', 3000, minute: 35));

      await record(toss('더스윙', 3000, minute: 43, cancel: true));

      final List<Transaction> list = await all();
      final Transaction mega =
          list.firstWhere((Transaction t) => t.brand == '메가MGC커피');
      expect(mega.isCancelled, isFalse, reason: '엉뚱한 결제를 지우면 안 된다');

      final Transaction swing = list.firstWhere(
        (Transaction t) => t.brand == '더스윙' && t.amount > 0,
      );
      expect(swing.isCancelled, isTrue);
    });
  });
}
