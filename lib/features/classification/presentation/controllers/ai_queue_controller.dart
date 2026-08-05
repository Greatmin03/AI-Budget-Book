import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/llm_health.dart';
import '../../domain/usecases/process_ai_pending_queue.dart';

/// AI 분석 대기열 상태.
///
/// 배너("AI 분석 대기 23건 [지금 분석]")와 자동 실행을 담당한다.
///
/// **UI 를 막지 않는다.** 분석은 백그라운드에서 돌고, 그 사이에도 거래 목록과
/// 통계는 그대로 쓸 수 있다. 진행 상태만 배너에 표시한다.
class AiQueueController extends ChangeNotifier {
  AiQueueController({
    required ProcessAiPendingQueue process,
    required TransactionRepository transactions,
  })  : _process = process,
        _transactions = transactions {
    // 거래가 저장/수정되면 대기 건수가 바뀐다.
    _subscription = _transactions.changes.listen((_) => refresh());
  }

  final ProcessAiPendingQueue _process;
  final TransactionRepository _transactions;
  late final StreamSubscription<void> _subscription;

  int _pendingCount = 0;
  bool _isProcessing = false;
  bool _disposed = false;
  LlmHealth? _health;
  AiBatchResult? _lastResult;

  /// 분석을 기다리는 거래 수.
  int get pendingCount => _pendingCount;

  bool get isProcessing => _isProcessing;

  /// 마지막으로 확인한 Ollama 상태. null 이면 아직 확인하지 않았다.
  LlmHealth? get health => _health;

  AiBatchResult? get lastResult => _lastResult;

  /// Ollama 에 닿는 것이 확인되었는지.
  bool get isConnected => _health?.isUsable ?? false;

  /// 배너를 보여 줄지.
  ///
  /// 대기 건수가 있고, AI 를 쓸 수 있는 상태여야 한다. AI 를 끈 사용자에게
  /// "분석 대기 23건" 을 보여 주면 할 수 있는 일이 없어 불필요한 불안만 준다.
  bool get shouldShowBanner => _pendingCount > 0 && isConnected;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 대기 건수만 다시 읽는다(가볍다).
  Future<void> refresh() async {
    try {
      _pendingCount = await _process.pendingCount();
      _notify();
    } on Object catch (e, stack) {
      AppLogger.e('AI 대기 건수 조회 실패', e, stack);
    }
  }

  /// 앱 시작 시 호출한다.
  ///
  /// 대기 건수를 읽고, 대기가 있을 때만 Ollama 연결을 확인한다.
  /// 대기가 없으면 연결 확인 자체가 낭비다.
  ///
  /// [autoProcess] 가 true 면 연결되어 있을 때 곧바로 일괄 처리를 시작한다.
  Future<void> initialize({bool autoProcess = true}) async {
    await refresh();
    if (_pendingCount == 0) return;

    await checkConnection();
    if (!isConnected) {
      AppLogger.i('AI 분석 대기 $_pendingCount건 (Ollama 미연결 — 나중에 처리)');
      return;
    }

    if (autoProcess) {
      await processNow();
    }
  }

  /// Ollama 연결 확인.
  Future<LlmHealth?> checkConnection() async {
    try {
      _health = await _process.checkConnection();
      _notify();
      return _health;
    } on Object catch (e, stack) {
      AppLogger.e('Ollama 연결 확인 실패', e, stack);
      _health = LlmHealth(reachable: false, message: '$e');
      _notify();
      return _health;
    }
  }

  /// 대기열을 지금 처리한다.
  ///
  /// 이미 처리 중이면 아무것도 하지 않는다(중복 실행 방지).
  Future<AiBatchResult?> processNow() async {
    if (_isProcessing) return null;

    _isProcessing = true;
    _notify();

    try {
      // 연결은 이미 확인했으므로 다시 확인하지 않는다.
      _lastResult = await _process(requireConnectionCheck: !isConnected);
      return _lastResult;
    } on Object catch (e, stack) {
      AppLogger.e('AI 일괄 분석 실패', e, stack);
      return null;
    } finally {
      _isProcessing = false;
      await refresh();
      _notify();
    }
  }

  @override
  void dispose() {
    // 구독을 먼저 끊는다. 끊지 않으면 dispose 후에도 refresh 가 불려
    // notifyListeners 로 죽는다.
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
