import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../classification/domain/entities/llm_health.dart';
import '../../../classification/data/datasources/place_api_datasource.dart';
import '../../../classification/domain/repositories/brand_metadata_repository.dart';
import '../../../classification/domain/repositories/classifier_repository.dart';
import '../../../classification/domain/usecases/lookup_brand_industry.dart';
import '../../../ingest/domain/repositories/ingest_failure_repository.dart';
import '../../../merchants/domain/repositories/merchant_repository.dart';
import '../../../notifications/domain/entities/notification_source.dart';
import '../../../notifications/domain/repositories/notification_listener_repository.dart';
import '../../../notifications/domain/repositories/notification_source_repository.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository settings,
    required ClassifierRepository classifier,
    required MerchantRepository merchants,
    required TransactionRepository transactions,
    required IngestFailureRepository failures,
    required NotificationListenerRepository notifications,
    required NotificationSourceRepository sources,
    required BrandMetadataRepository brandMetadata,
    required LookupBrandIndustry lookupIndustry,
  })  : _settingsRepo = settings,
        _classifier = classifier,
        _merchants = merchants,
        _transactions = transactions,
        _failures = failures,
        _notifications = notifications,
        _sources = sources,
        _brandMetadata = brandMetadata,
        _lookupIndustry = lookupIndustry;

  final SettingsRepository _settingsRepo;
  final ClassifierRepository _classifier;
  final MerchantRepository _merchants;
  final TransactionRepository _transactions;
  final IngestFailureRepository _failures;
  final NotificationListenerRepository _notifications;
  final NotificationSourceRepository _sources;
  final BrandMetadataRepository _brandMetadata;
  final LookupBrandIndustry _lookupIndustry;

  AppSettings _settings = const AppSettings();
  bool _permissionGranted = false;
  bool _serviceConnected = false;
  int _learnedMerchants = 0;
  int _transactionCount = 0;
  LlmHealth? _health;
  bool _isTestingConnection = false;

  NotificationSourceConfig _sourceConfig =
      const NotificationSourceConfig.empty();
  int _brandMetadataCount = 0;
  bool _isTestingPlaceApi = false;
  PlaceLookupResult? _placeApiResult;

  AppSettings get settings => _settings;
  bool get permissionGranted => _permissionGranted;
  bool get serviceConnected => _serviceConnected;
  int get learnedMerchants => _learnedMerchants;
  int get transactionCount => _transactionCount;
  LlmHealth? get health => _health;
  bool get isTestingConnection => _isTestingConnection;

  /// 감지된 알림 앱 + 허용 설정.
  NotificationSourceConfig get sourceConfig => _sourceConfig;

  /// 장소 API 로 조회해 둔 브랜드 수(캐시 크기).
  int get brandMetadataCount => _brandMetadataCount;

  bool get isTestingPlaceApi => _isTestingPlaceApi;
  PlaceLookupResult? get placeApiResult => _placeApiResult;

  /// dispose 이후에는 알림을 보내지 않는다.
  ///
  /// [testConnection] / [testPlaceApi] 는 네트워크를 최대 수십 초 기다린 뒤
  /// `finally` 에서 알림을 보낸다. 그 사이 화면이 사라져 컨트롤러가 dispose
  /// 되면 `A SettingsController was used after being disposed` 로 죽는다.
  /// 요청을 취소할 수단이 없으므로 알림 쪽에서 막는다.
  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    _settings = await _settingsRepo.load();
    _permissionGranted = await _notifications.isPermissionGranted();
    _serviceConnected = await _notifications.isServiceConnected();
    _learnedMerchants = await _merchants.learnedCount();
    _transactionCount = await _transactions.countAll();
    _sourceConfig = await _sources.load();
    _brandMetadataCount = await _brandMetadata.count();
    _notify();
  }

  Future<void> _update(AppSettings next) async {
    _settings = next;
    _notify();
    await _settingsRepo.save(next);
  }

  Future<void> setLlmEnabled(bool value) =>
      _update(_settings.copyWith(llmEnabled: value));

  Future<void> setAutoLearnBrandRule(bool value) =>
      _update(_settings.copyWith(autoLearnBrandRule: value));

  Future<void> setOllamaBaseUrl(String value) =>
      _update(_settings.copyWith(ollamaBaseUrl: value.trim()));

  Future<void> setOllamaModel(String value) =>
      _update(_settings.copyWith(ollamaModel: value.trim()));

  Future<void> setTimeout(int seconds) =>
      _update(_settings.copyWith(requestTimeoutSeconds: seconds));

  Future<void> setMinConfidence(double value) =>
      _update(_settings.copyWith(minConfidenceToLearn: value));

  Future<void> openPermissionSettings() async {
    await _notifications.openPermissionSettings();
  }

  /// Ollama 연결 테스트.
  Future<void> testConnection() async {
    _isTestingConnection = true;
    _health = null;
    _notify();

    try {
      _health = await _classifier.checkHealth();
    } on Object catch (e, stack) {
      AppLogger.e('연결 테스트 실패', e, stack);
      _health = LlmHealth(reachable: false, message: '$e');
    } finally {
      _isTestingConnection = false;
      _notify();
    }
  }

  // ------------------------------------------------------- 알림 수집 대상 앱
  /// 앱 하나를 켜고 끈다. 네이티브 필터에도 즉시 반영된다.
  Future<void> toggleSource({
    required String packageName,
    required bool enabled,
  }) async {
    await _sources.toggle(packageName: packageName, enabled: enabled);
    _sourceConfig = await _sources.load();
    _notify();
  }

  /// 감지 목록을 다시 읽는다(새 앱이 알림을 보낸 뒤).
  Future<void> refreshSources() async {
    _sourceConfig = await _sources.load();
    _notify();
  }

  // ------------------------------------------------------------- 장소 API
  Future<void> setPlaceApiEnabled(bool value) =>
      _update(_settings.copyWith(placeApiEnabled: value));

  Future<void> setPlaceApiKey(String value) async {
    // 키를 새로 넣으면 한도 초과 상태를 해제한다(다른 키일 수 있다).
    await _update(
      _settings.copyWith(
        placeApiKey: value.trim(),
        placeApiBlockedUntilMillis: 0,
      ),
    );
    _placeApiResult = null;
    _notify();
  }

  /// 한도 초과로 쉬는 상태를 사용자가 직접 해제한다.
  Future<void> clearPlaceApiThrottle() =>
      _update(_settings.copyWith(placeApiBlockedUntilMillis: 0));

  /// 키가 유효한지 실제로 1회 호출해 확인한다.
  Future<void> testPlaceApi() async {
    final String key = _settings.placeApiKey.trim();
    if (key.isEmpty) {
      _placeApiResult =
          const PlaceLookupResult.failed('먼저 REST API 키를 입력하세요.');
      _notify();
      return;
    }

    _isTestingPlaceApi = true;
    _placeApiResult = null;
    _notify();

    try {
      _placeApiResult = await _lookupIndustry.testKey(key);
    } on Object catch (e, stack) {
      AppLogger.e('장소 API 테스트 실패', e, stack);
      _placeApiResult = PlaceLookupResult.failed('$e');
    } finally {
      _isTestingPlaceApi = false;
      _notify();
    }
  }

  /// 조회 캐시를 비운다. 사용자가 직접 지정한 값은 남는다.
  Future<int> clearBrandLookupCache() async {
    final int removed = await _brandMetadata.clearLookupCache();
    _brandMetadataCount = await _brandMetadata.count();
    _notify();
    return removed;
  }

  Future<List<IngestFailureRecord>> loadFailures() => _failures.recent();

  Future<void> clearFailures() async {
    await _failures.clear();
    _notify();
  }
}
