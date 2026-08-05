import '../entities/notification_source.dart';

abstract interface class NotificationSourceRepository {
  /// 감지된 앱 + 저장된 허용 설정을 합쳐서 반환한다.
  ///
  /// 네이티브가 발견한 앱 목록과 DB 에 저장된 선택을 병합한다.
  Future<NotificationSourceConfig> load();

  /// 허용할 패키지를 저장하고 네이티브 캐시에도 반영한다.
  ///
  /// 네이티브 반영이 빠지면 리스너가 계속 옛 설정으로 동작한다.
  Future<void> setEnabled(Set<String> enabledPackages);

  /// 한 앱만 토글한다.
  Future<void> toggle({required String packageName, required bool enabled});

  /// 저장된 설정을 네이티브에 다시 밀어 넣는다(앱 시작 시).
  Future<void> syncToNative();
}
