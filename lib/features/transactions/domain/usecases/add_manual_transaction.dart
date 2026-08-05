import '../../../../core/constants/classification_source.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../parsing/domain/entities/parsed_payment.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// 자동으로 수집되지 않는 거래를 직접 추가한다.
///
/// 현금 사용, 중고거래, 개인 간 거래, 누락된 거래 등.
///
/// 알림 기반 거래와 같은 테이블에 저장하되 `entrySource` 로 구분한다.
/// 통계는 두 경로를 구분하지 않는다(둘 다 실제 지출이므로).
class AddManualTransaction {
  const AddManualTransaction(this._transactions);

  final TransactionRepository _transactions;

  Future<Transaction> call({
    required DateTime date,
    required int amount,
    required TransactionDirection direction,
    required String category,
    required String subcategory,
    required String brand,
    String? account,
    int? accountId,
    String? memo,
    int? projectId,
    bool isAssetTransfer = false,
    AssetKind? assetKind,
    PaymentMethodKind method = PaymentMethodKind.cash,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('금액은 0보다 커야 합니다.');
    }
    final String trimmedBrand = brand.trim();
    if (trimmedBrand.isEmpty) {
      throw ArgumentError('내용(브랜드)을 입력해야 합니다.');
    }

    final DateTime now = DateTime.now();

    final Transaction transaction = Transaction(
      merchantRaw: trimmedBrand,
      brand: trimmedBrand,
      // 수입도 양수로 저장하고 direction 으로 구분한다.
      // 부호를 뒤집으면 "취소 거래(음수)" 와 구분이 안 된다.
      amount: amount,
      category: category,
      subcategory: subcategory,
      method: direction.isIncome ? PaymentMethodKind.unknown : method,
      paymentDatetime: date,
      // 직접 입력은 원본 알림이 없다. 무엇을 근거로 만든 거래인지 남긴다.
      rawNotification: '직접 입력 (${now.toIso8601String()})',
      fingerprint: _manualFingerprint(now),
      classificationSource: ClassificationSource.user,
      entrySource: EntrySource.manual,
      direction: direction,
      account: account?.trim().isEmpty ?? true ? null : account!.trim(),
      // 계좌를 고르면 그 계좌 잔액에 자동 반영된다(수입 +, 지출 -).
      accountId: accountId,
      memo: memo?.trim().isEmpty ?? true ? null : memo!.trim(),
      projectId: projectId,
      isAssetTransfer: isAssetTransfer,
      assetKind: isAssetTransfer
          ? (assetKind ?? AssetKind.saving).code
          : null,
      // 사용자가 직접 고른 분류이므로 확인이 필요하지 않다.
      needsReview: false,
    );

    final Transaction? saved = await _transactions.insert(transaction);
    if (saved == null) {
      // fingerprint 가 시각 기반이라 사실상 발생하지 않지만,
      // 조용히 실패하면 사용자는 저장된 줄 안다.
      throw StateError('거래를 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }

    AppLogger.i('직접 입력: ${direction.label} $trimmedBrand $amount원'
        '${accountId == null ? '' : ' (계좌 반영)'}');
    return saved;
  }

  /// 직접 입력 거래의 중복 방지 키.
  ///
  /// 알림 거래는 (가맹점+금액+시각)으로 중복을 판단하지만, 직접 입력은
  /// 같은 가게에서 같은 금액을 두 번 쓰는 것이 정상이다.
  /// 그래서 생성 시각(밀리초)으로 항상 고유하게 만든다.
  static String _manualFingerprint(DateTime createdAt) =>
      'manual|${createdAt.microsecondsSinceEpoch}';
}
