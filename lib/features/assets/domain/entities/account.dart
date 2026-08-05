/// 자산 계좌 종류.
enum AccountType {
  checking('checking', '입출금'),
  savings('savings', '적금'),
  cash('cash', '현금'),
  investment('investment', '증권'),
  other('other', '기타');

  const AccountType(this.code, this.label);

  final String code;
  final String label;

  static AccountType fromCode(String? code) {
    for (final AccountType type in AccountType.values) {
      if (type.code == code) return type;
    }
    return AccountType.other;
  }

  /// 자산 화면 표시 순서.
  static List<AccountType> get displayOrder => <AccountType>[
        AccountType.checking,
        AccountType.savings,
        AccountType.cash,
        AccountType.investment,
        AccountType.other,
      ];
}

/// 자산 계좌.
///
/// 은행 연동이 없으므로 **기준 잔액은 사용자가 입력한다.**
/// 현재 잔액은 거기에 기준 시각 이후의 거래를 합산해서 구한다.
///
/// ```
/// 현재 잔액 = balance(기준) + Σ(기준 시각 이후 이 계좌 거래의 부호 있는 금액)
/// ```
///
/// 잔액을 직접 증감시키지 않는 이유는 **어긋날 방법을 없애기 위해서**다.
/// 저장 도중 앱이 죽거나, 거래를 수정/삭제할 때 차액을 되돌리는 데 실패하면
/// 잔액이 영구히 틀어지고 사용자는 그 사실을 알 수 없다.
/// 파생값이면 언제든 다시 계산되므로 그런 상태가 존재할 수 없다.
class Account {
  const Account({
    required this.name,
    required this.type,
    required this.balance,
    this.id,
    this.isActive = true,
    this.sortOrder = 0,
    this.balanceAsOf,
    this.transactionDelta = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final AccountType type;

  /// **기준 잔액.** 사용자가 입력/갱신한다.
  ///
  /// 현재 잔액이 아니다. 화면에는 [currentBalance] 를 보여 준다.
  final int balance;

  final bool isActive;
  final int sortOrder;

  /// 기준 잔액이 유효한 시각. 이 시각 이후의 거래만 반영된다.
  final DateTime? balanceAsOf;

  /// 기준 시각 이후 이 계좌 거래의 합(수입 +, 지출 -, 자산 이동 0).
  ///
  /// 조회할 때 채워 넣는다. 저장되는 컬럼이 아니다.
  final int transactionDelta;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// **화면에 보여 주는 잔액.**
  int get currentBalance => balance + transactionDelta;

  /// 기준 잔액 입력 이후 거래로 움직인 금액이 있는지.
  bool get hasMovement => transactionDelta != 0;

  Account copyWith({
    int? id,
    String? name,
    AccountType? type,
    int? balance,
    bool? isActive,
    int? sortOrder,
    DateTime? balanceAsOf,
    int? transactionDelta,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      balanceAsOf: balanceAsOf ?? this.balanceAsOf,
      transactionDelta: transactionDelta ?? this.transactionDelta,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'Account($name, ${type.label}, 현재 $currentBalance원 '
      '= 기준 $balance + 거래 $transactionDelta)';
}

/// 종류별 묶음.
class AccountGroup {
  const AccountGroup({
    required this.type,
    required this.accounts,
  });

  final AccountType type;
  final List<Account> accounts;

  /// 종류별 **현재** 잔액 합계.
  int get total =>
      accounts.fold<int>(0, (int sum, Account a) => sum + a.currentBalance);
}

/// 자산 화면 전체 데이터.
class AssetOverview {
  const AssetOverview({
    required this.groups,
    required this.totalAssets,
    required this.previousTotal,
    required this.lastRecordedAt,
    this.todayChange = 0,
    this.weekChange = 0,
    this.monthChange = 0,
  });

  const AssetOverview.empty()
      : groups = const <AccountGroup>[],
        totalAssets = 0,
        previousTotal = 0,
        lastRecordedAt = null,
        todayChange = 0,
        weekChange = 0,
        monthChange = 0;

  /// 종류별 계좌 묶음(표시 순서대로).
  final List<AccountGroup> groups;

  /// 총 자산.
  final int totalAssets;

  /// 직전 기록 시점의 총 자산(추이 비교용). 기록이 없으면 0.
  final int previousTotal;

  /// 마지막으로 잔액을 기록한 시각.
  final DateTime? lastRecordedAt;

  /// 오늘 / 이번 주 / 이번 달 잔액 변화(수입 +, 지출 -).
  ///
  /// 스냅샷 비교가 아니라 **거래를 합산한 값**이다. 스냅샷은 사용자가 잔액을
  /// 고친 시점에만 남으므로 "오늘 얼마 썼나" 를 답할 수 없다.
  final int todayChange;
  final int weekChange;
  final int monthChange;

  /// 모든 계좌를 합친 계좌 목록(종류 구분 없이).
  List<Account> get allAccounts =>
      groups.expand((AccountGroup g) => g.accounts).toList();

  bool get isEmpty => groups.isEmpty;

  /// 비교 가능한 이전 기록이 있는지.
  bool get hasComparison => previousTotal != 0;

  /// 총 자산 증감액.
  int get change => totalAssets - previousTotal;

  /// 총 자산 증감률(%). 이전 기록이 0이면 null.
  double? get changeRate {
    if (previousTotal == 0) return null;
    return (totalAssets - previousTotal) / previousTotal * 100;
  }
}
