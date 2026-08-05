import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/classification/data/repositories/brand_metadata_repository_impl.dart';
import 'package:budget_book/features/classification/domain/entities/llm_health.dart';
import 'package:budget_book/features/classification/domain/entities/merchant_classification.dart';
import 'package:budget_book/features/classification/domain/repositories/classifier_repository.dart';
import 'package:budget_book/features/classification/domain/usecases/process_ai_pending_queue.dart';
import 'package:budget_book/features/merchants/data/datasources/merchant_local_datasource.dart';
import 'package:budget_book/features/merchants/data/repositories/merchant_repository_impl.dart';
import 'package:budget_book/features/merchants/domain/entities/merchant.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:budget_book/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/models/transaction_dto.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 호출 횟수를 세는 가짜 LLM.
///
/// 이 기능의 핵심 약속은 **브랜드당 AI 호출 1회**다. 그래서 "동작한다" 가
/// 아니라 "몇 번 불렀나" 를 검증한다.
class _FakeClassifier implements ClassifierRepository {
  /// 테스트에서 필드로 직접 바꿔 쓴다(생성자 인자는 두지 않는다).
  bool enabled = true;
  bool reachable = true;

  /// null 이면 미분류를 반환한다.
  MerchantClassification? result;
  bool throwOnCall = false;

  /// 브랜드별 호출 횟수.
  final List<String> calls = <String>[];

  @override
  bool get isEnabled => enabled;

  @override
  Future<LlmHealth> checkHealth() async => reachable
      ? const LlmHealth(
          reachable: true,
          message: '연결됨',
          modelInstalled: true,
          installedModels: <String>['gemma3:4b'],
        )
      : const LlmHealth(reachable: false, message: '연결 실패');

  @override
  Future<MerchantClassification> classifyWithLlm(String merchantRaw) async {
    calls.add(merchantRaw);
    if (throwOnCall) throw StateError('LLM 오류');
    return result ??
        const MerchantClassification(
          brand: '',
          category: '기타',
          subcategory: '미분류',
          source: ClassificationSource.llm,
        );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionRepositoryImpl transactions;
  late BrandMetadataRepositoryImpl metadata;
  late MerchantRepositoryImpl merchants;
  late SettingsRepositoryImpl settings;
  late _FakeClassifier classifier;

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
    metadata = BrandMetadataRepositoryImpl(db);
    merchants = MerchantRepositoryImpl(MerchantLocalDataSource(db));
    settings = SettingsRepositoryImpl(SettingsLocalDataSource(db));
    await settings.load();
    classifier = _FakeClassifier();
  });

  tearDown(() async => db.close());

  ProcessAiPendingQueue buildUseCase() => ProcessAiPendingQueue(
        classifier: classifier,
        transactions: transactions,
        metadata: metadata,
        merchants: merchants,
        settings: settings,
      );

  /// 대기열에 들어간 거래 하나.
  Future<void> enqueue({
    required String brand,
    int amount = 12000,
    AiStatus status = AiStatus.pending,
    PaymentMethodKind method = PaymentMethodKind.card,
    String? merchantRaw,
    ClassificationSource source = ClassificationSource.pending,
    int seq = 0,
  }) async {
    final Transaction tx = Transaction(
      merchantRaw: merchantRaw ?? brand,
      brand: brand,
      amount: amount,
      category: '기타',
      subcategory: '미분류',
      method: method,
      paymentDatetime: DateTime(2026, 8, 5, 12, seq),
      rawNotification: 'test',
      fingerprint: '$brand|$amount|$seq',
      classificationSource: source,
      needsReview: true,
      aiStatus: status,
    );
    await db.insert(
      DbSchema.tableTransactions,
      TransactionDto.toRow(tx, now: DateTime.now()),
    );
  }

  Future<List<Transaction>> allTransactions() async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT t.*, 0 AS ${TransactionDto.settledAmountColumn} '
      'FROM ${DbSchema.tableTransactions} t '
      'ORDER BY ${DbSchema.tId} ASC',
    );
    return rows.map(TransactionDto.fromRow).toList();
  }

  const MerchantClassification chineseFood = MerchantClassification(
    brand: '행복반점',
    category: '식비',
    subcategory: '중식',
    source: ClassificationSource.llm,
    confidence: 0.95,
  );

  group('브랜드당 AI 호출 1회', () {
    test('같은 브랜드 15건이 있어도 LLM 은 한 번만 부른다', () async {
      for (int i = 0; i < 15; i++) {
        await enqueue(brand: '행복반점', amount: 12000 + i, seq: i);
      }
      classifier.result = chineseFood;

      final AiBatchResult result = await buildUseCase()();

      expect(classifier.calls.length, 1, reason: '이 기능의 핵심 약속이다');
      expect(result.llmCalls, 1);
      expect(result.brandsProcessed, 1);
      expect(result.transactionsUpdated, 15, reason: '15건 모두 분류돼야 한다');
    });

    test('분류 결과가 모든 거래에 적용되고 대기가 풀린다', () async {
      await enqueue(brand: '행복반점', seq: 0);
      await enqueue(brand: '행복반점', seq: 1);
      classifier.result = chineseFood;

      await buildUseCase()();

      final List<Transaction> saved = await allTransactions();
      expect(saved.every((Transaction t) => t.category == '식비'), isTrue);
      expect(saved.every((Transaction t) => t.subcategory == '중식'), isTrue);
      expect(saved.every((Transaction t) => t.needsReview), isFalse);
      expect(
        saved.every((Transaction t) => t.aiStatus == AiStatus.completed),
        isTrue,
      );
      expect(await transactions.countAiPending(), 0);
    });

    test('브랜드 캐시에 있으면 LLM 을 부르지 않는다', () async {
      await enqueue(brand: '행복반점');
      // 이전 실행에서 이미 알아낸 브랜드.
      await metadata.markUserModified(
        brand: '행복반점',
        category: '식비',
        subcategory: '중식',
      );

      final AiBatchResult result = await buildUseCase()();

      expect(classifier.calls, isEmpty, reason: '캐시가 있으면 물어볼 이유가 없다');
      expect(result.cacheHits, 1);
      expect(result.transactionsUpdated, 1);
    });

    test('여러 브랜드는 각각 한 번씩 부른다', () async {
      await enqueue(brand: '행복반점', seq: 0);
      await enqueue(brand: '행복반점', seq: 1);
      await enqueue(brand: '동네카페', seq: 2);
      classifier.result = chineseFood;

      final AiBatchResult result = await buildUseCase()();

      expect(classifier.calls.length, 2);
      expect(result.brandsProcessed, 2);
    });

    test('결과가 브랜드 캐시에 저장되어 다음부터 즉시 쓰인다', () async {
      await enqueue(brand: '행복반점');
      classifier.result = chineseFood;

      await buildUseCase()();

      final dynamic cached = await metadata.find('행복반점');
      expect(cached, isNotNull);
      expect(cached.category, '식비');
      expect(cached.subcategory, '중식');
    });

    test('브랜드 규칙으로 승격되어 새 지점도 자동 분류된다', () async {
      await enqueue(brand: '행복반점');
      classifier.result = chineseFood;

      await buildUseCase()();

      final List<BrandRule> rules = await merchants.allBrandRules();
      expect(
        rules.any((BrandRule r) => r.brand == '행복반점'),
        isTrue,
        reason: '아직 본 적 없는 지점까지 자동 분류돼야 한다',
      );
    });
  });

  group('실행 조건', () {
    test('AI 가 꺼져 있으면 실행하지 않는다', () async {
      await enqueue(brand: '행복반점');
      classifier.enabled = false;

      final AiBatchResult result = await buildUseCase()();

      expect(result.didRun, isFalse);
      expect(classifier.calls, isEmpty);
      expect(await transactions.countAiPending(), 1, reason: '대기는 그대로 남는다');
    });

    test('Ollama 에 닿지 않으면 실행하지 않는다', () async {
      await enqueue(brand: '행복반점');
      classifier.reachable = false;

      final AiBatchResult result = await buildUseCase()();

      expect(result.didRun, isFalse);
      expect(result.skippedReason, contains('연결'));
      expect(await transactions.countAiPending(), 1);
    });

    test('대기 거래가 없으면 연결 확인도 하지 않는다', () async {
      final AiBatchResult result = await buildUseCase()();

      expect(result.didRun, isFalse);
      expect(classifier.calls, isEmpty);
    });
  });

  group('실패 처리', () {
    test('AI 가 분류하지 못하면 failed 로 남아 재시도할 수 있다', () async {
      await enqueue(brand: '알수없는가게');
      classifier.result = null; // 미분류 반환

      final AiBatchResult result = await buildUseCase()();

      expect(result.failures, 1);
      expect(result.transactionsUpdated, 0);

      final Transaction saved = (await allTransactions()).single;
      expect(saved.aiStatus, AiStatus.failed);
      expect(saved.aiStatus.isRetryable, isTrue);
      expect(saved.needsReview, isTrue, reason: '사용자가 직접 고를 수 있어야 한다');
    });

    test('한 브랜드가 예외로 죽어도 나머지는 처리된다', () async {
      await enqueue(brand: '문제브랜드', seq: 0);
      await enqueue(brand: '정상브랜드', seq: 1);
      classifier
        ..throwOnCall = true
        ..result = chineseFood;

      // 첫 브랜드에서 예외가 나도 루프가 멈추지 않는지 확인한다.
      final AiBatchResult result = await buildUseCase()();

      expect(result.brandsProcessed, 2);
      expect(result.failures, 2, reason: '둘 다 예외지만 루프는 끝까지 돈다');
    });

    test('확신도가 기준 미만이면 학습하지 않는다', () async {
      await enqueue(brand: '애매한가게');
      classifier.result = const MerchantClassification(
        brand: '애매한가게',
        category: '식비',
        subcategory: '한식',
        source: ClassificationSource.llm,
        confidence: 0.2,
      );
      await settings.save(settings.current.copyWith(minConfidenceToLearn: 0.5));

      final AiBatchResult result = await buildUseCase()();

      expect(result.failures, 1);
      expect(result.transactionsUpdated, 0);
    });
  });

  group('정책', () {
    test('이체 거래는 AI 로 분류하지 않는다', () async {
      await enqueue(
        brand: '홍길동',
        method: PaymentMethodKind.accountTransfer,
      );
      classifier.result = chineseFood;

      final AiBatchResult result = await buildUseCase()();

      expect(classifier.calls, isEmpty, reason: '사람 이름은 브랜드가 아니다');
      expect(result.transactionsUpdated, 0);

      final Transaction saved = (await allTransactions()).single;
      expect(
        saved.aiStatus,
        AiStatus.none,
        reason: '다시 시도해도 소용없으므로 대기열에서 빼야 한다',
      );
      expect(await transactions.countAiPending(), 0);
    });

    test('사용자가 직접 분류한 거래는 AI 결과로 덮지 않는다', () async {
      await enqueue(
        brand: '행복반점',
        source: ClassificationSource.user,
        seq: 0,
      );
      await enqueue(brand: '행복반점', seq: 1);
      classifier.result = chineseFood;

      await buildUseCase()();

      final List<Transaction> saved = await allTransactions();
      final Transaction userOne = saved.first;
      expect(userOne.category, '기타', reason: '사용자 분류를 보존한다');
      expect(saved.last.category, '식비');
    });
  });
}
