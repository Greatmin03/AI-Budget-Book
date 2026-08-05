import '../../../../core/utils/date_range.dart';
import '../entities/analytics.dart';

/// 브랜드 / 카테고리 심화 분석 경계.
///
/// 기본 통계(총액·카테고리 비율·추이)는 `StatisticsRepository` 가 담당하고,
/// 여기서는 **드릴다운**(브랜드별, 카테고리 상세, 검색, 대시보드)을 다룬다.
abstract interface class AnalyticsRepository {
  /// 대시보드 요약.
  Future<DashboardSummary> dashboard(
    DateRange range, {
    List<String> highlightSubcategories,
  });

  /// 브랜드별 집계 목록.
  Future<List<BrandStat>> brandStats(
    DateRange range, {
    BrandSortBy sortBy = BrandSortBy.amount,
    int limit = 50,
  });

  /// 카테고리 -> 서브카테고리 트리.
  Future<List<CategoryNode>> categoryTree(DateRange range);

  /// 브랜드 상세.
  Future<BrandDetail> brandDetail(
    String brand,
    DateRange range, {
    int trendMonths = 6,
    int transactionLimit = 200,
  });

  /// 카테고리 상세(속한 브랜드 목록 포함).
  ///
  /// [subcategory] 를 주면 그 세부 항목으로 좁힌다.
  /// (요구사항 4의 "카페" 상세처럼 서브카테고리 단위 조회에 사용)
  Future<CategoryDetail> categoryDetail(
    String category,
    DateRange range, {
    String? subcategory,
    int trendMonths = 6,
  });

  /// 브랜드명 검색.
  ///
  /// 브랜드명과 알림 원본 가맹점명을 모두 대상으로 한다.
  Future<List<BrandSearchResult>> searchBrands(
    String query,
    DateRange range, {
    int limit = 50,
  });
}
