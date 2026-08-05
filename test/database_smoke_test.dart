import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/insights/data/repositories/insight_repository_impl.dart';
import 'package:budget_book/features/insights/domain/entities/insight_facts.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/projects/data/repositories/project_repository_impl.dart';
import 'package:budget_book/features/projects/domain/entities/project.dart';
import 'package:budget_book/features/statistics/data/datasources/analytics_local_datasource.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/data/models/transaction_dto.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 실제 SQLite 로 스키마와 집계 쿼리를 검증한다.
///
/// 이 앱의 통계는 대부분 손으로 쓴 SQL 문자열이다. 위젯 테스트로는 닿지 않고
/// 기기에서만 실행되므로 오래 검증되지 않은 영역이었다.
/// 여기서 메모리 DB 를 띄워 **쿼리가 실제로 실행되는지**와
/// **정산 차감 / 자산이동·수입 제외**가 맞는지 확인한다.
void main() {
  // 데스크톱에서 SQLite 를 구동한다(앱은 Android 기본 구현을 쓴다).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

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
  });

  tearDown(() async => db.close());

  /// 거래 한 건 삽입. DTO 를 그대로 써서 컬럼 매핑까지 함께 검증한다.
  Future<int> insertTransaction({
    required int amount,
    required DateTime at,
    String brand = '스타벅스',
    String category = '식비',
    String subcategory = '카페',
    bool isAssetTransfer = false,
    TransactionDirection direction = TransactionDirection.expense,
    int? projectId,
    String fingerprint = '',
  }) {
    final Transaction tx = Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      category: category,
      subcategory: subcategory,
      method: PaymentMethodKind.card,
      paymentDatetime: at,
      rawNotification: 'test',
      fingerprint: fingerprint.isEmpty
          ? '$brand|$amount|${at.microsecondsSinceEpoch}'
          : fingerprint,
      classificationSource: ClassificationSource.seed,
      isAssetTransfer: isAssetTransfer,
      direction: direction,
      projectId: projectId,
    );
    return db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  Future<void> insertSettlement({
    required int transactionId,
    required int amount,
  }) async {
    await db.insert(DbSchema.tableSettlements, <String, Object?>{
      DbSchema.stTransactionId: transactionId,
      DbSchema.stCounterparty: '김철수',
      DbSchema.stAmount: amount,
      DbSchema.stSettledAt: DateTime.now().millisecondsSinceEpoch,
      DbSchema.stCreatedAt: DateTime.now().millisecondsSinceEpoch,
    });
  }

  group('스키마', () {
    test('모든 CREATE 문이 실행된다', () async {
      final List<Map<String, Object?>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final List<String> names = tables
          .map((Map<String, Object?> r) => r['name'] as String)
          .toList();

      // 현재 스키마의 전체 테이블.
      expect(
        names,
        containsAll(<String>[
          DbSchema.tableTransactions,
          DbSchema.tableMerchants,
          DbSchema.tableBrandRules,
          DbSchema.tableSettlements,
          DbSchema.tableDeposits,
          DbSchema.tableRecurringRules,
          DbSchema.tableAssetTransfers,
          DbSchema.tableProjects,
          DbSchema.tableAccounts,
          DbSchema.tableAccountSnapshots,
          DbSchema.tableSettings,
          DbSchema.tableIngestFailures,
        ]),
      );
    });

    test('중복 fingerprint 는 저장되지 않는다', () async {
      final DateTime at = DateTime(2026, 8, 4, 12);
      final int first = await insertTransaction(
        amount: 6200,
        at: at,
        fingerprint: 'dup',
      );
      expect(first, greaterThan(0));

      final int second = await db.insert(
        DbSchema.tableTransactions,
        TransactionDto.toRow(
          Transaction(
            merchantRaw: '스타벅스',
            brand: '스타벅스',
            amount: 6200,
            category: '식비',
            subcategory: '카페',
            method: PaymentMethodKind.card,
            paymentDatetime: at,
            rawNotification: 'test',
            fingerprint: 'dup',
            classificationSource: ClassificationSource.seed,
          ),
          now: DateTime.now(),
        ),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      expect(second, 0, reason: '중복은 무시되어야 한다');
    });
  });

  group('통계 쿼리 (정산 차감 · 자산이동/수입 제외)', () {
    late StatisticsLocalDataSource stats;
    late DateRange august;

    setUp(() {
      stats = StatisticsLocalDataSource(db);
      august = DateRange.ofYearMonth(2026, 8);
    });

    test('총액은 실제 부담(정산 차감) 기준이다', () async {
      final int id = await insertTransaction(
        amount: 30000,
        at: DateTime(2026, 8, 4, 12),
      );
      await insertSettlement(transactionId: id, amount: 20000);

      expect(await stats.totalInRange(august), 10000);
      expect(
        await stats.grossTotalInRange(august),
        30000,
        reason: '원본 결제 합계는 그대로',
      );
    });

    test('자산 이동은 소비에서 제외되고 현금 흐름에는 포함된다', () async {
      await insertTransaction(amount: 6200, at: DateTime(2026, 8, 1, 12));
      await insertTransaction(
        amount: 500000,
        at: DateTime(2026, 8, 2, 12),
        brand: '청년미래적금',
        isAssetTransfer: true,
      );

      // 소비 통계: 적금 제외
      expect(await stats.totalInRange(august), 6200);
      expect(await stats.countInRange(august), 1);

      // 현금 흐름: 적금 포함
      expect(await stats.cashOutflowInRange(august), 506200);
      expect(await stats.assetTransferTotalInRange(august), 500000);
    });

    test('수입은 소비 통계에서 제외된다', () async {
      await insertTransaction(amount: 10000, at: DateTime(2026, 8, 2, 12));
      await insertTransaction(
        amount: 3000000,
        at: DateTime(2026, 8, 3, 12),
        brand: '급여',
        direction: TransactionDirection.income,
      );

      expect(await stats.totalInRange(august), 10000);
      expect(await stats.countInRange(august), 1);
    });

    test('카테고리/서브카테고리/브랜드 집계가 실행된다', () async {
      await insertTransaction(amount: 6200, at: DateTime(2026, 8, 1, 12));
      await insertTransaction(
        amount: 12000,
        at: DateTime(2026, 8, 2, 12),
        brand: '배달의민족',
        subcategory: '배달',
      );

      final List<Map<String, Object?>> byCategory =
          await stats.byCategory(august);
      expect(byCategory.first['name'], '식비');
      expect(byCategory.first['amount'], 18200);

      expect((await stats.bySubcategory(august)).length, 2);
      expect((await stats.byBrand(august, 10)).length, 2);
      expect((await stats.topVisited(august, 5)).length, 2);

      final Map<String, Object?> cafe =
          await stats.subcategoryTotal(august, '카페');
      expect(cafe['amount'], 6200);
      expect(cafe['cnt'], 1);

      expect((await stats.paymentTimesInRange(august)).length, 2);
    });

    test('기간 밖 거래는 잡히지 않는다', () async {
      await insertTransaction(amount: 5000, at: DateTime(2026, 7, 31, 23, 59));
      await insertTransaction(amount: 7000, at: DateTime(2026, 9, 1));

      expect(await stats.totalInRange(august), 0);
    });
  });

  group('드릴다운 쿼리', () {
    late AnalyticsLocalDataSource analytics;
    late DateRange august;

    setUp(() async {
      analytics = AnalyticsLocalDataSource(db);
      august = DateRange.ofYearMonth(2026, 8);
      await insertTransaction(amount: 6200, at: DateTime(2026, 8, 1, 12));
      await insertTransaction(amount: 5500, at: DateTime(2026, 8, 3, 12));
      await insertTransaction(
        amount: 12000,
        at: DateTime(2026, 8, 2, 12),
        brand: '배달의민족',
        subcategory: '배달',
      );
    });

    test('브랜드 집계 + 정렬 4종이 모두 실행된다', () async {
      for (final String orderBy in <String>[
        'amount DESC',
        'cnt DESC, amount DESC',
        'avg_amount DESC',
        'last_at DESC',
      ]) {
        final List<Map<String, Object?>> rows = await analytics.brandStats(
          range: august,
          orderBy: orderBy,
          limit: 10,
        );
        expect(rows, isNotEmpty, reason: orderBy);
      }
    });

    test('브랜드 상세 · 지점 · LEFT JOIN 이 실행된다', () async {
      final Map<String, Object?> total =
          await analytics.brandTotal(range: august, brand: '스타벅스');
      expect(total['amount'], 11700);
      expect(total['cnt'], 2);

      final List<Map<String, Object?>> txs = await analytics.brandTransactions(
        range: august,
        brand: '스타벅스',
        limit: 50,
      );
      expect(txs.length, 2);
      // merchants LEFT JOIN + 정산 합계 별칭이 함께 나온다.
      expect(txs.first.containsKey('merchant_branch'), isTrue);
      expect(
        txs.first.containsKey(TransactionDto.settledAmountColumn),
        isTrue,
      );
      // DTO 변환까지 통과해야 한다.
      expect(TransactionDto.fromRow(txs.first).brand, '스타벅스');

      expect(
        (await analytics.brandBranches(range: august, brand: '스타벅스')).length,
        1,
      );
    });

    test('카테고리 상세 쿼리', () async {
      expect(
        (await analytics.categoryTotal(range: august, category: '식비'))['cnt'],
        3,
      );
      expect(
        (await analytics.categoryTotal(
          range: august,
          category: '식비',
          subcategory: '카페',
        ))['cnt'],
        2,
      );
      expect(
        (await analytics.brandsInCategory(range: august, category: '식비'))
            .length,
        2,
      );
      expect(
        (await analytics.subcategoriesOfCategory(range: august, category: '식비'))
            .length,
        2,
      );
      expect(
        await analytics.categoryAmountInRange(range: august, category: '식비'),
        23700,
      );
      expect(
        await analytics.brandAmountInRange(range: august, brand: '스타벅스'),
        11700,
      );
    });

    test('검색은 LIKE 와일드카드를 이스케이프한다', () async {
      expect(
        (await analytics.searchBrands(range: august, query: '스타', limit: 10))
            .length,
        1,
      );
      // `%` 를 그대로 넘기면 전체 일치가 되어 버린다. 이스케이프되어야 0건.
      expect(
        (await analytics.searchBrands(range: august, query: '%', limit: 10)),
        isEmpty,
      );
      expect(AnalyticsLocalDataSource.escapeLike('100%'), '100\\%');
    });

    test('상위 카테고리/브랜드 1건 조회', () async {
      expect((await analytics.topCategory(august))!['name'], '식비');
      expect((await analytics.topVisitedBrand(august))!['brand'], '스타벅스');
      expect(
        (await analytics.brandPrimaryCategories(august)),
        isNotEmpty,
      );
      expect((await analytics.categorySubcategoryTotals(august)).length, 2);
    });
  });

  group('사실 계산 레이어', () {
    test('두 기간을 비교해 ItemFact 를 만든다', () async {
      // 7월: 카페 1회 4,000원 / 8월: 카페 2회 11,700원
      await insertTransaction(amount: 4000, at: DateTime(2026, 7, 10, 12));
      await insertTransaction(amount: 6200, at: DateTime(2026, 8, 1, 12));
      await insertTransaction(amount: 5500, at: DateTime(2026, 8, 3, 12));

      final InsightFacts facts = await InsightRepositoryImpl(db)
          .facts(DateRange.ofYearMonth(2026, 8));

      expect(facts.total, 11700);
      expect(facts.previousTotal, 4000);
      expect(facts.transactionCount, 2);

      final ItemFact cafe =
          facts.subcategories.firstWhere((ItemFact f) => f.name == '카페');
      expect(cafe.amount, 11700);
      expect(cafe.count, 2);
      expect(cafe.previousAmount, 4000);
      expect(cafe.increased, isTrue);

      // 브랜드 사실에는 상위(서브카테고리)가 붙는다.
      final ItemFact brand =
          facts.brands.firstWhere((ItemFact f) => f.name == '스타벅스');
      expect(brand.parent, '카페');

      // 절약 시뮬레이션이 실제 데이터로 동작한다.
      final SavingScenario? s =
          facts.simulateReduction(target: '스타벅스', reduceBy: 1);
      expect(s!.averageAmount, 5850);
      expect(s.savedPerMonth, 5850);
    });

    test('자산 이동과 수입은 사실 계산에서도 빠진다', () async {
      await insertTransaction(amount: 6200, at: DateTime(2026, 8, 1, 12));
      await insertTransaction(
        amount: 500000,
        at: DateTime(2026, 8, 2, 12),
        brand: '청년미래적금',
        isAssetTransfer: true,
      );
      await insertTransaction(
        amount: 3000000,
        at: DateTime(2026, 8, 3, 12),
        brand: '급여',
        direction: TransactionDirection.income,
      );

      final InsightFacts facts = await InsightRepositoryImpl(db)
          .facts(DateRange.ofYearMonth(2026, 8));

      expect(facts.total, 6200);
      expect(facts.transactionCount, 1);
      expect(facts.brands.length, 1);
    });
  });

  group('프로젝트', () {
    test('생성 → 거래 연결 → 집계 → 삭제 시 거래 유지', () async {
      final ProjectRepositoryImpl repo = ProjectRepositoryImpl(db);

      final Project saved = await repo.save(const Project(name: '일본 여행'));
      expect(saved.id, isNotNull);

      final int txId = await insertTransaction(
        amount: 320000,
        at: DateTime(2026, 8, 4, 12),
        brand: '호텔',
        category: '문화/여가',
        subcategory: '숙박',
        projectId: saved.id,
      );
      await insertTransaction(
        amount: 180000,
        at: DateTime(2026, 8, 5, 12),
        projectId: saved.id,
      );
      // 프로젝트에 속하지 않은 거래는 집계에서 빠진다.
      await insertTransaction(amount: 9999, at: DateTime(2026, 8, 6, 12));

      final ProjectDetail detail = await repo.detail(saved.id!);
      expect(detail.total, 500000);
      expect(detail.transactionCount, 2);
      expect(detail.byCategory.length, 2);
      expect(detail.byBrand.length, 2);

      expect((await repo.transactionsOf(saved.id!)).length, 2);
      expect((await repo.findAll()).first.total, 500000);

      // 연결 해제
      await repo.assign(transactionId: txId, projectId: null);
      expect((await repo.detail(saved.id!)).transactionCount, 1);

      // 프로젝트를 지워도 거래는 남는다(ON DELETE SET NULL).
      await repo.delete(saved.id!);
      final int remaining = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${DbSchema.tableTransactions}',
      )).first['c']! as int;
      expect(remaining, 3);
    });
  });
}
