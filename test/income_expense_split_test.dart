import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/projects/data/repositories/project_repository_impl.dart';
import 'package:budget_book/features/projects/domain/entities/project.dart';
import 'package:budget_book/features/recurring/domain/services/recurring_detector.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/data/models/transaction_dto.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 수입과 지출이 하나로 합산되던 버그를 고정한다.
///
/// 사용자가 보고한 증상: 수입 300,000원 + 지출 15,000원이 **315,000원**으로
/// 표시됨. 수입도 양수로 저장되고(`direction` 으로만 구분한다) 현금 흐름
/// 쿼리에 방향 조건이 없었기 때문이다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late StatisticsLocalDataSource stats;

  /// 이번 달 전체를 덮는 기간.
  final DateRange range = DateRange.month(DateTime(2026, 8, 15));
  final DateTime inRange = DateTime(2026, 8, 10, 12);

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
    stats = StatisticsLocalDataSource(db);
  });

  tearDown(() async => db.close());

  Future<int> insert({
    required int amount,
    TransactionDirection direction = TransactionDirection.expense,
    bool isAssetTransfer = false,
    String? assetKind,
    String brand = '테스트',
    String category = '식비',
    String subcategory = '카페',
    DateTime? at,
  }) {
    final DateTime when = at ?? inRange;
    final Transaction tx = Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      category: category,
      subcategory: subcategory,
      method: PaymentMethodKind.card,
      paymentDatetime: when,
      rawNotification: 'test',
      fingerprint: '$brand|$amount|${when.microsecondsSinceEpoch}|$direction',
      classificationSource: ClassificationSource.seed,
      direction: direction,
      isAssetTransfer: isAssetTransfer,
      assetKind: assetKind,
    );
    return db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  Future<int> insertInProject({
    required int amount,
    required int projectId,
    TransactionDirection direction = TransactionDirection.expense,
  }) {
    final Transaction tx = Transaction(
      merchantRaw: '프로젝트거래',
      brand: '프로젝트거래',
      amount: amount,
      category: direction.isIncome ? '용돈' : '식비',
      subcategory: direction.isIncome ? '용돈' : '카페',
      method: PaymentMethodKind.card,
      paymentDatetime: inRange,
      rawNotification: 'test',
      fingerprint: 'proj|$amount|$direction|$projectId',
      classificationSource: ClassificationSource.seed,
      direction: direction,
      projectId: projectId,
    );
    return db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  group('수입 / 지출 분리', () {
    test('요구사항 예시: 수입 300,000 + 지출 15,000', () async {
      await insert(amount: 300000, direction: TransactionDirection.income);
      await insert(amount: 15000);

      expect(await stats.incomeTotalInRange(range), 300000, reason: '수입');
      expect(await stats.totalInRange(range), 15000, reason: '지출(소비)');
      expect(
        await stats.cashOutflowInRange(range),
        15000,
        reason: '315,000원이 되면 버그가 되살아난 것이다',
      );
    });

    test('순증가는 수입 - 지출이다', () async {
      await insert(amount: 300000, direction: TransactionDirection.income);
      await insert(amount: 15000);

      final int income = await stats.incomeTotalInRange(range);
      final int expense = await stats.totalInRange(range);

      expect(income - expense, 285000);
    });

    test('수입은 소비 통계에 들어가지 않는다', () async {
      await insert(amount: 500000, direction: TransactionDirection.income);

      expect(await stats.totalInRange(range), 0);
      expect(await stats.countInRange(range), 0);
      expect(await stats.cashOutflowInRange(range), 0);
      expect(await stats.grossTotalInRange(range), 0);
    });

    test('수입은 카테고리/브랜드 순위에도 섞이지 않는다', () async {
      await insert(
        amount: 3000000,
        direction: TransactionDirection.income,
        brand: '회사',
        category: '기타',
        subcategory: '미분류',
      );
      await insert(amount: 5000, brand: '스타벅스');

      final List<Map<String, Object?>> byCategory =
          await stats.byCategory(range);
      final List<Map<String, Object?>> byBrand = await stats.byBrand(range, 10);

      expect(byCategory.length, 1);
      expect(byCategory.single['name'], '식비');
      expect(byBrand.single['brand'], '스타벅스');
    });

    test('수입 건수와 카테고리별 수입을 따로 집계한다', () async {
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
      await insert(amount: 5000);

      expect(await stats.incomeCountInRange(range), 2);
      expect(await stats.incomeTotalInRange(range), 2300000);

      // 수입 카테고리(급여/장학금)로 나뉜다. 지출 카테고리는 섞이지 않는다.
      final Map<String, int> byName = <String, int>{
        for (final Map<String, Object?> row
            in await stats.incomeByCategory(range))
          row['name'] as String: row['amount'] as int,
      };
      expect(byName['급여'], 2000000);
      expect(byName['장학금'], 300000);
      expect(byName.containsKey('식비'), isFalse);
    });

    test('자산 이동은 지출에 포함되고 소비에서는 빠진다', () async {
      await insert(amount: 10000); // 소비
      await insert(
        amount: 500000,
        isAssetTransfer: true,
        assetKind: 'saving',
        category: '금융',
        subcategory: '기타',
      );

      expect(await stats.totalInRange(range), 10000, reason: '소비');
      expect(
        await stats.cashOutflowInRange(range),
        510000,
        reason: '통장에서는 나갔다',
      );
      expect(await stats.assetTransferTotalInRange(range), 500000);
    });

    test('수입이 자산 이동 합계를 오염시키지 않는다', () async {
      await insert(amount: 1000000, direction: TransactionDirection.income);
      await insert(amount: 500000, isAssetTransfer: true, assetKind: 'saving');

      expect(await stats.assetTransferTotalInRange(range), 500000);
    });

    test('취소 거래(음수)는 지출에서 차감된다', () async {
      await insert(amount: 30000);
      await insert(amount: -30000);

      expect(await stats.totalInRange(range), 0);
      expect(await stats.cashOutflowInRange(range), 0);
    });

    test('기간 밖의 수입은 집계되지 않는다', () async {
      await insert(
        amount: 999999,
        direction: TransactionDirection.income,
        at: DateTime(2026, 7, 31, 23, 59),
      );

      expect(await stats.incomeTotalInRange(range), 0);
    });
  });

  group('자산 이동 종류별 분리', () {
    test('저축 / 청약 / 투자를 나눠서 집계한다', () async {
      await insert(amount: 700000, isAssetTransfer: true, assetKind: 'saving');
      await insert(amount: 100000, isAssetTransfer: true, assetKind: 'housing');
      await insert(
        amount: 300000,
        isAssetTransfer: true,
        assetKind: 'investment',
      );
      await insert(amount: 450000); // 소비

      final Map<String, int> byKind = <String, int>{
        for (final Map<String, Object?> row
            in await stats.assetTransfersByKind(range))
          row['kind'] as String: row['amount'] as int,
      };

      expect(byKind['saving'], 700000);
      expect(byKind['housing'], 100000);
      expect(byKind['investment'], 300000);
      expect(await stats.totalInRange(range), 450000, reason: '소비만');
    });

    test('종류가 없는 예전 자산 이동은 other 로 묶인다', () async {
      await insert(amount: 200000, isAssetTransfer: true);

      final List<Map<String, Object?>> rows =
          await stats.assetTransfersByKind(range);
      expect(rows.single['kind'], 'other');
      expect(rows.single['amount'], 200000);
    });
  });
  group('수입이 다른 기능으로 새지 않는다', () {
    test('월급은 정기결제 후보가 되지 않는다', () async {
      // 매달 같은 날 같은 금액이 들어오는 월급은 이 앱에서 가장 규칙적인
      // 데이터다. 막지 않으면 "회사 2,000,000원 매달 결제 예정" 이 뜬다.
      final List<Transaction> monthlySalary = <Transaction>[
        for (int m = 3; m <= 8; m++)
          Transaction(
            merchantRaw: '회사',
            brand: '회사',
            amount: 2000000,
            category: '급여',
            subcategory: '월급',
            method: PaymentMethodKind.unknown,
            paymentDatetime: DateTime(2026, m, 25, 10),
            rawNotification: 'test',
            fingerprint: 'salary|$m',
            classificationSource: ClassificationSource.user,
            direction: TransactionDirection.income,
            entrySource: EntrySource.manual,
          ),
      ];

      const RecurringDetector detector = RecurringDetector();
      final List<RecurringCandidate> candidates =
          detector.detect(monthlySalary);

      expect(candidates, isEmpty, reason: '수입은 정기결제가 아니다');
    });

    test('같은 조건의 지출은 정기결제 후보가 된다 (대조군)', () async {
      // 위 테스트가 "감지기가 아무것도 못 찾는다" 때문에 통과하는 게 아님을
      // 확인한다.
      final List<Transaction> monthlySubscription = <Transaction>[
        for (int m = 3; m <= 8; m++)
          Transaction(
            merchantRaw: '넷플릭스',
            brand: '넷플릭스',
            amount: 17000,
            category: '문화/여가',
            subcategory: '기타',
            method: PaymentMethodKind.card,
            paymentDatetime: DateTime(2026, m, 25, 10),
            rawNotification: 'test',
            fingerprint: 'netflix|$m',
            classificationSource: ClassificationSource.seed,
          ),
      ];

      const RecurringDetector detector = RecurringDetector();
      expect(detector.detect(monthlySubscription), isNotEmpty);
    });

    test('프로젝트 건수와 합계가 같은 기준을 쓴다', () async {
      final int projectId = await db.insert(
        DbSchema.tableProjects,
        <String, Object?>{
          DbSchema.pjName: '제주 여행',
          DbSchema.pjIsArchived: 0,
          DbSchema.pjCreatedAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
          DbSchema.pjUpdatedAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
        },
      );

      await insertInProject(
        amount: 100000,
        projectId: projectId,
      );
      // 여행 중 받은 용돈. 지출이 아니다.
      await insertInProject(
        amount: 50000,
        projectId: projectId,
        direction: TransactionDirection.income,
      );

      final ProjectRepositoryImpl projects = ProjectRepositoryImpl(db);
      final List<ProjectSummary> all = await projects.findAll();

      expect(all.single.total, 100000, reason: '수입은 합계에서 빠진다');
      expect(
        all.single.transactionCount,
        1,
        reason: '건수도 같은 기준이어야 한다 (2건이면 합계와 어긋난다)',
      );
    });
    test('수입은 정산 후보로 뜨지 않는다', () async {
      // 정산은 "내가 대신 낸 지출" 을 나눠 받는 것이다.
      // 월급에 입금을 붙이면 net 이 깎여 통계가 틀어진다.
      await insert(
        amount: 30000,
        direction: TransactionDirection.income,
        brand: '용돈',
        category: '용돈',
        subcategory: '용돈',
      );

      final TransactionRepositoryImpl repo =
          TransactionRepositoryImpl(TransactionLocalDataSource(db));
      final List<Transaction> candidates = await repo.findSettlementCandidates(
        depositAmount: 30000,
        from: inRange.subtract(const Duration(days: 7)),
        to: inRange.add(const Duration(days: 1)),
      );

      expect(candidates, isEmpty);
    });

    test('자산 이동도 정산 후보가 아니다', () async {
      await insert(amount: 30000, isAssetTransfer: true, assetKind: 'saving');

      final TransactionRepositoryImpl repo =
          TransactionRepositoryImpl(TransactionLocalDataSource(db));
      expect(
        await repo.findSettlementCandidates(
          depositAmount: 30000,
          from: inRange.subtract(const Duration(days: 7)),
          to: inRange.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
    });

    test('지출은 정산 후보로 정상 표시된다 (대조군)', () async {
      await insert(amount: 30000, brand: '삼겹살집');

      final TransactionRepositoryImpl repo =
          TransactionRepositoryImpl(TransactionLocalDataSource(db));
      final List<Transaction> candidates = await repo.findSettlementCandidates(
        depositAmount: 30000,
        from: inRange.subtract(const Duration(days: 7)),
        to: inRange.add(const Duration(days: 1)),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.brand, '삼겹살집');
    });
  });
}
