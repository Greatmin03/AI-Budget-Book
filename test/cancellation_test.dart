import 'dart:io';

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
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/legacy_schema.dart';

/// 승인취소 / 환불.
///
/// 취소 건만 통계에서 빼면 원결제가 남아 **쓰지도 않은 돈이 잡힌다.**
/// 둘 다 남기면 금액은 상계되지만 건수가 오염된다 — 취소된 결제 한 번 때문에
/// "가장 많이 간 가게" 1위가 되는 식이다.
///
/// 그래서 취소가 오면 **양쪽 모두** 표시를 달고, 통계는 한 조건으로 둘 다 뺀다.
/// 목록에는 두 줄 다 그대로 보인다 — 없었던 일로 만드는 것은 통계뿐이다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
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

  RawNotification payment(
    String merchant,
    int amount, {
    bool cancel = false,
    int minute = 30,
  }) =>
      RawNotification(
        packageName: 'com.kbcard.cxh.appcard',
        title: 'KB국민카드',
        text: 'KB국민카드 ${cancel ? '승인취소' : '승인'} 홍*동 $amount원 일시불 '
            '08/05 14:$minute $merchant',
        postedAt: DateTime(2026, 8, 5, 14, minute),
      );

  StatisticsLocalDataSource stats() => StatisticsLocalDataSource(db);

  Future<List<Object?>> brands() async {
    final List<Map<String, Object?>> rows = await stats().byBrand(august, 10);
    return rows.map((Map<String, Object?> r) => r['brand']).toList();
  }

  group('취소는 통계에서 양쪽 다 빠진다', () {
    test('결제 후 취소하면 소비가 0이 된다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      expect(await stats().totalInRange(august), 30000);

      await record(payment('스타벅스', 30000, cancel: true, minute: 40));

      expect(await stats().totalInRange(august), 0);
    });

    test('취소된 가게는 "많이 간 곳" 에 나오지 않는다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('스타벅스', 30000, cancel: true, minute: 40));
      await record(payment('메가커피', 5000, minute: 50));

      final List<Map<String, Object?>> visited =
          await stats().topVisited(august, 10);

      // 예전에는 금액 0원 2건으로 남아 1위를 차지했다. 간 적이 없는 가게다.
      expect(visited.map((Map<String, Object?> r) => r['brand']),
          <String>['메가MGC커피']);
    });

    test('브랜드 통계에서도 사라진다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('스타벅스', 30000, cancel: true, minute: 40));
      await record(payment('메가커피', 5000, minute: 50));

      expect(await brands(), <String>['메가MGC커피']);
    });

    test('원결제에 취소 표시가 붙는다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('스타벅스', 30000, cancel: true, minute: 40));

      final List<Transaction> all = await transactions.findByRange(august);

      expect(all, hasLength(2));
      expect(all.every((Transaction t) => t.isCancelled), isTrue);
    });
  });

  group('거래 목록에는 그대로 남는다', () {
    test('두 줄 다 보인다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('스타벅스', 30000, cancel: true, minute: 40));

      // 통계에서 빼는 것은 "그 질문의 답이 아니라서" 이지
      // "없었던 일이라서" 가 아니다.
      expect(await transactions.findByRange(august), hasLength(2));
    });

    test('금액과 원문은 바뀌지 않는다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('스타벅스', 30000, cancel: true, minute: 40));

      final List<Transaction> all = await transactions.findByRange(august);
      final Transaction original =
          all.firstWhere((Transaction t) => t.amount > 0);
      final Transaction cancellation =
          all.firstWhere((Transaction t) => t.amount < 0);

      expect(original.amount, 30000, reason: '카드 명세와 일치해야 한다');
      expect(cancellation.amount, -30000);
      expect(original.rawNotification, contains('승인'));
    });
  });

  group('잘못 지우지 않는다', () {
    test('금액이 다르면 원결제를 건드리지 않는다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('스타벅스', 5000, cancel: true, minute: 40));

      // 5,000원 취소가 30,000원 결제를 지우면 안 된다.
      expect(await stats().totalInRange(august), 30000);
    });

    test('다른 브랜드의 결제를 건드리지 않는다', () async {
      await record(payment('스타벅스', 30000, minute: 30));
      await record(payment('메가커피', 30000, cancel: true, minute: 40));

      expect(await stats().totalInRange(august), 30000);
      expect(await brands(), <String>['스타벅스']);
    });

    test('취소보다 나중의 결제는 건드리지 않는다', () async {
      await record(payment('스타벅스', 30000, cancel: true, minute: 30));
      await record(payment('스타벅스', 30000, minute: 40));

      // 취소가 먼저 오고 그 뒤에 새로 결제한 경우다. 새 결제는 살아 있어야 한다.
      expect(await stats().totalInRange(august), 30000);
    });

    test('같은 가게에 결제가 둘이면 하나만 지운다', () async {
      await record(payment('스타벅스', 30000, minute: 10));
      await record(payment('스타벅스', 30000, minute: 20));
      await record(payment('스타벅스', 30000, cancel: true, minute: 30));

      // 두 번 결제하고 한 번 취소했다. 한 번은 남아야 한다.
      expect(await stats().totalInRange(august), 30000);
    });

    test('원결제가 없으면 아무것도 하지 않는다', () async {
      // 알림 수집을 켜기 전에 결제한 건의 취소만 들어온 경우.
      await record(payment('스타벅스', 30000, cancel: true, minute: 40));

      expect(await stats().totalInRange(august), 0);
      expect(await transactions.findByRange(august), hasLength(1));
    });
  });

  group('v11 -> v12 이관', () {
    test('이미 쌓인 취소 쌍의 원결제에도 표시가 붙는다', () async {
      await db.close();

      final Directory dir =
          await Directory.systemTemp.createTemp('cancellation_upgrade');
      final String path = '${dir.path}/budget.db';

      const int beforeVoidOriginal = 11;
      final Database old = await openDatabase(
        path,
        version: beforeVoidOriginal,
        onCreate: (Database db, int version) =>
            LegacySchema.createAt(db, beforeVoidOriginal),
      );

      // 옛 스키마에 넣어야 하므로 그 시절에 있던 컬럼만 직접 쓴다.
      // 현재 DTO 를 쓰면 나중에 추가된 컬럼까지 넣으려 해서 실패한다.
      Future<void> add(String brand, int amount, {bool cancelled = false,
          int minute = 0}) async {
        final DateTime when = DateTime(2026, 8, 5, 12, minute);
        final int now = DateTime.now().millisecondsSinceEpoch;
        await old.insert(DbSchema.tableTransactions, <String, Object?>{
          DbSchema.tMerchantRaw: brand,
          DbSchema.tBrand: brand,
          DbSchema.tAmount: amount,
          DbSchema.tCategory: '식비',
          DbSchema.tSubcategory: '카페',
          DbSchema.tPaymentMethod: 'card',
          DbSchema.tIsCancelled: cancelled ? 1 : 0,
          DbSchema.tPaymentDatetime: when.millisecondsSinceEpoch,
          DbSchema.tRawNotification: 'x',
          DbSchema.tFingerprint: '$brand|$amount|$minute',
          DbSchema.tClassificationSource: 'seed',
          DbSchema.tDirection: 'expense',
          DbSchema.tEntrySource: 'notification',
          DbSchema.tCreatedAt: now,
          DbSchema.tUpdatedAt: now,
        });
      }

      // 옛 방식: 취소 건에만 표시가 있다.
      await add('스타벅스', 30000, minute: 10);
      await add('스타벅스', -30000, cancelled: true, minute: 20);
      await add('메가커피', 5000, minute: 30);
      await old.close();

      final Database upgraded = await openDatabase(
        path,
        version: DbSchema.databaseVersion,
        onUpgrade: LegacySchema.upgrade,
      );

      // 이관이 없으면 원결제 30,000원만 남아 오히려 나빠진다.
      final int total = await StatisticsLocalDataSource(upgraded)
          .totalInRange(august);
      expect(total, 5000);

      // 거래는 셋 다 남아 있어야 한다.
      expect(
        await upgraded.query(DbSchema.tableTransactions),
        hasLength(3),
      );

      await upgraded.close();
      await dir.delete(recursive: true);

      db = await openDatabase(inMemoryDatabasePath);
    });
  });
}
