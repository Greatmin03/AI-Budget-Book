import '../../../../core/utils/date_range.dart';
import '../entities/insight_facts.dart';

abstract interface class InsightRepository {
  /// 기간의 사실 묶음을 계산한다.
  ///
  /// AI 기능은 모두 이 결과를 근거로 삼는다.
  /// [weekdayLookbackWeeks] 는 요일 패턴을 볼 기간(주 수)이다.
  Future<InsightFacts> facts(
    DateRange range, {
    int weekdayLookbackWeeks = 8,
  });
}
