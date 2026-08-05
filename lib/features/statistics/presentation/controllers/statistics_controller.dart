import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/statistics.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../../domain/repositories/statistics_repository.dart';

/// 통계 화면 상태.
///
/// 기본 통계(총액/비율/추이)와 드릴다운 데이터(카테고리 트리, 브랜드 목록)를
/// 함께 들고 있는다. 한 화면에서 두 가지를 모두 보여 주기 때문이다.
class StatisticsController extends ChangeNotifier {
  StatisticsController({
    required StatisticsRepository repository,
    required AnalyticsRepository analytics,
    required TransactionRepository transactions,
  })  : _repository = repository,
        _analytics = analytics {
    _subscription = transactions.changes.listen((_) => load());
  }

  final StatisticsRepository _repository;
  final AnalyticsRepository _analytics;
  late final StreamSubscription<void> _subscription;

  DateRange _range = DateRange.month();
  PeriodStatistics? _statistics;
  List<CategoryNode> _categoryTree = const <CategoryNode>[];
  List<BrandStat> _brands = const <BrandStat>[];
  BrandSortBy _brandSortBy = BrandSortBy.amount;
  bool _isLoading = false;
  String? _error;

  DateRange get range => _range;
  PeriodStatistics get statistics =>
      _statistics ?? PeriodStatistics.empty(_range);
  List<CategoryNode> get categoryTree => _categoryTree;
  List<BrandStat> get brands => _brands;
  BrandSortBy get brandSortBy => _brandSortBy;
  bool get isLoading => _isLoading;
  bool get hasData => _statistics != null;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _statistics = await _repository.statistics(_range);
      _categoryTree = await _analytics.categoryTree(_range);
      _brands = await _analytics.brandStats(_range, sortBy: _brandSortBy);
    } on Object catch (e, stack) {
      AppLogger.e('통계 계산 실패', e, stack);
      _error = '통계를 불러오지 못했습니다: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> changeRange(DateRange range) async {
    if (range == _range) return;
    _range = range;
    _statistics = null;
    await load();
  }

  /// 브랜드 목록 정렬만 바꾼다(전체 재조회 없이).
  Future<void> changeBrandSort(BrandSortBy sortBy) async {
    if (sortBy == _brandSortBy) return;
    _brandSortBy = sortBy;
    notifyListeners();

    try {
      _brands = await _analytics.brandStats(_range, sortBy: sortBy);
    } on Object catch (e, stack) {
      AppLogger.e('브랜드 정렬 실패', e, stack);
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
