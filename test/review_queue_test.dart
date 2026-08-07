import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/utils/date_range.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/statistics/data/datasources/statistics_local_datasource.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 무엇을 물어보고 무엇을 세는가.
///
/// 취소된 거래는 통계에 들어가지 않는다. 그런데도 "분류 필요" 로 남으면
/// 사용자는 답할 수 없는 질문을 계속 받는다 — 취소 알림에는 가맹점 이름조차
/// 없다(`출금취소 3,400`).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;

  final DateRange august = DateRange.month(DateTime(2026, 8, 7));

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
  });

  tearDown(() async => db.close());

  int seq = 0;
  Future<Transaction> add({
    required int amount,
    bool cancelled = false,
    bool needsReview = true,
    AiStatus aiStatus = AiStatus.none,
    TransactionDirection direction = TransactionDirection.expense,
    String category = '기타',
    String subcategory = '미분류',
    String brand = '가게',
  }) async {
    final DateTime when = DateTime(2026, 8, 7, 12, seq++);
    return (await transactions.insert(
      Transaction(
        merchantRaw: brand,
        brand: brand,
        amount: amount,
        direction: direction,
        isCancelled: cancelled,
        needsReview: needsReview,
        aiStatus: aiStatus,
        category: category,
        subcategory: subcategory,
        method: PaymentMethodKind.card,
        paymentDatetime: when,
        rawNotification: 'x',
        fingerprint: '$brand|$amount|${when.microsecondsSinceEpoch}',
        classificationSource: ClassificationSource.pending,
      ),
    ))!;
  }

  group('분류 필요 목록', () {
    test('취소된 거래는 묻지 않는다', () async {
      await add(amount: 3400, cancelled: true);
      await add(amount: -3400, cancelled: true, brand: '미확인 가맹점');
      await add(amount: 5000, brand: '진짜 물어봐야 하는 가게');

      final List<Transaction> queue = await transactions.findNeedingReview();

      expect(queue, hasLength(1));
      expect(queue.single.brand, '진짜 물어봐야 하는 가게');
      expect(await transactions.countNeedingReview(), 1);
    });

    test('취소를 해제하면 다시 물어본다', () async {
      final Transaction original = await add(amount: 3400);
      final Transaction cancellation =
          await add(amount: -3400, brand: '미확인 가맹점');
      await transactions.linkCancellation(
        cancellationId: cancellation.id!,
        originalId: original.id!,
      );

      expect(await transactions.countNeedingReview(), 1,
          reason: '취소 건만 남는다(원결제는 취소 표시가 붙었다)');

      await transactions.unlinkCancellation(cancellation.id!);

      // 원결제가 통계로 돌아왔으니 분류가 다시 의미를 갖는다.
      expect(await transactions.countNeedingReview(), 2);
    });
  });

  group('AI 대기열', () {
    test('취소된 거래에는 LLM 을 부르지 않는다', () async {
      await add(amount: 3400, cancelled: true, aiStatus: AiStatus.pending);
      await add(amount: 5000, aiStatus: AiStatus.pending);

      final List<Transaction> queue = await transactions.findAiPending();

      // 통계에 들어가지 않는 거래를 분류하려고 LLM 을 부르는 것은 낭비다.
      expect(queue, hasLength(1));
      expect(queue.single.amount, 5000);
      expect(await transactions.countAiPending(), 1);
    });
  });

  group('들어왔지만 내 소득이 아닌 돈', () {
    test('인증 1원은 수입 통계에서 빠진다', () async {
      await add(
        amount: 599000,
        direction: TransactionDirection.income,
        category: '급여',
        subcategory: '월급',
        needsReview: false,
        brand: '급여',
      );
      await add(
        amount: 1,
        direction: TransactionDirection.income,
        category: '기타',
        subcategory: CategoryTaxonomy.nonIncomeSubcategory,
        needsReview: false,
        brand: '계좌 인증',
      );

      final StatisticsLocalDataSource stats = StatisticsLocalDataSource(db);

      // 통장에는 찍혔지만 "이번 달 얼마 벌었나" 의 답이 아니다.
      expect(await stats.incomeTotalInRange(august), 599000);
      expect(await stats.incomeCountInRange(august), 1);
    });

    test('정산과는 다른 자리다', () async {
      // 정산은 "내가 쓴 돈을 돌려받은 것" 이라 나중에 따로 세게 된다.
      // 둘을 섞으면 그 질문에 답할 수 없다.
      expect(
        CategoryTaxonomy.nonIncomeSubcategory,
        isNot(CategoryTaxonomy.settlementCategory),
      );
      expect(
        CategoryTaxonomy.incomeSubcategoriesOf('기타'),
        contains(CategoryTaxonomy.nonIncomeSubcategory),
      );
      expect(
        CategoryTaxonomy.coerceIncome(
          '기타',
          CategoryTaxonomy.nonIncomeSubcategory,
        ),
        const CategoryPair('기타', CategoryTaxonomy.nonIncomeSubcategory),
      );
    });
  });
}
