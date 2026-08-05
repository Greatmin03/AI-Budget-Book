/// 반복 주기.
enum RecurringCycle {
  weekly('weekly', '매주', 7),
  monthly('monthly', '매월', 30),
  quarterly('quarterly', '3개월마다', 91),
  yearly('yearly', '매년', 365);

  const RecurringCycle(this.code, this.label, this.approximateDays);

  final String code;
  final String label;

  /// 감지에 쓰는 대략적인 간격(일).
  final int approximateDays;

  /// 간격 판정 허용 오차(일).
  ///
  /// 월 주기는 28~31일로 흔들리므로 넉넉하게 잡는다.
  int get toleranceDays {
    switch (this) {
      case RecurringCycle.weekly:
        return 2;
      case RecurringCycle.monthly:
        return 5;
      case RecurringCycle.quarterly:
        return 10;
      case RecurringCycle.yearly:
        return 20;
    }
  }

  bool matchesInterval(int days) =>
      (days - approximateDays).abs() <= toleranceDays;

  /// [from] 기준 다음 예정일.
  ///
  /// 월/년 주기는 단순히 일수를 더하지 않고 **같은 날짜**를 유지한다.
  /// (15일 결제가 매달 15일로 유지되어야 한다)
  DateTime nextAfter(DateTime from) {
    switch (this) {
      case RecurringCycle.weekly:
        return from.add(const Duration(days: 7));
      case RecurringCycle.monthly:
        return _addMonths(from, 1);
      case RecurringCycle.quarterly:
        return _addMonths(from, 3);
      case RecurringCycle.yearly:
        return _addMonths(from, 12);
    }
  }

  /// 달을 더한다. 짧은 달로 넘어갈 때 날짜를 잘라 준다.
  ///
  /// 1월 31일 + 1개월 = 2월 28일. (`DateTime(2026, 2, 31)` 은 3월 3일이 된다)
  static DateTime _addMonths(DateTime from, int months) {
    final int targetYear = from.year + ((from.month - 1 + months) ~/ 12);
    final int targetMonth = ((from.month - 1 + months) % 12) + 1;
    final int lastDayOfTarget = DateTime(targetYear, targetMonth + 1, 0).day;
    final int day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
    return DateTime(targetYear, targetMonth, day, from.hour, from.minute);
  }

  static RecurringCycle fromCode(String? code) {
    for (final RecurringCycle cycle in RecurringCycle.values) {
      if (cycle.code == code) return cycle;
    }
    return RecurringCycle.monthly;
  }

  /// 간격(일)에 가장 잘 맞는 주기. 없으면 null.
  static RecurringCycle? forInterval(int days) {
    for (final RecurringCycle cycle in RecurringCycle.values) {
      if (cycle.matchesInterval(days)) return cycle;
    }
    return null;
  }
}

/// 정기결제 규칙.
///
/// 거래를 미리 만들어 두지 않는다. "예정" 은 이 규칙에서 계산해 보여 주고,
/// 실제 결제 알림이 오면 그때 거래가 생기며 규칙에 연결된다.
class RecurringRule {
  const RecurringRule({
    required this.brand,
    required this.category,
    required this.subcategory,
    required this.cycle,
    required this.expectedAmount,
    this.id,
    this.lastPaidAt,
    this.nextExpectedAt,
    this.isActive = true,
    this.source = RecurringSource.auto,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String brand;
  final String category;
  final String subcategory;
  final RecurringCycle cycle;

  /// 예상 금액. 실제 결제액은 조금씩 다를 수 있다.
  final int expectedAmount;

  final DateTime? lastPaidAt;
  final DateTime? nextExpectedAt;
  final bool isActive;
  final RecurringSource source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 금액 허용 오차(비율). 통신비/환율 변동을 흡수한다.
  static const double amountTolerance = 0.15;

  /// 이 금액이 이 규칙의 결제로 볼 만한가.
  bool matchesAmount(int amount) {
    if (expectedAmount == 0) return false;
    final int diff = (amount.abs() - expectedAmount.abs()).abs();
    return diff <= (expectedAmount.abs() * amountTolerance).round();
  }

  /// 예정일이 지났는데 결제가 안 들어왔는지.
  bool isOverdue([DateTime? now]) {
    final DateTime? next = nextExpectedAt;
    if (next == null || !isActive) return false;
    final DateTime reference = now ?? DateTime.now();
    // 며칠 늦는 것은 흔하므로 여유를 준다.
    return reference.isAfter(next.add(Duration(days: cycle.toleranceDays)));
  }

  /// 예정일까지 남은 일수. 지났으면 음수.
  int? daysUntilNext([DateTime? now]) {
    final DateTime? next = nextExpectedAt;
    if (next == null) return null;
    final DateTime reference = now ?? DateTime.now();
    final DateTime today =
        DateTime(reference.year, reference.month, reference.day);
    final DateTime target = DateTime(next.year, next.month, next.day);
    return target.difference(today).inDays;
  }

  RecurringRule copyWith({
    int? id,
    String? category,
    String? subcategory,
    RecurringCycle? cycle,
    int? expectedAmount,
    DateTime? lastPaidAt,
    DateTime? nextExpectedAt,
    bool? isActive,
  }) {
    return RecurringRule(
      id: id ?? this.id,
      brand: brand,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      cycle: cycle ?? this.cycle,
      expectedAmount: expectedAmount ?? this.expectedAmount,
      lastPaidAt: lastPaidAt ?? this.lastPaidAt,
      nextExpectedAt: nextExpectedAt ?? this.nextExpectedAt,
      isActive: isActive ?? this.isActive,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() => 'RecurringRule($brand, ${cycle.code}, '
      '$expectedAmount원, next=$nextExpectedAt)';
}

enum RecurringSource {
  /// 자동 감지에서 등록.
  auto('auto', '자동 감지'),

  /// 사용자가 직접 등록.
  user('user', '직접 등록');

  const RecurringSource(this.code, this.label);

  final String code;
  final String label;

  static RecurringSource fromCode(String? code) =>
      code == 'user' ? RecurringSource.user : RecurringSource.auto;
}
