/// 알림을 보내는 앱 하나.
///
/// 금융 앱을 여러 개 쓰면 같은 결제가 여러 앱에서 알림으로 온다.
/// 사용자가 고른 앱만 수집해 중복 기록과 노이즈를 막는다.
class NotificationSource {
  const NotificationSource({
    required this.packageName,
    required this.displayName,
    required this.enabled,
    this.lastSeenAt,
    this.detectedAt,
  });

  final String packageName;

  /// 사람이 읽는 앱 이름. 네이티브가 PackageManager 로 얻는다.
  final String displayName;

  final bool enabled;

  /// 마지막으로 결제 알림을 보낸 시각.
  final DateTime? lastSeenAt;

  /// 처음 감지된 시각.
  final DateTime? detectedAt;

  /// 이름을 알 수 없어 패키지명을 그대로 쓰고 있는지.
  bool get hasReadableName => displayName != packageName;

  NotificationSource copyWith({bool? enabled, String? displayName}) {
    return NotificationSource(
      packageName: packageName,
      displayName: displayName ?? this.displayName,
      enabled: enabled ?? this.enabled,
      lastSeenAt: lastSeenAt,
      detectedAt: detectedAt,
    );
  }

  @override
  String toString() =>
      'NotificationSource($displayName, $packageName, enabled=$enabled)';
}

/// 수집 대상 앱 설정 상태.
class NotificationSourceConfig {
  const NotificationSourceConfig({
    required this.sources,
    required this.isConfigured,
  });

  const NotificationSourceConfig.empty()
      : sources = const <NotificationSource>[],
        isConfigured = false;

  /// 감지된 앱 전체(허용/비허용 포함). 최근 감지 순.
  final List<NotificationSource> sources;

  /// 사용자가 한 번이라도 선택을 저장했는지.
  ///
  /// false 면 **전체 허용**으로 동작한다. 설정 전에 아무것도 수집되지 않으면
  /// 사용자는 앱이 고장난 줄 알기 때문이다.
  final bool isConfigured;

  List<NotificationSource> get enabled =>
      sources.where((NotificationSource s) => s.enabled).toList();

  int get enabledCount => enabled.length;

  bool get isEmpty => sources.isEmpty;

  /// 실제로 수집이 제한되고 있는지.
  bool get isFiltering => isConfigured && enabledCount > 0;
}
