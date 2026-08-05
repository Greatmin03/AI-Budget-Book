import '../entities/raw_notification.dart';

/// 알림 수집 경계.
///
/// 도메인은 "알림이 어디서 오는지(Platform Channel / 파일 큐)" 를 알지 못한다.
abstract interface class NotificationListenerRepository {
  /// 알림 접근 권한 허용 여부.
  Future<bool> isPermissionGranted();

  /// 시스템 설정 화면 열기.
  Future<void> openPermissionSettings();

  /// 리스너 서비스 연결 여부.
  Future<bool> isServiceConnected();

  /// 네이티브 큐에 쌓인 알림을 회수한다(회수 후 큐는 비워진다).
  ///
  /// 앱이 꺼져 있던 동안 발생한 결제도 여기서 함께 돌아온다.
  Future<List<RawNotification>> drainPending();

  /// "새 알림이 큐에 들어왔다" 신호.
  ///
  /// 내용은 담기지 않는다. 신호를 받으면 [drainPending] 을 호출해야 한다.
  Stream<void> watchQueueSignal();
}
