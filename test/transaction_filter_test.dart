import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/features/transactions/domain/usecases/apply_user_correction.dart';
import 'package:budget_book/features/transactions/presentation/controllers/transaction_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 거래 목록의 일반 / 전체 / 취소 탭.
///
/// 취소된 결제와 그 취소 건이 나란히 보이면 "썼다가 돌려받았다" 를 매번 다시
/// 읽어야 한다. 그렇다고 지워 버리면 무슨 일이 있었는지 알 수 없다.
/// **기본은 숨기고, 필요하면 볼 수 있게** 한다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl repository;
  late TransactionListController controller;

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
    repository = TransactionRepositoryImpl(TransactionLocalDataSource(db));
    controller = TransactionListController(
      repository: repository,
      applyUserCorrection: ApplyUserCorrection(
        transactions: repository,
        merchants: MerchantRepositoryImpl(MerchantLocalDataSource(db)),
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  int seq = 0;
  Future<Transaction> add({
    required int amount,
    bool cancelled = false,
    String brand = '스타벅스',
    String? cardName = 'KB국민은행',
  }) async {
    final DateTime when = DateTime(2026, 8, 10, 12, seq++);
    return (await repository.insert(
      Transaction(
        merchantRaw: brand,
        brand: brand,
        amount: amount,
        isCancelled: cancelled,
        category: '식비',
        subcategory: '카페',
        method: PaymentMethodKind.card,
        cardName: cardName,
        paymentDatetime: when,
        rawNotification: 'x',
        fingerprint: '$brand|$amount|${when.microsecondsSinceEpoch}',
        classificationSource: ClassificationSource.seed,
      ),
    ))!;
  }

  /// 결제 하나와 그 취소 하나. 둘 다 취소 표시가 붙는다.
  Future<(Transaction, Transaction)> cancelledPair() async {
    final Transaction original = await add(amount: 30000);
    final Transaction cancellation =
        await add(amount: -30000, cancelled: true, brand: '미확인 가맹점');
    await repository.linkCancellation(
      cancellationId: cancellation.id!,
      originalId: original.id!,
    );
    return (original, cancellation);
  }

  group('일반 탭', () {
    test('취소된 결제와 취소 건을 둘 다 숨긴다', () async {
      await cancelledPair();
      await add(amount: 5000, brand: '메가커피');
      await controller.load();

      expect(controller.filter, TransactionFilter.normal);
      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.brand, '메가커피');
    });

    test('합계는 필터와 무관하다', () async {
      await cancelledPair();
      await add(amount: 5000, brand: '메가커피');
      await controller.load();

      // 취소 탭을 보는 동안 이번 달 지출이 0원으로 바뀌면 안 된다.
      final int normal = controller.expenseTotal;
      controller.changeFilter(TransactionFilter.cancelled);
      expect(controller.expenseTotal, normal);
      expect(normal, 5000, reason: '취소된 30,000원은 빠져야 한다');
    });
  });

  group('전체 탭', () {
    test('취소도 그대로 보여 준다', () async {
      await cancelledPair();
      await add(amount: 5000, brand: '메가커피');
      await controller.load();

      controller.changeFilter(TransactionFilter.all);
      expect(controller.transactions, hasLength(3));
    });
  });

  group('취소 탭', () {
    test('취소 건만 보여 준다(원결제는 아니다)', () async {
      await cancelledPair();
      await add(amount: 5000, brand: '메가커피');
      await controller.load();

      controller.changeFilter(TransactionFilter.cancelled);
      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.amount, -30000);
    });

    test('원결제를 함께 찾아 준다', () async {
      final (Transaction original, _) = await cancelledPair();
      await controller.load();
      controller.changeFilter(TransactionFilter.cancelled);

      final Transaction cancellation = controller.transactions.single;
      expect(controller.originalOf(cancellation)?.id, original.id);
    });

    test('미연결 취소를 센다', () async {
      await add(amount: 30000);
      await add(amount: -30000, cancelled: true, brand: '미확인 가맹점');
      await controller.load();

      // 자동 연결은 수집 경로에서만 일어난다. 여기서는 직접 넣었으므로
      // 미연결 상태다.
      expect(controller.unmatchedCancellationCount, 1);
      controller.changeFilter(TransactionFilter.cancelled);
      expect(controller.originalOf(controller.transactions.single), isNull);
    });
  });

  group('연결과 해제', () {
    test('연결하면 원결제가 통계에서 빠진다', () async {
      final Transaction original = await add(amount: 30000);
      final Transaction cancellation =
          await add(amount: -30000, cancelled: true, brand: '미확인 가맹점');
      await controller.load();
      expect(controller.expenseTotal, 30000, reason: '연결 전');

      await controller.linkCancellation(
        cancellation: cancellation,
        original: original,
      );
      await controller.load();

      expect(controller.expenseTotal, 0);
      expect(controller.unmatchedCancellationCount, 0);
    });

    test('해제하면 원결제가 통계로 돌아온다', () async {
      final (_, Transaction cancellation) = await cancelledPair();
      await controller.load();
      expect(controller.expenseTotal, 0);

      await controller.unlinkCancellation(cancellation);
      await controller.load();

      expect(controller.expenseTotal, 30000);
      expect(controller.unmatchedCancellationCount, 1);
    });

    test('후보는 같은 카드 · 같은 금액만 나온다', () async {
      final Transaction same = await add(amount: 30000);
      await add(amount: 30000, cardName: '신한카드');
      await add(amount: 5000);
      final Transaction cancellation =
          await add(amount: -30000, cancelled: true, brand: '미확인 가맹점');
      await controller.load();

      final List<Transaction> candidates =
          await controller.candidatesFor(cancellation);

      expect(candidates.map((Transaction t) => t.id), <int?>[same.id]);
    });
  });
}
