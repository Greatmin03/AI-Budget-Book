import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../../statistics/domain/entities/analytics.dart';
import '../../../settlements/domain/repositories/settlement_repository.dart';
import '../../../statistics/domain/repositories/analytics_repository.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({
    required AnalyticsRepository analytics,
    required TransactionRepository transactions,
    required DepositRepository deposits,
  }) : _analytics = analytics {
    _subscription = transactions.changes.listen((_) => load());
    // 입금이 새로 들어오거나 연결되면 "연결할 입금" 배지가 바뀐다.
    _depositSubscription = deposits.changes.listen((_) => load());
  }

  final AnalyticsRepository _analytics;
  late final StreamSubscription<void> _subscription;
  late final StreamSubscription<void> _depositSubscription;

  DateRange _range = DateRange.month();
  DashboardSummary? _summary;
  bool _isLoading = false;
  String? _error;

  DateRange get range => _range;
  DashboardSummary get summary => _summary ?? DashboardSummary.empty(_range);
  bool get isLoading => _isLoading;
  bool get hasData => _summary != null;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _summary = await _analytics.dashboard(_range);
    } on Object catch (e, stack) {
      AppLogger.e('대시보드 계산 실패', e, stack);
      _error = '요약을 불러오지 못했습니다: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> changeRange(DateRange range) async {
    if (range == _range) return;
    _range = range;
    _summary = null;
    await load();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _depositSubscription.cancel();
    super.dispose();
  }
}
