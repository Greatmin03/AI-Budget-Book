import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/database/seed/brand_seed.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/merchants/domain/entities/merchant.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/features/transactions/domain/usecases/normalize_existing_brands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 이미 저장된 거래의 브랜드를 지금의 사전 기준으로 다시 맞춘다.
///
/// 이 작업은 **사용자의 실제 가계부를 고친다.** 그래서 확인하는 것은 두 가지다.
///  - 갈라진 브랜드가 실제로 합쳐지는가
///  - 건드리면 안 되는 것(원본, 사용자가 가르친 값)을 건드리지 않는가
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
  late MerchantRepositoryImpl merchants;
  late NormalizeExistingBrands normalize;

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
    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
    merchants = MerchantRepositoryImpl(MerchantLocalDataSource(db));
    normalize = NormalizeExistingBrands(
      transactions: transactions,
      merchants: merchants,
    );
  });

  tearDown(() async => db.close());

  int seq = 0;

  /// 옛 버전이 저장했던 형태의 거래. 브랜드가 정규화되지 않은 채로 들어간다.
  Future<void> insert({
    required String merchantRaw,
    required String brand,
    int amount = 3000,
  }) async {
    final DateTime when = DateTime(2026, 8, 5, 12, seq++);
    await transactions.insert(
      Transaction(
        merchantRaw: merchantRaw,
        brand: brand,
        amount: amount,
        category: '생활',
        subcategory: '편의점',
        method: PaymentMethodKind.card,
        paymentDatetime: when,
        rawNotification: 'test',
        fingerprint: '$merchantRaw|$amount|${when.microsecondsSinceEpoch}',
        classificationSource: ClassificationSource.user,
      ),
    );
  }

  Future<List<Object?>> brandRows() async {
    final List<Map<String, Object?>> rows = await StatisticsLocalDataSource(db)
        .byBrand(DateRange.month(DateTime(2026, 8, 5)), 10);
    return rows.map((Map<String, Object?> r) => r['brand']).toList();
  }

  group('갈라진 브랜드 합치기', () {
    test('직접 입력한 "씨유" 가 CU 로 합쳐진다', () async {
      await insert(merchantRaw: '씨유강원대제3학생', brand: 'CU');
      await insert(merchantRaw: '씨유', brand: '씨유');

      expect(await brandRows(), unorderedEquals(<String>['CU', '씨유']),
          reason: '고치기 전');

      final BrandNormalizationResult result = await normalize();

      expect(result.brandCount, 1);
      expect(result.transactionsUpdated, 1);
      expect(await brandRows(), <String>['CU']);
    });

    test('같은 브랜드의 여러 거래가 한 번에 바뀐다', () async {
      await insert(merchantRaw: '씨유', brand: '씨유');
      await insert(merchantRaw: '씨유', brand: '씨유');
      await insert(merchantRaw: '씨유', brand: '씨유');

      final BrandNormalizationResult result = await normalize();

      // 사전 조회는 조합당 한 번, 갱신은 세 건.
      expect(result.brandCount, 1);
      expect(result.transactionsUpdated, 3);
    });

    test('원본 거래명은 바뀌지 않는다', () async {
      await insert(merchantRaw: '씨유', brand: '씨유');

      await normalize();

      final Map<String, Object?> row = (await db.query(
        DbSchema.tableTransactions,
        columns: <String>[DbSchema.tBrand, DbSchema.tMerchantRaw],
      ))
          .single;
      expect(row[DbSchema.tBrand], 'CU');
      // 근거가 남아야 사전이 또 바뀌었을 때 다시 돌릴 수 있다.
      expect(row[DbSchema.tMerchantRaw], '씨유');
    });
  });

  group('건드리지 않는 것', () {
    test('사전이 모르는 이름은 그대로 둔다', () async {
      await insert(merchantRaw: '학식', brand: '학식');
      await insert(merchantRaw: '동네반찬가게', brand: '동네반찬가게');

      final BrandNormalizationResult result = await normalize();

      expect(result.isEmpty, isTrue);
      expect(await brandRows(), unorderedEquals(<String>['학식', '동네반찬가게']));
    });

    test('사용자가 가르친 가맹점이 사전을 이긴다', () async {
      // 사용자가 이 가게를 "우리 편의점" 이라고 직접 고쳤다.
      await merchants.save(
        const Merchant.unsaved(
          brand: '우리 편의점',
          merchantName: '씨유강원대제3학생',
          normalizedName: '씨유강원대제3학생',
          category: '생활',
          subcategory: '편의점',
          source: ClassificationSource.user,
          confidence: 1,
        ),
      );
      await insert(merchantRaw: '씨유강원대제3학생', brand: '우리 편의점');

      final BrandNormalizationResult result = await normalize();

      // 일괄 작업이 사용자의 선택을 되돌리면 안 된다.
      expect(result.isEmpty, isTrue);
      expect(await brandRows(), <String>['우리 편의점']);
    });

    test('이미 정규화된 거래는 다시 쓰지 않는다', () async {
      await insert(merchantRaw: '씨유강원대제3학생', brand: 'CU');

      final BrandNormalizationResult result = await normalize();

      expect(result.transactionsUpdated, 0);
    });
  });

  group('안전장치', () {
    test('preview 는 아무것도 바꾸지 않는다', () async {
      await insert(merchantRaw: '씨유', brand: '씨유');

      final BrandNormalizationResult preview = await normalize.preview();

      expect(preview.transactionsUpdated, 1, reason: '바뀔 건수는 알려 준다');
      // 실제 가계부는 그대로여야 한다. 사용자가 보고 결정한다.
      expect(await brandRows(), <String>['씨유']);
    });

    test('두 번 돌려도 결과가 같다', () async {
      await insert(merchantRaw: '씨유', brand: '씨유');

      final BrandNormalizationResult first = await normalize();
      final BrandNormalizationResult second = await normalize();

      expect(first.transactionsUpdated, 1);
      expect(second.isEmpty, isTrue, reason: '두 번째는 바꿀 것이 없다');
      expect(await brandRows(), <String>['CU']);
    });
  });
}
