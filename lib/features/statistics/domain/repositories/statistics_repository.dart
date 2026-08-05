import '../../../../core/utils/date_range.dart';
import '../entities/statistics.dart';

abstract interface class StatisticsRepository {
  /// 통계 화면에 필요한 기본 데이터를 한 번에 계산한다.
  ///
  /// [trendMonths] 는 기간 필터와 무관하게 "최근 N개월" 추이를 만든다.
  /// (오늘/이번 주를 보고 있어도 월별 흐름은 따로 보는 편이 유용하다)
  Future<PeriodStatistics> statistics(
    DateRange range, {
    int trendMonths = 6,
    List<String> highlightSubcategories = const <String>['카페', '배달'],
  });
}
