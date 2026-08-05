import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 여러 금융 앱이 같은 결제를 알릴 때 한 건만 저장되는지 검증한다.
///
/// KB 앱과 토스 앱이 같은 결제를 알리면 카드명·시각이 미세하게 달라
/// 지문(fingerprint)이 갈리고 두 건이 저장됐다.
///
/// **UI 에서 숨기는 것이 아니라 저장 자체를 막는다.** 저장해 두면 모든
/// 집계가 두 배가 되고 골라내는 일이 사용자 몫이 된다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;

  final DateTime at = DateTime(2026, 8, 10, 14, 30, 15);

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

  Transaction build({
    required String sourcePackage,
    int amount = 15000,
    String brand = '스타벅스',
    String merchantRaw = '스타벅스강남점',
    String? cardName = 'KB국민카드',
    PaymentMethodKind method = PaymentMethodKind.card,
    DateTime? when,
    EntrySource entrySource = EntrySource.notification,
  }) {
    final DateTime moment = when ?? at;
    return Transaction(
      merchantRaw: merchantRaw,
      brand: brand,
      amount: amount,
      category: '식비',
      subcategory: '카페',
      method: method,
      cardName: cardName,
      paymentDatetime: moment,
      rawNotification: '$sourcePackage 알림',
      sourcePackage: sourcePackage,
      // 실제 파이프라인과 동일하게 지문을 만든다.
      fingerprint: Transaction.buildFingerprint(
        merchantRaw: merchantRaw,
        signedAmount: amount,
        paymentDatetime: moment,
        cardName: cardName,
      ),
      classificationSource: ClassificationSource.seed,
      entrySource: entrySource,
    );
  }

  Future<int> countRows() async {
    final List<Map<String, Object?>> rows =
        await db.query(DbSchema.tableTransactions);
    return rows.length;
  }

  group('앱 간 중복 저장 차단', () {
    test('KB 와 토스가 같은 결제를 알리면 한 건만 저장된다', () async {
      final Transaction? first = await transactions.insert(
        build(sourcePackage: 'com.kbcard.cxh.appcard'),
      );
      // 토스는 카드명 문구가 다르고 시각도 몇 초 어긋난다.
      final Transaction? second = await transactions.insert(
        build(
          sourcePackage: 'viva.republica.toss',
          cardName: '토스',
          when: at.add(const Duration(seconds: 12)),
        ),
      );

      expect(first, isNotNull);
      expect(second, isNull, reason: '두 번째는 저장되지 않아야 한다');
      expect(await countRows(), 1);
    });

    test('분 경계를 넘어도(59초 -> 01초) 같은 결제로 본다', () async {
      // 지문은 분 단위로 자르므로 이 경우가 예전에 중복의 주범이었다.
      await transactions.insert(
        build(
          sourcePackage: 'com.kbcard.cxh.appcard',
          when: DateTime(2026, 8, 10, 14, 30, 59),
        ),
      );
      final Transaction? second = await transactions.insert(
        build(
          sourcePackage: 'viva.republica.toss',
          cardName: '토스',
          when: DateTime(2026, 8, 10, 14, 31, 1),
        ),
      );

      expect(second, isNull);
      expect(await countRows(), 1);
    });

    test('30초를 넘으면 다른 결제로 본다', () async {
      await transactions.insert(build(sourcePackage: 'kb'));
      final Transaction? second = await transactions.insert(
        build(
          sourcePackage: 'toss',
          cardName: '토스',
          when: at.add(const Duration(seconds: 45)),
        ),
      );

      expect(second, isNotNull, reason: '45초 뒤 같은 금액은 별개 결제일 수 있다');
      expect(await countRows(), 2);
    });

    test('금액이 다르면 별개 거래다', () async {
      await transactions.insert(build(sourcePackage: 'kb', amount: 15000));
      final Transaction? second = await transactions.insert(
        build(sourcePackage: 'toss', amount: 16000, cardName: '토스'),
      );

      expect(second, isNotNull);
      expect(await countRows(), 2);
    });

    test('브랜드가 다르면 별개 거래다', () async {
      await transactions.insert(build(sourcePackage: 'kb', brand: '스타벅스'));
      final Transaction? second = await transactions.insert(
        build(sourcePackage: 'toss', brand: '메가커피', cardName: '토스'),
      );

      expect(second, isNotNull);
      expect(await countRows(), 2);
    });

    test('결제 수단이 다르면 별개 거래다', () async {
      await transactions.insert(
        build(sourcePackage: 'kb', method: PaymentMethodKind.card),
      );
      final Transaction? second = await transactions.insert(
        build(
          sourcePackage: 'kakao',
          method: PaymentMethodKind.easyPay,
          cardName: null,
        ),
      );

      expect(second, isNotNull, reason: '카드 결제와 간편결제는 다른 거래일 수 있다');
      expect(await countRows(), 2);
    });

    test('취소 거래는 원본과 별개로 저장된다', () async {
      await transactions.insert(build(sourcePackage: 'kb', amount: 30000));
      // 취소는 음수로 저장되므로 금액이 다르다.
      final Transaction? cancelled = await transactions.insert(
        build(
          sourcePackage: 'kb',
          amount: -30000,
          when: at.add(const Duration(seconds: 5)),
        ),
      );

      expect(cancelled, isNotNull, reason: '취소가 삼켜지면 합계가 틀어진다');
      expect(await countRows(), 2);
    });

    test('같은 알림이 두 번 와도 한 건이다 (지문 중복)', () async {
      final Transaction sample = build(sourcePackage: 'kb');
      await transactions.insert(sample);
      final Transaction? again = await transactions.insert(sample);

      expect(again, isNull);
      expect(await countRows(), 1);
    });
  });

  group('직접 입력은 막지 않는다', () {
    test('같은 금액·가게를 연달아 직접 입력할 수 있다', () async {
      // 현금으로 같은 커피를 두 잔 사는 것은 정상이다.
      final Transaction? first = await transactions.insert(
        build(
          sourcePackage: 'manual',
          entrySource: EntrySource.manual,
          method: PaymentMethodKind.cash,
          cardName: null,
        ).copyWith(),
      );
      final Transaction? second = await transactions.insert(
        Transaction(
          merchantRaw: '스타벅스강남점',
          brand: '스타벅스',
          amount: 15000,
          category: '식비',
          subcategory: '카페',
          method: PaymentMethodKind.cash,
          paymentDatetime: at,
          rawNotification: '직접 입력',
          // 직접 입력은 생성 시각으로 항상 고유한 지문을 만든다.
          fingerprint: 'manual|${DateTime.now().microsecondsSinceEpoch}',
          classificationSource: ClassificationSource.user,
          entrySource: EntrySource.manual,
        ),
      );

      expect(first, isNotNull);
      expect(second, isNotNull, reason: '사용자가 넣은 거래를 조용히 버리면 안 된다');
      expect(await countRows(), 2);
    });

    test('직접 입력이 먼저 있어도 알림 쪽은 중복으로 막힌다', () async {
      // 사용자가 미리 적어 둔 거래와 같은 결제 알림이 뒤늦게 오는 경우.
      await transactions.insert(
        Transaction(
          merchantRaw: '스타벅스강남점',
          brand: '스타벅스',
          amount: 15000,
          category: '식비',
          subcategory: '카페',
          method: PaymentMethodKind.card,
          paymentDatetime: at,
          rawNotification: '직접 입력',
          fingerprint: 'manual|1',
          classificationSource: ClassificationSource.user,
          entrySource: EntrySource.manual,
        ),
      );

      final Transaction? fromNotification = await transactions.insert(
        build(sourcePackage: 'com.kbcard.cxh.appcard'),
      );

      expect(fromNotification, isNull);
      expect(await countRows(), 1);
    });
  });
}
