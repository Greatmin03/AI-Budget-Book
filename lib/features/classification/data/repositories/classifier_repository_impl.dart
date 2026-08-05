import '../../../../core/logging/app_logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../../domain/entities/llm_health.dart';
import '../../domain/entities/merchant_classification.dart';
import '../../domain/repositories/classifier_repository.dart';
import '../datasources/ollama_remote_datasource.dart';
import '../models/classification_dto.dart';

class ClassifierRepositoryImpl implements ClassifierRepository {
  ClassifierRepositoryImpl({
    required OllamaRemoteDataSource remote,
    required SettingsRepository settings,
  })  : _remote = remote,
        _settings = settings;

  final OllamaRemoteDataSource _remote;
  final SettingsRepository _settings;

  @override
  bool get isEnabled => _settings.current.llmEnabled;

  @override
  Future<MerchantClassification> classifyWithLlm(String merchantRaw) async {
    final AppSettings settings = _settings.current;
    final Stopwatch stopwatch = Stopwatch()..start();

    final String raw = await _remote.classifyMerchant(
      baseUrl: settings.ollamaBaseUrl,
      model: settings.ollamaModel,
      merchantName: merchantRaw,
      timeout: Duration(seconds: settings.requestTimeoutSeconds),
    );

    // 검증을 통과한 결과만 상위로 올린다.
    final MerchantClassification result = ClassificationDto.parse(
      rawResponse: raw,
      merchantNameFallback: merchantRaw,
    );

    stopwatch.stop();
    AppLogger.i('LLM 분류 "$merchantRaw" -> $result '
        '(${stopwatch.elapsedMilliseconds}ms)');
    return result;
  }

  @override
  Future<LlmHealth> checkHealth() async {
    final AppSettings settings = _settings.current;
    if (!settings.llmEnabled) {
      return const LlmHealth.disabled();
    }
    return _remote.checkHealth(
      baseUrl: settings.ollamaBaseUrl,
      model: settings.ollamaModel,
    );
  }
}
