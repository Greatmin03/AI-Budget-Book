import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/statistics/data/repositories/statistics_repository_impl.dart';
import 'package:budget_book/features/statistics/domain/entities/statistics.dart';
import 'package:budget_book/features/transactions/data/models/transaction_dto.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 소비 / 저축 / 청약 / 투자 분리와 수입 통계를 검증한다.
///
/// 요구사항의 예시 숫자를 그대로 쓴다.
/// 소비 450,000 · 저축 700,000 · 청약 100,000 · 투자 300,000
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late StatisticsRepositoryImpl repo;

  final DateTime now = DateTime.now();
  late DateRange range;
  late DateTime inRange;

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
    repo = StatisticsRepositoryImpl(StatisticsLocalDataSource(db));
    // 월별 추이가 '이번 달' 을 포함해야 하므로 실제 현재 달을 쓴다.
    range = DateRange.month(now);
    inRange = DateTime(now.year, now.month, 1, 12);
  });

  tearDown(() async => db.close());

  Future<void> insert({
    required int amount,
    TransactionDirection direction = TransactionDirection.expense,
    bool isAssetTransfer = false,
    AssetKind? kind,
    String category = '식비',
    String subcategory = '카페',
    String brand = '테스트',
  }) async {
    final Transaction tx = Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      category: category,
      subcategory: subcategory,
      method: PaymentMethodKind.card,
      paymentDatetime: inRange,
      rawNotification: 'test',
      fingerprint: '$brand|$amount|$category|$subcategory|$direction'
          '|${kind?.code}|${DateTime.now().microsecondsSinceEpoch}',
      classificationSource: ClassificationSource.seed,
      direction: direction,
      isAssetTransfer: isAssetTransfer,
      assetKind: kind?.code,
    );
    await db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  group('소비 / 저축 / 청약 / 투자', () {
    test('요구사항 예시대로 네 갈래로 나뉜다', () async {
      await insert(amount: 450000);
      await insert(
        amount: 700000,
        isAssetTransfer: true,
        kind: AssetKind.saving,
      );
      await insert(
        amount: 100000,
        isAssetTransfer: true,
        kind: AssetKind.housing,
      );
      await insert(
        amount: 300000,
        isAssetTransfer: true,
        kind: AssetKind.investment,
      );

      final PeriodStatistics stats = await repo.statistics(range);
      final FlowBreakdown flow = stats.flow;

      expect(flow.spending, 450000);
      expect(flow.saving, 700000);
      expect(flow.housing, 100000);
      expect(flow.investment, 300000);
      expect(flow.keptAsAssets, 1100000);
      expect(flow.totalOutflow, 1550000);
    });

    test('소비 통계 총액에는 저축·청약·투자가 들어가지 않는다', () async {
      await insert(amount: 450000);
      await insert(
        amount: 700000,
        isAssetTransfer: true,
        kind: AssetKind.saving,
      );

      final PeriodStatistics stats = await repo.statistics(range);

      expect(stats.total, 450000, reason: '"이번 달 얼마 썼나" 는 소비만이다');
      expect(stats.byCategory.fold<int>(0, (int s, CategoryAmount c) => s + c.amount),
          450000);
    });

    test('저축률을 계산한다', () async {
      await insert(amount: 500000);
      await insert(
        amount: 500000,
        isAssetTransfer: true,
        kind: AssetKind.saving,
      );

      final FlowBreakdown flow = (await repo.statistics(range)).flow;
      expect(flow.savingRate, 50.0);
    });

    test('자산 이동이 없으면 저축 관련 값이 모두 0이다', () async {
      await insert(amount: 10000);

      final FlowBreakdown flow = (await repo.statistics(range)).flow;
      expect(flow.hasAssetTransfers, isFalse);
      expect(flow.keptAsAssets, 0);
      expect(flow.totalOutflow, 10000);
    });

    test('종류를 지정하지 않은 자산 이동은 기타로 잡힌다', () async {
      await insert(amount: 200000, isAssetTransfer: true);

      final FlowBreakdown flow = (await repo.statistics(range)).flow;
      expect(flow.otherAssetTransfer, 200000);
      expect(flow.saving, 0);
      expect(flow.keptAsAssets, 200000);
    });
  });

  group('수입 통계', () {
    test('수입 카테고리별로 집계한다', () async {
      await insert(
        amount: 2000000,
        direction: TransactionDirection.income,
        category: '급여',
        subcategory: '월급',
        brand: '회사',
      );
      await insert(
        amount: 300000,
        direction: TransactionDirection.income,
        category: '장학금',
        subcategory: '장학금',
        brand: '학교',
      );
      await insert(
        amount: 100000,
        direction: TransactionDirection.income,
        category: '용돈',
        subcategory: '용돈',
        brand: '부모님',
      );
      await insert(amount: 15000); // 지출

      final IncomeStatistics income = (await repo.statistics(range)).income;

      expect(income.total, 2400000);
      expect(income.count, 3);

      final Map<String, int> byName = <String, int>{
        for (final CategoryAmount c in income.byCategory) c.name: c.amount,
      };
      expect(byName['급여'], 2000000);
      expect(byName['장학금'], 300000);
      expect(byName['용돈'], 100000);
      expect(byName.containsKey('식비'), isFalse, reason: '지출이 섞이면 안 된다');
    });

    test('월별 수입 추이를 만든다', () async {
      await insert(
        amount: 2000000,
        direction: TransactionDirection.income,
        category: '급여',
        subcategory: '월급',
      );

      final IncomeStatistics income =
          (await repo.statistics(range, trendMonths: 3)).income;

      expect(income.trend.length, 3);
      // 마지막 항목이 이번 달이다.
      expect(income.trend.last.amount, 2000000);
    });

    test('수입이 없으면 비어 있다', () async {
      await insert(amount: 15000);

      final IncomeStatistics income = (await repo.statistics(range)).income;
      expect(income.isEmpty, isTrue);
      expect(income.total, 0);
    });

    test('수입만 있어도 통계가 비어 있지 않다', () async {
      await insert(
        amount: 500000,
        direction: TransactionDirection.income,
        category: '급여',
        subcategory: '월급',
      );

      final PeriodStatistics stats = await repo.statistics(range);
      expect(stats.transactionCount, 0, reason: '소비 건수는 0');
      expect(stats.isEmpty, isFalse, reason: '수입이 있으므로 화면은 비어 있지 않다');
    });
  });

  group('수입 분류 체계', () {
    test('지출 카테고리와 수입 카테고리는 서로 섞이지 않는다', () async {
      expect(CategoryTaxonomy.incomeCategories, contains('급여'));
      expect(CategoryTaxonomy.categories, isNot(contains('급여')));
      expect(CategoryTaxonomy.incomeCategories, isNot(contains('식비')));
    });

    test('방향에 맞는 목록을 준다', () {
      expect(
        CategoryTaxonomy.categoriesFor(isIncome: true),
        CategoryTaxonomy.incomeCategories,
      );
      expect(
        CategoryTaxonomy.categoriesFor(isIncome: false),
        CategoryTaxonomy.categories,
      );
    });

    test('수입 분류를 보정한다', () {
      expect(
        CategoryTaxonomy.coerceIncome('급여', '월급'),
        const CategoryPair('급여', '월급'),
      );
      // 카테고리는 맞고 세부항목만 틀리면 그 카테고리의 기타로 내린다.
      expect(
        CategoryTaxonomy.coerceIncome('급여', '없는항목'),
        const CategoryPair('급여', '기타'),
      );
      // 지출 카테고리를 수입으로 보정하면 기타/미분류.
      expect(
        CategoryTaxonomy.coerceIncome('식비', '카페'),
        const CategoryPair('기타', '미분류'),
      );
    });

    test('지출을 수입으로 바꿀 때 분류가 안전하게 보정된다', () {
      // 수정 시트가 방향을 바꿀 때 쓰는 경로다.
      final CategoryPair fixed = CategoryTaxonomy.coerceFor(
        '식비',
        '카페',
        isIncome: true,
      );
      expect(fixed.category, '기타');
      expect(
        CategoryTaxonomy.incomeTree.containsKey(fixed.category),
        isTrue,
        reason: '보정 결과는 항상 수입 체계 안에 있어야 한다',
      );
    });
  });
}
