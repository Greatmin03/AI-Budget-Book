import '../../../parsing/domain/entities/notification_source_trait.dart';
import '../../../parsing/domain/entities/parsed_payment.dart';
import '../../../transactions/domain/entities/transaction.dart';

/// 같은 결제를 알린 **두 앱의 정보를 하나로 합친다.**
///
/// ```
/// 토스   더스윙                                  ← 브랜드가 정확하다
/// KB     ... 통신판매_NIC 체크카드출금 3,000 잔액1,264,862
///                                              ↑ 계좌·잔액이 있다
/// ```
///
/// 어느 하나를 버리면 반드시 무언가를 잃는다. **거래는 하나만 남기되
/// 정보는 둘 다 가져온다.**
///
/// ## 왜 미리 모아 두지 않는가
/// 알림 두 개를 기다렸다가 합치려면 타이머가 필요하고, 그 사이 앱이 죽으면
/// 거래가 아예 없어진다. 대신 **먼저 온 알림으로 거래를 만들고, 나중에 온
/// 알림이 그 거래를 채운다.** 결과는 같고 잃을 것이 없다.
class NotificationMerger {
  const NotificationMerger();

  /// [existing] 에 [incoming] 의 정보를 얹은 결과.
  ///
  /// 바꿀 것이 없으면 null 을 돌려준다 — 그때는 저장도 하지 않는다.
  Transaction? merge({
    required Transaction existing,
    required ParsedPayment incoming,
    required String? incomingBrand,
    required String? incomingCategory,
    required String? incomingSubcategory,
  }) {
    final NotificationSourceTrait incomingTrait = incoming.sourceTrait;
    final NotificationSourceTrait existingTrait =
        NotificationSourceTrait.of(existing.sourcePackage);

    Transaction merged = existing;
    bool changed = false;

    // 1) 브랜드는 **더 믿을 수 있는 쪽**을 쓴다.
    //
    //    은행이 준 `쿠팡(쿠페 ` 를 토스가 준 `쿠팡` 으로 바꾸는 것이 이 규칙의
    //    목적이다. 같은 등급이면 먼저 온 것을 유지한다 — 뒤에 온 것이 더
    //    낫다는 근거가 없다.
    //
    //    `merchant_raw` 는 바꾸지 않는다. 먼저 온 알림이 실제로 무엇을
    //    보냈는지가 감사 기록이고, 그것을 나중 알림으로 덮으면 원본이
    //    사라진다. 어느 앱들이 관여했는지는 `mergedSources` 에 남는다.
    if (incomingTrait.brandQuality > existingTrait.brandQuality &&
        incomingBrand != null &&
        incomingBrand.trim().isNotEmpty) {
      merged = merged.copyWith(
        brand: incomingBrand,
        // 브랜드가 바뀌면 그 브랜드로 다시 분류한 결과를 함께 쓴다.
        category: incomingCategory ?? merged.category,
        subcategory: incomingSubcategory ?? merged.subcategory,
        // 좋은 브랜드를 얻었으니 더 물어볼 것이 없다.
        needsReview: incomingCategory == null ? merged.needsReview : false,
      );
      changed = true;
    }

    // 2) 계좌 정보는 **가진 쪽**에서 가져온다. 이미 있으면 덮지 않는다.
    if (incomingTrait.providesAccountDetails) {
      if (merged.accountNumber == null && incoming.accountNumber != null) {
        merged = merged.copyWith(accountNumber: incoming.accountNumber);
        changed = true;
      }
      if (merged.balanceAfter == null && incoming.balanceAfter != null) {
        merged = merged.copyWith(balanceAfter: incoming.balanceAfter);
        changed = true;
      }
    }

    // 3) 카드 이름도 비어 있을 때만 채운다.
    if ((merged.cardName == null || merged.cardName!.trim().isEmpty) &&
        incoming.cardName != null) {
      merged = merged.copyWith(cardName: incoming.cardName);
      changed = true;
    }

    // 4) 어느 앱들이 이 거래를 알렸는지 남긴다.
    final String? source = incoming.sourcePackage;
    if (source != null && !merged.mergedSources.contains(source)) {
      merged = merged.copyWith(
        mergedSources: <String>[
          ...merged.mergedSources,
          if (merged.mergedSources.isEmpty && existing.sourcePackage != null)
            existing.sourcePackage!,
          source,
        ],
      );
      changed = true;
    }

    return changed ? merged : null;
  }
}
