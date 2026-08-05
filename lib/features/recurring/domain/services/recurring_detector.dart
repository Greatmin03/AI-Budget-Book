import '../../../transactions/domain/entities/transaction.dart';
import '../entities/recurring_rule.dart';

/// 자동 감지된 정기결제 후보.
class RecurringCandidate {
  const RecurringCandidate({
    required this.brand,
    required this.category,
    required this.subcategory,
    required this.cycle,
    required this.expectedAmount,
    required this.occurrences,
    required this.lastPaidAt,
    required this.nextExpectedAt,
    required this.confidence,
  });

  final String brand;
  final String category;
  final String subcategory;
  final RecurringCycle cycle;

  /// 대표 금액(중앙값).
  final int expectedAmount;

  /// 근거가 된 결제 내역(최신순).
  final List<Transaction> occurrences;

  final DateTime lastPaidAt;
  final DateTime nextExpectedAt;

  /// 0~1. 간격이 규칙적이고 금액이 일정할수록 높다.
  final double confidence;

  int get occurrenceCount => occurrences.length;

  RecurringRule toRule() => RecurringRule(
        brand: brand,
        category: category,
        subcategory: subcategory,
        cycle: cycle,
        expectedAmount: expectedAmount,
        lastPaidAt: lastPaidAt,
        nextExpectedAt: nextExpectedAt,
        source: RecurringSource.auto,
      );

  @override
  String toString() => 'RecurringCandidate($brand, ${cycle.code}, '
      '$expectedAmount원, ${occurrences.length}회, '
      'conf=${confidence.toStringAsFixed(2)})';
}

/// 거래 이력에서 정기결제 패턴을 찾아낸다.
///
/// 순수 함수다. DB 를 보지 않으므로 테스트가 쉽다.
///
/// ## 판정 기준
/// 1. 같은 브랜드 결제가 [minOccurrences]회 이상
/// 2. 금액이 서로 비슷하다 (중앙값 대비 ±15%)
/// 3. 결제 간격이 하나의 주기로 일관되게 설명된다 (주/월/분기/년)
///
/// 세 조건을 모두 만족해야 후보가 된다. 애매하면 후보로 올리지 않는다.
/// 잘못된 후보를 계속 물어보는 것이 놓치는 것보다 더 짜증나기 때문이다.
class RecurringDetector {
  const RecurringDetector();

  /// 후보로 인정하는 최소 결제 횟수.
  ///
  /// 2회는 우연일 수 있다. 3회부터 주기를 말할 수 있다.
  static const int minOccurrences = 3;

  /// 금액 허용 오차(중앙값 대비 비율).
  static const double amountTolerance = 0.15;

  /// 취소/자산이동/수입을 제외한 거래들에서 브랜드별 후보를 찾는다.
  ///
  /// [existingBrands] 에 있는 브랜드는 이미 규칙이 있으므로 건너뛴다.
  List<RecurringCandidate> detect(
    List<Transaction> transactions, {
    Set<String> existingBrands = const <String>{},
  }) {
    final Map<String, List<Transaction>> byBrand =
        <String, List<Transaction>>{};

    for (final Transaction tx in transactions) {
      if (tx.isCancelled) continue;
      if (tx.isAssetTransfer) continue;

      // **수입은 정기결제가 아니다.** 수입도 양수로 저장되므로
      // 아래 `amount <= 0` 검사로는 걸러지지 않는다.
      // 매달 같은 날 같은 금액이 들어오는 월급은 이 앱에서 가장 규칙적인
      // 데이터라서, 막지 않으면 "회사 2,000,000원 매달 결제 예정" 이 뜬다.
      if (tx.isIncome) continue;

      if (tx.amount <= 0) continue;
      final String brand = tx.brand.trim();
      if (brand.isEmpty) continue;
      if (existingBrands.contains(brand)) continue;

      byBrand.putIfAbsent(brand, () => <Transaction>[]).add(tx);
    }

    final List<RecurringCandidate> candidates = <RecurringCandidate>[];
    byBrand.forEach((String brand, List<Transaction> items) {
      final RecurringCandidate? candidate = analyzeBrand(brand, items);
      if (candidate != null) candidates.add(candidate);
    });

    // 확신도 높은 것 먼저.
    candidates.sort(
      (RecurringCandidate a, RecurringCandidate b) =>
          b.confidence.compareTo(a.confidence),
    );
    return candidates;
  }

  /// 한 브랜드의 결제 이력을 분석한다.
  RecurringCandidate? analyzeBrand(String brand, List<Transaction> items) {
    if (items.length < minOccurrences) return null;

    // 오래된 순으로 정렬해 간격을 계산한다.
    final List<Transaction> sorted = List<Transaction>.of(items)
      ..sort(
        (Transaction a, Transaction b) =>
            a.paymentDatetime.compareTo(b.paymentDatetime),
      );

    // 1) 금액 일관성
    final int median = _medianAmount(sorted);
    if (median <= 0) return null;

    final int allowedDiff = (median * amountTolerance).round();
    final bool amountsConsistent = sorted.every(
      (Transaction t) => (t.amount - median).abs() <= allowedDiff,
    );
    if (!amountsConsistent) return null;

    // 2) 간격 일관성
    final List<int> intervals = <int>[];
    for (int i = 1; i < sorted.length; i++) {
      final int days = _dayGap(
        sorted[i - 1].paymentDatetime,
        sorted[i].paymentDatetime,
      );
      // 같은 날 중복 결제는 주기 판단에서 제외한다.
      if (days <= 0) continue;
      intervals.add(days);
    }
    if (intervals.length < minOccurrences - 1) return null;

    // 모든 간격이 같은 주기로 설명되어야 한다.
    final RecurringCycle? cycle = RecurringCycle.forInterval(intervals.first);
    if (cycle == null) return null;
    if (!intervals.every(cycle.matchesInterval)) return null;

    // 3) 확신도: 간격 편차가 작고 횟수가 많을수록 높다.
    final double confidence = _confidence(
      cycle: cycle,
      intervals: intervals,
      occurrences: sorted.length,
    );

    final DateTime lastPaidAt = sorted.last.paymentDatetime;

    return RecurringCandidate(
      brand: brand,
      category: sorted.last.category,
      subcategory: sorted.last.subcategory,
      cycle: cycle,
      expectedAmount: median,
      occurrences: sorted.reversed.toList(),
      lastPaidAt: lastPaidAt,
      nextExpectedAt: cycle.nextAfter(lastPaidAt),
      confidence: confidence,
    );
  }

  /// 날짜 차이(일). 시각 성분은 무시한다.
  static int _dayGap(DateTime a, DateTime b) {
    final DateTime dayA = DateTime(a.year, a.month, a.day);
    final DateTime dayB = DateTime(b.year, b.month, b.day);
    return dayB.difference(dayA).inDays;
  }

  static int _medianAmount(List<Transaction> items) {
    final List<int> amounts = items.map((Transaction t) => t.amount).toList()
      ..sort();
    final int middle = amounts.length ~/ 2;
    if (amounts.length.isOdd) return amounts[middle];
    return ((amounts[middle - 1] + amounts[middle]) / 2).round();
  }

  static double _confidence({
    required RecurringCycle cycle,
    required List<int> intervals,
    required int occurrences,
  }) {
    // 간격이 이상적인 주기에서 얼마나 벗어났는지의 평균.
    double totalDeviation = 0;
    for (final int interval in intervals) {
      totalDeviation += (interval - cycle.approximateDays).abs();
    }
    final double averageDeviation = totalDeviation / intervals.length;

    // clamp 의 정적 반환형이 num 이므로 직접 범위를 제한한다.
    final double regularity =
        1 - _limit01(averageDeviation / (cycle.toleranceDays * 2));

    // 횟수가 많으면 신뢰도가 올라간다(6회에서 최대).
    final double volume = _limit01((occurrences - minOccurrences) / 3);

    return _limit01(regularity * 0.75 + volume * 0.25);
  }

  /// 0.0 ~ 1.0 으로 제한.
  static double _limit01(double value) {
    if (value.isNaN) return 0;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}
