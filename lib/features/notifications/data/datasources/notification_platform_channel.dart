import 'dart:async';

import 'package:flutter/services.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/raw_notification_dto.dart';

/// Kotlin `PaymentNotificationListenerService` 와의 유일한 통신 지점.
///
/// ## 설계
/// 알림 **내용**은 오직 [drainQueue] 로만 전달된다.
/// 네이티브는 수집한 알림을 파일 큐(JSONL)에 쌓고, EventChannel 로는
/// "큐에 뭔가 들어왔다" 는 **신호만** 보낸다([queueSignal]).
///
/// 이렇게 나눈 이유:
///  - 앱이 죽어 있는 동안의 알림도 파일에 남아 유실되지 않는다.
///  - 내용 전달 경로가 하나뿐이므로 같은 알림을 두 번 처리할 일이 없다.
///    (실시간 스트림 + 파일 큐 두 경로로 내용을 받으면 중복 처리가 생긴다)
class NotificationPlatformChannel {
  NotificationPlatformChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel(methodChannelName),
        _event = eventChannel ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'budget_book/notifications';
  static const String eventChannelName = 'budget_book/notifications/events';

  final MethodChannel _method;
  final EventChannel _event;

  Stream<void>? _signals;

  /// 알림 접근 권한(특수 권한)이 허용되어 있는지.
  Future<bool> isPermissionGranted() async {
    try {
      final bool? granted =
          await _method.invokeMethod<bool>('isPermissionGranted');
      return granted ?? false;
    } on PlatformException catch (e) {
      AppLogger.e('권한 확인 실패', e);
      return false;
    } on MissingPluginException {
      // Android 외 플랫폼 / 네이티브 미구현 환경
      return false;
    }
  }

  /// 시스템 "알림 접근 허용" 설정 화면을 연다.
  Future<void> openPermissionSettings() async {
    try {
      await _method.invokeMethod<void>('openPermissionSettings');
    } on PlatformException catch (e) {
      throw PlatformFailure('설정 화면을 열 수 없습니다: ${e.message}');
    } on MissingPluginException {
      throw const PlatformFailure('이 플랫폼에서는 지원되지 않습니다.');
    }
  }

  /// 리스너 서비스가 실제로 연결되어 있는지(권한은 있어도 미연결일 수 있다).
  Future<bool> isServiceConnected() async {
    try {
      final bool? connected =
          await _method.invokeMethod<bool>('isServiceConnected');
      return connected ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 네이티브 파일 큐의 알림을 모두 가져오고 큐를 비운다.
  ///
  /// 네이티브에서 "읽기 + 삭제" 가 한 번의 lock 안에서 처리되므로
  /// 동시 호출에도 중복/누락이 없다.
  Future<List<RawNotificationDto>> drainQueue() async {
    try {
      final List<Object?>? raw =
          await _method.invokeMethod<List<Object?>>('drainQueue');
      if (raw == null || raw.isEmpty) return const <RawNotificationDto>[];

      final List<RawNotificationDto> result = <RawNotificationDto>[];
      for (final Object? item in raw) {
        if (item is Map<Object?, Object?>) {
          result.add(RawNotificationDto.fromMap(item));
        }
      }
      if (result.isNotEmpty) {
        AppLogger.i('네이티브 큐에서 ${result.length}건 회수');
      }
      return result;
    } on PlatformException catch (e) {
      throw PlatformFailure('알림 큐 회수 실패: ${e.message}');
    } on MissingPluginException {
      return const <RawNotificationDto>[];
    }
  }

  /// 결제 알림을 보낸 적 있는 앱 목록.
  ///
  /// 수집 대상 여부와 무관하게 네이티브가 기록해 둔 것이다.
  /// 설정 화면에서 "어떤 앱을 수집할지" 고르는 후보가 된다.
  Future<List<Map<String, Object?>>> seenSources() async {
    try {
      final List<Object?>? raw =
          await _method.invokeMethod<List<Object?>>('seenSources');
      if (raw == null) return const <Map<String, Object?>>[];

      return raw
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> e) => <String, Object?>{
              for (final MapEntry<Object?, Object?> entry in e.entries)
                entry.key.toString(): entry.value,
            },
          )
          .toList();
    } on PlatformException catch (e) {
      AppLogger.e('감지된 앱 목록 조회 실패', e);
      return const <Map<String, Object?>>[];
    } on MissingPluginException {
      return const <Map<String, Object?>>[];
    }
  }

  /// 수집 허용 패키지를 네이티브 캐시에 반영한다.
  ///
  /// 리스너 서비스는 Flutter 엔진이 없을 때도 돌아가므로 SQLite 를 읽을 수 없다.
  /// 그래서 설정이 바뀔 때마다 네이티브로 복사해 준다.
  Future<void> setEnabledSources(List<String> packages) async {
    try {
      await _method.invokeMethod<void>('setEnabledSources', <String, Object?>{
        'packages': packages,
      });
    } on PlatformException catch (e) {
      throw PlatformFailure('수집 대상 앱 설정 실패: ${e.message}');
    } on MissingPluginException {
      // Android 외 환경에서는 조용히 넘어간다.
    }
  }

  /// "큐에 새 알림이 들어왔다" 신호. 내용은 담기지 않는다.
  Stream<void> get queueSignal {
    return _signals ??= _event
        .receiveBroadcastStream()
        .map<void>((Object? _) {})
        .handleError((Object error, StackTrace stack) {
      AppLogger.e('알림 신호 스트림 오류', error, stack);
    });
  }
}
