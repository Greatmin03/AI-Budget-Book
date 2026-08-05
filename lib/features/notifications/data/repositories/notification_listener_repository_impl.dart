import '../../domain/entities/raw_notification.dart';
import '../../domain/repositories/notification_listener_repository.dart';
import '../datasources/notification_platform_channel.dart';
import '../models/raw_notification_dto.dart';

class NotificationListenerRepositoryImpl
    implements NotificationListenerRepository {
  NotificationListenerRepositoryImpl(this._channel);

  final NotificationPlatformChannel _channel;

  @override
  Future<bool> isPermissionGranted() => _channel.isPermissionGranted();

  @override
  Future<void> openPermissionSettings() => _channel.openPermissionSettings();

  @override
  Future<bool> isServiceConnected() => _channel.isServiceConnected();

  @override
  Future<List<RawNotification>> drainPending() async {
    final List<RawNotificationDto> dtos = await _channel.drainQueue();
    return dtos.map((RawNotificationDto e) => e.toEntity()).toList();
  }

  @override
  Stream<void> watchQueueSignal() => _channel.queueSignal;
}
