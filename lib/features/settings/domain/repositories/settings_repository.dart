import '../entities/app_settings.dart';

abstract interface class SettingsRepository {
  /// 저장된 설정을 읽는다(없으면 기본값).
  Future<AppSettings> load();

  /// 전체 설정을 저장한다.
  Future<void> save(AppSettings settings);

  /// 현재 캐시된 설정. [load] 가 한 번 호출된 뒤에는 동기적으로 접근할 수 있다.
  AppSettings get current;
}
