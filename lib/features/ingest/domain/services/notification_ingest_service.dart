import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../notifications/domain/entities/raw_notification.dart';
import '../../../notifications/domain/repositories/notification_listener_repository.dart';
import '../entities/ingest_result.dart';
import '../usecases/record_payment_notification.dart';

/// 알림 수집 -> 처리 파이프라인을 구동하는 애플리케이션 서비스.
///
/// 두 입력을 하나의 **직렬 큐**로 합친다.
///  - 실시간 알림 스트림
///  - 앱이 꺼져 있던 동안 네이티브가 쌓아둔 큐
///
/// 직렬 처리가 중요한 이유: LLM 호출이 동시에 여러 건 들어가면
/// 4B 모델이라도 로컬 자원을 잡아먹고, 같은 가맹점을 중복 학습할 수 있다.
class NotificationIngestService {
  NotificationIngestService({
    required NotificationListenerRepository listener,
    required RecordPaymentNotification recordPayment,
  })  : _listener = listener,
        _recordPayment = recordPayment;

  final NotificationListenerRepository _listener;
  final RecordPaymentNotification _recordPayment;

  final Queue<RawNotification> _pending = Queue<RawNotification>();
  StreamSubscription<void>? _subscription;
  bool _isDraining = false;

  /// UI 가 관찰하는 상태.
  final ValueNotifier<IngestStatus> status =
      ValueNotifier<IngestStatus>(const IngestStatus());

  bool get isRunning => _subscription != null;

  /// 수신을 시작하고, 밀린 알림을 즉시 회수한다.
  ///
  /// 네이티브는 신호만 보내므로, 신호를 받을 때마다 파일 큐를 비운다.
  Future<void> start() async {
    if (_subscription != null) return;

    _subscription = _listener.watchQueueSignal().listen(
      (_) => drainNativeQueue(),
      onError: (Object error, StackTrace stack) {
        AppLogger.e('알림 신호 스트림 오류', error, stack);
      },
    );
    AppLogger.i('알림 수집 시작');
    await drainNativeQueue();
  }

  /// 앱이 포그라운드로 돌아올 때마다 호출한다.
  Future<void> drainNativeQueue() async {
    try {
      final List<RawNotification> pending = await _listener.drainPending();
      if (pending.isEmpty) return;
      pending.forEach(_enqueue);
    } on Object catch (e, stack) {
      AppLogger.e('네이티브 큐 회수 실패', e, stack);
    }
  }

  /// 테스트/수동 처리용. 알림 한 건을 직접 밀어 넣는다.
  void enqueue(RawNotification notification) => _enqueue(notification);

  void _enqueue(RawNotification notification) {
    _pending.addLast(notification);
    status.value = status.value.copyWith(queued: _pending.length);
    // await 하지 않는다. 큐 소비는 백그라운드로 돌린다.
    _drain();
  }

  Future<void> _drain() async {
    if (_isDraining) return;
    _isDraining = true;

    try {
      while (_pending.isNotEmpty) {
        final RawNotification notification = _pending.removeFirst();
        status.value = status.value.copyWith(
          queued: _pending.length,
          isProcessing: true,
        );

        try {
          final IngestResult result = await _recordPayment(notification);
          status.value = status.value.applyResult(result);
        } on Object catch (e, stack) {
          // 한 건이 실패해도 큐 전체가 멈추면 안 된다.
          AppLogger.e('알림 처리 실패: ${notification.title}', e, stack);
          status.value = status.value.copyWith(
            lastMessage: '처리 중 오류: $e',
            failedCount: status.value.failedCount + 1,
          );
        }
      }
    } finally {
      _isDraining = false;
      status.value = status.value.copyWith(
        isProcessing: false,
        queued: _pending.length,
      );
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    AppLogger.i('알림 수집 중지');
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    status.dispose();
  }
}

/// 수집 상태 스냅샷(설정/홈 화면 표시용).
class IngestStatus {
  const IngestStatus({
    this.queued = 0,
    this.isProcessing = false,
    this.savedCount = 0,
    this.ignoredCount = 0,
    this.failedCount = 0,
    this.duplicateCount = 0,
    this.mergedCount = 0,
    this.depositCount = 0,
    this.lastMessage,
    this.lastUpdatedAt,
  });

  final int queued;
  final bool isProcessing;
  final int savedCount;
  final int ignoredCount;
  final int failedCount;
  final int duplicateCount;

  /// 다른 앱 알림과 합쳐진 건수. 거래가 늘지는 않았다.
  final int mergedCount;

  /// 정산 후보로 저장한 입금 건수.
  final int depositCount;

  /// 이번 실행에서 LLM 을 호출한 횟수. "LLM 최소 호출" 원칙 확인용.

  final String? lastMessage;
  final DateTime? lastUpdatedAt;

  IngestStatus copyWith({
    int? queued,
    bool? isProcessing,
    int? savedCount,
    int? ignoredCount,
    int? failedCount,
    int? duplicateCount,
    int? mergedCount,
    int? depositCount,
    String? lastMessage,
  }) {
    return IngestStatus(
      queued: queued ?? this.queued,
      isProcessing: isProcessing ?? this.isProcessing,
      savedCount: savedCount ?? this.savedCount,
      ignoredCount: ignoredCount ?? this.ignoredCount,
      failedCount: failedCount ?? this.failedCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      mergedCount: mergedCount ?? this.mergedCount,
      depositCount: depositCount ?? this.depositCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastUpdatedAt: DateTime.now(),
    );
  }

  IngestStatus applyResult(IngestResult result) {
    return switch (result) {
      IngestSaved() => copyWith(
          savedCount: savedCount + 1,
          lastMessage: result.summary,
        ),
      // 병합은 버린 것이 아니라 값을 더한 것이다. 저장으로 세지도 않는다
      // (거래가 늘지 않았으므로).
      IngestMerged() => copyWith(
          mergedCount: mergedCount + 1,
          lastMessage: result.summary,
        ),
      IngestDuplicate() => copyWith(
          duplicateCount: duplicateCount + 1,
          lastMessage: result.summary,
        ),
      IngestDepositRecorded() => copyWith(
          depositCount: depositCount + 1,
          lastMessage: result.summary,
        ),
      IngestIgnored() => copyWith(
          ignoredCount: ignoredCount + 1,
          lastMessage: result.summary,
        ),
      IngestFailed() => copyWith(
          failedCount: failedCount + 1,
          lastMessage: result.summary,
        ),
    };
  }
}
