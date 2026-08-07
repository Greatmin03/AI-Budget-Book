import '../../../parsing/domain/entities/parsed_payment.dart';
import '../entities/transaction.dart';

/// 취소가 되돌린 원결제를 좁힌다.
///
/// ## 카드 이름으로는 맞출 수 없다
/// 같은 물리 카드를 앱마다 다르게 부른다.
///
/// ```
/// 토스   card_name = 토스
/// 은행   card_name = KB국민은행
/// ```
///
/// 카드 이름을 **조건**으로 걸면 영영 못 만난다. 그래서 조건이 아니라
/// **좁히는 단서**로만 쓴다 — 좁혔더니 아무것도 안 남으면 그 단서는 쓸모가
/// 없었다는 뜻이므로 되돌린다.
///
/// ## 계좌번호가 가장 확실하다
/// 은행만 주는 값이고, 결제와 취소가 같은 계좌에서 일어나므로 정확히
/// 일치한다. 사용자가 "국민은행 알림을 기준으로" 라고 한 것이 이 뜻이다.
class CancellationMatcher {
  const CancellationMatcher();

  /// [candidates] 를 믿을 수 있는 순서대로 좁힌다.
  ///
  /// 자동 연결과 화면의 후보 목록이 **같은 답**을 봐야 한다. 다르면
  /// "왜 자동으로 안 됐지" 를 설명할 수 없다.
  List<Transaction> narrow(
    Transaction cancellation,
    List<Transaction> candidates,
  ) {
    List<Transaction> pool = candidates;

    // 1) 계좌번호 — 가장 확실하다.
    pool = _prefer(
      pool,
      (Transaction t) => t.accountNumber == cancellation.accountNumber,
      when: (cancellation.accountNumber ?? '').isNotEmpty,
    );

    // 2) 카드 이름 — 같은 앱끼리는 이름이 같다.
    pool = _prefer(
      pool,
      (Transaction t) => t.cardName == cancellation.cardName,
      when: (cancellation.cardName ?? '').isNotEmpty,
    );

    return pool;
  }

  /// **자동으로 이어도 되는** 원결제. 확실하지 않으면 null.
  ///
  /// [narrow] 보다 한 단계 더 엄격하다. 화면에서는 사용자가 보고 고르지만,
  /// 자동 연결은 아무도 확인하지 않는다 — 틀리면 엉뚱한 결제가 통계에서
  /// 조용히 사라지고 알아챌 방법이 없다.
  ///
  /// 취소 알림이 가맹점을 알려 줬다면(토스 등) **반드시 일치해야 한다.**
  /// 은행은 알려 주지 않으므로 이 조건이 적용되지 않는다.
  Transaction? autoLinkTarget(
    Transaction cancellation,
    List<Transaction> candidates,
  ) {
    List<Transaction> pool = narrow(cancellation, candidates);

    if (cancellation.merchantRaw != ParsedPayment.unknownMerchantLabel) {
      pool = pool
          .where((Transaction t) => t.brand == cancellation.brand)
          .toList();
    }

    return pool.length == 1 ? pool.single : null;
  }

  /// 후보를 걸러 보되, **아무것도 안 남으면 되돌린다.**
  ///
  /// 그 단서가 이 거래에는 없었다는 뜻이다. 없는 단서로 후보를 0으로 만들면
  /// 이을 수 있는 것도 못 잇는다.
  static List<Transaction> _prefer(
    List<Transaction> pool,
    bool Function(Transaction) test, {
    required bool when,
  }) {
    if (!when) return pool;
    final List<Transaction> narrowed = pool.where(test).toList();
    return narrowed.isEmpty ? pool : narrowed;
  }
}
