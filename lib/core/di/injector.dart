import 'package:sqflite/sqflite.dart';

import '../../features/classification/data/datasources/ollama_remote_datasource.dart';
import '../../features/classification/data/datasources/place_api_datasource.dart';
import '../../features/classification/data/repositories/brand_metadata_repository_impl.dart';
import '../../features/classification/data/repositories/classification_diagnostics_repository_impl.dart';
import '../../features/classification/data/repositories/classifier_repository_impl.dart';
import '../../features/classification/domain/repositories/brand_metadata_repository.dart';
import '../../features/classification/domain/repositories/classification_diagnostics_repository.dart';
import '../../features/classification/domain/repositories/classifier_repository.dart';
import '../../features/classification/domain/usecases/lookup_brand_industry.dart';
import '../../features/classification/domain/usecases/process_ai_pending_queue.dart';
import '../../features/classification/presentation/controllers/ai_queue_controller.dart';
import '../../features/ingest/data/datasources/ingest_failure_local_datasource.dart';
import '../../features/ingest/data/repositories/ingest_failure_repository_impl.dart';
import '../../features/ingest/domain/repositories/ingest_failure_repository.dart';
import '../../features/ingest/domain/services/notification_ingest_service.dart';
import '../../features/ingest/domain/usecases/record_payment_notification.dart';
import '../../features/merchants/data/datasources/merchant_local_datasource.dart';
import '../../features/merchants/data/repositories/merchant_repository_impl.dart';
import '../../features/merchants/domain/repositories/merchant_repository.dart';
import '../../features/merchants/domain/services/brand_extractor.dart';
import '../../features/notifications/data/datasources/notification_platform_channel.dart';
import '../../features/notifications/data/repositories/notification_listener_repository_impl.dart';
import '../../features/notifications/data/repositories/notification_source_repository_impl.dart';
import '../../features/notifications/domain/repositories/notification_listener_repository.dart';
import '../../features/notifications/domain/repositories/notification_source_repository.dart';
import '../../features/parsing/domain/services/payment_notification_parser.dart';
import '../../features/settings/data/datasources/settings_local_datasource.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settlements/data/datasources/settlement_local_datasource.dart';
import '../../features/settlements/data/repositories/settlement_repository_impl.dart';
import '../../features/settlements/domain/repositories/settlement_repository.dart';
import '../../features/settlements/domain/usecases/manage_settlements.dart';
import '../../features/assets/data/repositories/account_repository_impl.dart';
import '../../features/assets/data/repositories/card_account_link_repository_impl.dart';
import '../../features/assets/data/repositories/asset_repository_impl.dart';
import '../../features/assets/domain/repositories/account_repository.dart';
import '../../features/assets/domain/repositories/card_account_link_repository.dart';
import '../../features/assets/domain/repositories/asset_repository.dart';
import '../../features/insights/data/repositories/insight_repository_impl.dart';
import '../../features/insights/domain/repositories/insight_repository.dart';
import '../../features/insights/domain/services/insight_narrator.dart';
import '../../features/projects/data/repositories/project_repository_impl.dart';
import '../../features/projects/domain/repositories/project_repository.dart';
import '../../features/recurring/data/repositories/recurring_repository_impl.dart';
import '../../features/recurring/domain/repositories/recurring_repository.dart';
import '../../features/statistics/data/datasources/analytics_local_datasource.dart';
import '../../features/statistics/data/datasources/statistics_local_datasource.dart';
import '../../features/statistics/data/repositories/analytics_repository_impl.dart';
import '../../features/statistics/data/repositories/statistics_repository_impl.dart';
import '../../features/statistics/domain/repositories/analytics_repository.dart';
import '../../features/statistics/domain/repositories/statistics_repository.dart';
import '../../features/transactions/data/datasources/transaction_local_datasource.dart';
import '../../features/transactions/data/repositories/transaction_repository_impl.dart';
import '../../features/transactions/domain/repositories/transaction_repository.dart';
import '../../features/transactions/domain/usecases/add_manual_transaction.dart';
import '../../features/transactions/domain/usecases/apply_user_correction.dart';
import '../database/app_database.dart';
import '../database/seed/brand_seed.dart';
import '../logging/app_logger.dart';

/// 아주 단순한 서비스 로케이터.
///
/// 외부 DI 패키지를 쓰지 않는다. 의존 관계가 한 파일에 다 보이는 편이
/// 이 규모에서는 오히려 추적하기 쉽다.
///
/// 사용 전 [init] 을 반드시 호출해야 한다(main 에서 1회).
class Injector {
  Injector._();

  static final Injector instance = Injector._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ------------------------------------------------------------ repositories
  late final SettingsRepository settings;
  late final MerchantRepository merchants;
  late final TransactionRepository transactions;
  late final StatisticsRepository statistics;

  /// 브랜드/카테고리 드릴다운, 검색, 대시보드.
  late final AnalyticsRepository analytics;

  late final ClassifierRepository classifier;
  late final IngestFailureRepository ingestFailures;
  late final NotificationListenerRepository notifications;

  /// 알림 수집 대상 앱 관리.
  late final NotificationSourceRepository notificationSources;

  /// 장소 API 로 조회한 브랜드 업종 캐시.
  late final BrandMetadataRepository brandMetadata;

  /// 정산(더치페이).
  late final SettlementRepository settlements;

  /// 입금 알림(정산 후보).
  late final DepositRepository deposits;

  /// 정기결제 규칙(거래 위의 메타데이터).
  late final RecurringRepository recurring;

  /// 자산 이동(적금 납입 등). 소비 통계에서 제외된다.
  late final AssetRepository assets;

  /// 자산 계좌(잔액·총자산·추이).
  late final AccountRepository accounts;

  /// 카드 이름 -> 계좌 연결. 알림 거래를 잔액에 반영하는 다리다.
  late final CardAccountLinkRepository cardAccountLinks;

  /// 프로젝트(폴더).
  late final ProjectRepository projects;

  /// 사실 계산 레이어. AI 기능이 모두 이 위에 얹힌다.
  late final InsightRepository insights;

  // --------------------------------------------------------------- use cases

  /// 분류 파이프라인 계측(디버그 화면 + 미매핑 업종 수집).
  late final ClassificationDiagnosticsRepository classificationDiagnostics;

  /// 브랜드 업종 조회(브랜드당 최대 1회). 설정에서 상태 확인/키 테스트에도 쓴다.
  late final LookupBrandIndustry lookupBrandIndustry;

  /// AI 분류 대기열 일괄 처리. 결제 순간에는 AI 를 부르지 않는다.
  late final ProcessAiPendingQueue processAiQueue;

  late final RecordPaymentNotification recordPayment;
  late final ApplyUserCorrection applyUserCorrection;
  late final ManageSettlements manageSettlements;
  late final LinkDepositToTransaction linkDeposit;
  late final AddManualTransaction addManualTransaction;

  /// 사실 -> 문장. LLM 이 없어도 동작한다.
  late final InsightNarrator narrator;

  /// AI 분석 대기열 상태. 배너가 여러 화면에서 같은 값을 봐야 하므로
  /// 화면이 아니라 여기서 하나만 만든다.
  late final AiQueueController aiQueue;

  // ---------------------------------------------------------------- services
  late final NotificationIngestService ingestService;

  /// 개발/디버깅용 직접 접근.
  late final OllamaRemoteDataSource ollama;
  late final PlaceApiDataSource placeApi;
  late final AppDatabase database;

  Future<void> init() async {
    if (_initialized) return;

    database = AppDatabase.instance;
    final Database db = await database.open();

    // ----------------------------------------------------------- datasources
    final SettingsLocalDataSource settingsLocal = SettingsLocalDataSource(db);
    final MerchantLocalDataSource merchantLocal = MerchantLocalDataSource(db);
    final TransactionLocalDataSource transactionLocal =
        TransactionLocalDataSource(db);
    final StatisticsLocalDataSource statisticsLocal =
        StatisticsLocalDataSource(db);
    final AnalyticsLocalDataSource analyticsLocal =
        AnalyticsLocalDataSource(db);
    final IngestFailureLocalDataSource failureLocal =
        IngestFailureLocalDataSource(db);
    final SettlementLocalDataSource settlementLocal =
        SettlementLocalDataSource(db);
    final DepositLocalDataSource depositLocal = DepositLocalDataSource(db);
    final NotificationPlatformChannel channel = NotificationPlatformChannel();
    ollama = OllamaRemoteDataSource();
    placeApi = PlaceApiDataSource();

    // ---------------------------------------------------------- repositories
    final SettingsRepositoryImpl settingsRepo =
        SettingsRepositoryImpl(settingsLocal);
    await settingsRepo.load(); // 이후 동기 접근을 위해 미리 캐시
    settings = settingsRepo;

    merchants = MerchantRepositoryImpl(merchantLocal);
    transactions = TransactionRepositoryImpl(transactionLocal);
    statistics = StatisticsRepositoryImpl(statisticsLocal);
    settlements = SettlementRepositoryImpl(settlementLocal);
    deposits = DepositRepositoryImpl(depositLocal);
    recurring = RecurringRepositoryImpl(db);
    assets = AssetRepositoryImpl(db);
    accounts = AccountRepositoryImpl(db);
    cardAccountLinks = CardAccountLinkRepositoryImpl(db);
    projects = ProjectRepositoryImpl(db);
    insights = InsightRepositoryImpl(db);
    analytics = AnalyticsRepositoryImpl(
      analytics: analyticsLocal,
      statistics: statisticsLocal,
      transactions: transactions,
      deposits: deposits,
      recurring: recurring,
    );
    ingestFailures = IngestFailureRepositoryImpl(failureLocal);
    notifications = NotificationListenerRepositoryImpl(channel);
    notificationSources = NotificationSourceRepositoryImpl(
      db: db,
      channel: channel,
    );
    brandMetadata = BrandMetadataRepositoryImpl(db);
    classificationDiagnostics =
        ClassificationDiagnosticsRepositoryImpl(db);
    classifier = ClassifierRepositoryImpl(
      remote: ollama,
      settings: settings,
    );

    // -------------------------------------------------------------- usecases
    lookupBrandIndustry = LookupBrandIndustry(
      metadata: brandMetadata,
      placeApi: placeApi,
      settings: settings,
      diagnostics: classificationDiagnostics,
    );
    processAiQueue = ProcessAiPendingQueue(
      classifier: classifier,
      transactions: transactions,
      metadata: brandMetadata,
      merchants: merchants,
      settings: settings,
    );
    recordPayment = RecordPaymentNotification(
      // 파서가 후보 중 아는 브랜드를 고를 수 있게 사전을 넘긴다.
      // (`씨유(CU) 춘천 백령점` 에서 지점명 대신 브랜드를 고르게 한다)
      parser: PaymentNotificationParser(
        recognizeBrand: const BrandExtractor(BrandSeed.definitions).recognizes,
      ),
      merchants: merchants,
      transactions: transactions,
      failures: ingestFailures,
      settings: settings,
      deposits: deposits,
      recurring: recurring,
      lookupIndustry: lookupBrandIndustry,
      cardLinks: cardAccountLinks,
    );
    applyUserCorrection = ApplyUserCorrection(
      merchants: merchants,
      transactions: transactions,
      brandMetadata: brandMetadata,
    );
    manageSettlements = ManageSettlements(
      settlements: settlements,
      transactions: transactions,
    );
    linkDeposit = LinkDepositToTransaction(
      deposits: deposits,
      settlements: manageSettlements,
      transactions: transactions,
    );
    addManualTransaction =
        AddManualTransaction(transactions, merchants: merchants);
    narrator = const InsightNarrator();
    aiQueue = AiQueueController(
      process: processAiQueue,
      transactions: transactions,
    );

    // -------------------------------------------------------------- services
    ingestService = NotificationIngestService(
      listener: notifications,
      recordPayment: recordPayment,
    );

    // 네이티브 필터 캐시를 DB 와 맞춘다(앱 재설치/데이터 삭제 후 어긋날 수 있다).
    await notificationSources.syncToNative();

    _initialized = true;
    AppLogger.i('의존성 초기화 완료');
  }

  /// 리소스를 정리한다(스트림 구독, HTTP 클라이언트, DB 핸들).
  ///
  /// 주의: 필드가 `late final` 이므로 정리 후 [init] 을 다시 호출할 수는 없다.
  /// 재초기화가 필요한 테스트는 각 리포지토리를 직접 조립해서 쓴다.
  Future<void> disposeAll() async {
    if (!_initialized) return;
    ingestService.dispose();
    aiQueue.dispose();
    ollama.dispose();
    placeApi.dispose();
    await database.close();
  }
}
