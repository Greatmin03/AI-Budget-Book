import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/core/database/seed/brand_seed.dart';
import 'package:budget_book/features/classification/data/datasources/place_api_datasource.dart';
import 'package:budget_book/features/classification/data/repositories/brand_metadata_repository_impl.dart';
import 'package:budget_book/features/classification/domain/usecases/lookup_brand_industry.dart';
import 'package:budget_book/features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import 'package:budget_book/features/ingest/data/repositories/ingest_failure_repository_impl.dart';
import 'package:budget_book/features/ingest/domain/entities/ingest_result.dart';
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
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 분류 우선순위 사슬을 파이프라인 전체로 검증한다.
///
/// ```
/// 사용자 규칙 -> 내장 사전 -> 장소 API -> LLM -> 사용자 선택
/// ```
///
/// 특히 두 가지를 지킨다.
///  - 사전에 있는 브랜드는 API 를 호출하지 않는다(할당량 낭비).
///  - **이체/송금 거래명은 절대 외부로 보내지 않는다**(상대방 이름).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late int apiCallCount;

  /// 마지막으로 카카오에 보낸 검색어. 개인정보 유출 검증에 쓴다.
  late List<String> sentQueries;

  /// 어떤 브랜드든 카페로 응답하는 가짜 서버.
  PlaceApiDataSource fakePlaceApi() {
    return PlaceApiDataSource(
      client: MockClient((http.Request request) async {
        apiCallCount++;
        sentQueries.add(request.url.queryParameters['query'] ?? '');
        return http.Response(
          '{"documents":[{"place_name":"테스트가게",'
          '"category_name":"음식점 > 카페 > 커피전문점"}]}',
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
  }

  Future<RecordPaymentNotification> buildUseCase({
    String apiKey = 'test-key',
  }) async {
    final SettingsRepositoryImpl settings =
        SettingsRepositoryImpl(SettingsLocalDataSource(db));
    await settings.load();
    await settings.save(
      // LLM 은 끈 상태로 둔다. 초기 버전의 기본값이며, 장소 API 단계가
      // LLM 없이도 동작해야 한다.
      settings.current.copyWith(placeApiKey: apiKey),
    );

    final MerchantRepositoryImpl merchants =
        MerchantRepositoryImpl(MerchantLocalDataSource(db));
    return RecordPaymentNotification(
      parser: PaymentNotificationParser(
        recognizeBrand: const BrandExtractor(BrandSeed.definitions).recognizes,
      ),
      merchants: merchants,
      transactions: TransactionRepositoryImpl(TransactionLocalDataSource(db)),
      failures: IngestFailureRepositoryImpl(IngestFailureLocalDataSource(db)),
      settings: settings,
      deposits: DepositRepositoryImpl(DepositLocalDataSource(db)),
      recurring: RecurringRepositoryImpl(db),
      lookupIndustry: LookupBrandIndustry(
        metadata: BrandMetadataRepositoryImpl(db),
        placeApi: fakePlaceApi(),
        settings: settings,
      ),
    );
  }

  setUp(() async {
    apiCallCount = 0;
    sentQueries = <String>[];
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
        // 내장 브랜드 사전(시드). 사전 히트 시 API 를 부르지 않는지 확인해야 한다.
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
  });

  tearDown(() async => db.close());

  RawNotification cardPayment(String merchant, {int amount = 5000}) {
    return RawNotification(
      packageName: 'com.kbcard.cxh.appcard',
      title: 'KB국민카드',
      text: 'KB국민카드 승인 홍*동 $amount원 일시불 08/05 14:33 $merchant',
      postedAt: DateTime(2026, 8, 5, 14, 33),
    );
  }

  Transaction saved(IngestResult result) {
    expect(result, isA<IngestSaved>(), reason: '저장돼야 한다: ${result.summary}');
    return (result as IngestSaved).transaction;
  }

  test('처음 보는 브랜드는 장소 API 로 자동 분류된다', () async {
    final RecordPaymentNotification record = await buildUseCase();

    final Transaction tx = saved(await record(cardPayment('동네작은카페')));

    expect(tx.category, '식비');
    expect(tx.subcategory, '카페');
    expect(tx.needsReview, isFalse, reason: '업종을 알아냈으므로 물어볼 필요가 없다');
    expect(tx.classificationSource, ClassificationSource.rule);
    expect(apiCallCount, 1);
  });

  test('같은 브랜드를 또 결제해도 API 를 다시 부르지 않는다', () async {
    final RecordPaymentNotification record = await buildUseCase();

    await record(cardPayment('동네작은카페', amount: 5000));
    await record(cardPayment('동네작은카페', amount: 6000));
    await record(cardPayment('동네작은카페', amount: 7000));

    expect(apiCallCount, 1);
  });

  test('내장 사전에 있는 브랜드는 API 를 부르지 않는다', () async {
    final RecordPaymentNotification record = await buildUseCase();

    final Transaction tx = saved(await record(cardPayment('스타벅스강남점')));

    expect(tx.brand, '스타벅스');
    expect(apiCallCount, 0, reason: '사전으로 해결되면 조회할 이유가 없다');
  });

  test('송금 거래명(상대방 이름)은 절대 외부로 보내지 않는다', () async {
    final RecordPaymentNotification record = await buildUseCase();

    final IngestResult result = await record(
      RawNotification(
        packageName: 'com.kakaobank.channel',
        title: '카카오뱅크',
        text: '카카오뱅크 출금 30,000원 08/05 14:33 홍길동',
        postedAt: DateTime(2026, 8, 5, 14, 33),
      ),
    );

    expect(apiCallCount, 0, reason: '사람 이름을 장소 검색에 보내면 안 된다');
    expect(sentQueries, isEmpty);

    // 기록 자체는 정상적으로 남고, 분류만 사용자에게 넘긴다.
    if (result is IngestSaved) {
      expect(result.transaction.needsReview, isTrue);
    }
  });

  test('키가 없으면 조회 없이도 정상 기록된다 (분류 필요로 남는다)', () async {
    final RecordPaymentNotification record = await buildUseCase(apiKey: '');

    final Transaction tx = saved(await record(cardPayment('처음보는가게')));

    expect(apiCallCount, 0);
    expect(tx.needsReview, isTrue);
    expect(tx.amount, 5000, reason: 'API 가 없어도 금액은 그대로 기록된다');
  });

  test('조회한 브랜드는 가맹점으로 학습되어 다른 지점도 자동 분류된다', () async {
    final RecordPaymentNotification record = await buildUseCase();

    await record(cardPayment('동네작은카페'));
    final Transaction second =
        saved(await record(cardPayment('동네작은카페', amount: 8000)));

    expect(second.category, '식비');
    expect(second.subcategory, '카페');
    expect(second.needsReview, isFalse);
  });
  group('은행별 표기 차이 흡수 (Brand Extractor)', () {
    // 이 기능의 목적은 정확히 이것이다:
    // 이미 아는 브랜드는 카카오 API 도 AI 도 부르지 않는다.
    for (final (String raw, String brand) sample in <(String, String)>[
      ('씨유강원대제3학생', 'CU'),
      ('씨유(CU) 춘천 백령점', 'CU'),
      ('씨유강대병원점', 'CU'),
      ('지에스25춘천애막골', 'GS25'),
      ('지에스25춘천효제길', 'GS25'),
      ('메가MGC커피강원대점', '메가MGC커피'),
      ('메가커피춘천후평점', '메가MGC커피'),
    ]) {
      test('${sample.$1} -> ${sample.$2} (외부 호출 없음)', () async {
        final RecordPaymentNotification record = await buildUseCase();

        final Transaction tx = saved(await record(cardPayment(sample.$1)));

        expect(tx.brand, sample.$2, reason: '대표 브랜드로 모여야 한다');
        expect(tx.needsReview, isFalse, reason: '아는 브랜드이므로 물어볼 필요가 없다');
        expect(
          apiCallCount,
          0,
          reason: '사전으로 해결되면 카카오를 부르지 않는다',
        );
        expect(tx.aiStatus, AiStatus.none, reason: 'AI 대기열에도 넣지 않는다');
      });
    }

    test('같은 브랜드의 다른 표기가 하나로 모인다', () async {
      final RecordPaymentNotification record = await buildUseCase();

      await record(cardPayment('씨유강원대제3학생', amount: 1000));
      await record(cardPayment('씨유강대병원점', amount: 2000));
      await record(cardPayment('CU 춘천점', amount: 3000));

      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT DISTINCT ${DbSchema.tBrand} AS b '
        'FROM ${DbSchema.tableTransactions}',
      );

      expect(
        rows.map((Map<String, Object?> r) => r['b']).toList(),
        <String>['CU'],
        reason: '표기가 달라도 통계에서 한 브랜드로 합쳐져야 한다',
      );
      expect(apiCallCount, 0);
    });
  });
}
