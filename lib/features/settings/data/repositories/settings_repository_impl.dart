import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;

  AppSettings _cache = const AppSettings();

  @override
  AppSettings get current => _cache;

  @override
  Future<AppSettings> load() async {
    final Map<String, String> raw = await _local.readAll();
    const AppSettings defaults = AppSettings();

    _cache = AppSettings(
      llmEnabled: _bool(raw[SettingsKeys.llmEnabled], defaults.llmEnabled),
      ollamaBaseUrl:
          _string(raw[SettingsKeys.ollamaBaseUrl], defaults.ollamaBaseUrl),
      ollamaModel:
          _string(raw[SettingsKeys.ollamaModel], defaults.ollamaModel),
      requestTimeoutSeconds: _int(
        raw[SettingsKeys.requestTimeoutSeconds],
        defaults.requestTimeoutSeconds,
      ),
      autoLearnBrandRule: _bool(
        raw[SettingsKeys.autoLearnBrandRule],
        defaults.autoLearnBrandRule,
      ),
      minConfidenceToLearn: _double(
        raw[SettingsKeys.minConfidenceToLearn],
        defaults.minConfidenceToLearn,
      ),
      placeApiKey:
          _string(raw[SettingsKeys.placeApiKey], defaults.placeApiKey),
      placeApiEnabled: _bool(
        raw[SettingsKeys.placeApiEnabled],
        defaults.placeApiEnabled,
      ),
      placeApiBlockedUntilMillis: _int(
        raw[SettingsKeys.placeApiBlockedUntil],
        defaults.placeApiBlockedUntilMillis,
      ),
    );
    return _cache;
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _local.writeAll(<String, String>{
      SettingsKeys.llmEnabled: settings.llmEnabled.toString(),
      SettingsKeys.ollamaBaseUrl: settings.ollamaBaseUrl,
      SettingsKeys.ollamaModel: settings.ollamaModel,
      SettingsKeys.requestTimeoutSeconds:
          settings.requestTimeoutSeconds.toString(),
      SettingsKeys.autoLearnBrandRule: settings.autoLearnBrandRule.toString(),
      SettingsKeys.minConfidenceToLearn:
          settings.minConfidenceToLearn.toString(),
      SettingsKeys.placeApiKey: settings.placeApiKey,
      SettingsKeys.placeApiEnabled: settings.placeApiEnabled.toString(),
      SettingsKeys.placeApiBlockedUntil:
          settings.placeApiBlockedUntilMillis.toString(),
    });
    _cache = settings;
  }

  static bool _bool(String? value, bool fallback) {
    if (value == null) return fallback;
    return value.toLowerCase() == 'true';
  }

  static String _string(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) return fallback;
    return value.trim();
  }

  static int _int(String? value, int fallback) =>
      value == null ? fallback : (int.tryParse(value) ?? fallback);

  static double _double(String? value, double fallback) =>
      value == null ? fallback : (double.tryParse(value) ?? fallback);
}
