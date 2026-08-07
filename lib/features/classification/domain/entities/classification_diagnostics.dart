/// 매핑하지 못한 카카오 업종 한 줄.
class UnmappedPlaceCategory {
  const UnmappedPlaceCategory({
    required this.categoryName,
    required this.hitCount,
    this.sampleMerchant,
    this.lastSeenAt,
  });

  /// 카카오가 준 원본 문자열. 예: `음식점 > 브런치`
  final String categoryName;

  /// 이 업종으로 몇 번 막혔는가. 자주 막히는 것부터 매핑한다.
  final int hitCount;

  /// 이 업종으로 들어온 가맹점 하나. 무엇을 뜻하는지 가늠하는 데 쓴다.
  final String? sampleMerchant;

  final DateTime? lastSeenAt;

  @override
  String toString() => '$categoryName x$hitCount'
      '${sampleMerchant == null ? '' : ' ($sampleMerchant)'}';
}

/// 분류 파이프라인이 실제로 얼마나 일하고 있는지.
///
/// 감이 아니라 숫자로 봐야 어디를 고칠지 알 수 있다. 자동 분류가 잘 되는데
/// 매핑표를 늘리는 것은 낭비고, 카카오가 계속 실패하는데 사전만 손보는 것도
/// 마찬가지다.
class ClassificationDiagnostics {
  const ClassificationDiagnostics({
    required this.totalTransactions,
    required this.bySource,
    required this.needsReview,
    required this.aiPending,
    required this.aiCompleted,
    required this.aiFailed,
    required this.brandLookupsFound,
    required this.brandLookupsNotFound,
    required this.unmapped,
  });

  const ClassificationDiagnostics.empty()
      : totalTransactions = 0,
        bySource = const <String, int>{},
        needsReview = 0,
        aiPending = 0,
        aiCompleted = 0,
        aiFailed = 0,
        brandLookupsFound = 0,
        brandLookupsNotFound = 0,
        unmapped = const <UnmappedPlaceCategory>[];

  final int totalTransactions;

  /// `classification_source` 별 거래 수. seed/rule/llm/user/pending
  final Map<String, int> bySource;

  /// 아직 사용자가 분류를 골라 주지 않은 거래.
  final int needsReview;

  final int aiPending;
  final int aiCompleted;
  final int aiFailed;

  /// 장소 API 로 업종을 알아낸 브랜드 수.
  final int brandLookupsFound;

  /// 조회했지만 못 알아낸 브랜드 수. **이것도 캐시된다**(재조회 방지).
  final int brandLookupsNotFound;

  final List<UnmappedPlaceCategory> unmapped;

  bool get isEmpty => totalTransactions == 0;

  int _source(String code) => bySource[code] ?? 0;

  /// 사용자에게 묻지 않고 분류가 끝난 비율.
  ///
  /// `pending` 은 "아직 아무도 분류하지 않음" 이므로 실패로 센다.
  double get autoClassifiedRate => _rate(
        totalTransactions - _source('pending'),
        totalTransactions,
      );

  /// 브랜드 사전이 해결한 비율. 외부 호출이 전혀 없었던 거래다.
  double get brandExtractorRate => _rate(_source('seed'), totalTransactions);

  /// 장소 API 규칙이 해결한 비율.
  double get placeRuleRate => _rate(_source('rule'), totalTransactions);

  /// AI 대기열까지 간 비율. 낮을수록 좋다 — LLM 은 최후의 수단이다.
  double get aiQueueRate => _rate(
        aiPending + aiCompleted + aiFailed,
        totalTransactions,
      );

  /// 사용자가 직접 고친 비율. 높으면 앞단이 틀리고 있다는 뜻이다.
  double get userCorrectionRate => _rate(_source('user'), totalTransactions);

  /// 장소 API 조회 성공률.
  double get placeLookupRate => _rate(
        brandLookupsFound,
        brandLookupsFound + brandLookupsNotFound,
      );

  static double _rate(int part, int whole) =>
      whole == 0 ? 0 : part / whole;
}
