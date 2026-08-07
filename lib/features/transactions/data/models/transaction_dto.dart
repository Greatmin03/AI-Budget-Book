import '../../../../core/constants/classification_source.dart';
import '../../../../core/database/db_schema.dart';
import '../../../parsing/domain/entities/parsed_payment.dart';
import '../../domain/entities/transaction.dart';

/// `transactions` 테이블 행 <-> [Transaction] 변환.
class TransactionDto {
  const TransactionDto._();

  /// 조회 쿼리가 정산 합계를 담아 주는 별칭 컬럼 이름.
  ///
  /// 실제 테이블 컬럼이 아니라 `settlements` 를 합산한 계산 값이다.
  static const String settledAmountColumn = 'settled_amount';

  static Transaction fromRow(Map<String, Object?> row) {
    return Transaction(
      id: row[DbSchema.tId] as int?,
      merchantId: row[DbSchema.tMerchantId] as int?,
      merchantRaw: (row[DbSchema.tMerchantRaw] as String?) ?? '',
      brand: (row[DbSchema.tBrand] as String?) ?? '',
      userDisplayName: row[DbSchema.tDisplayName] as String?,
      tag: row[DbSchema.tTag] as String?,
      amount: (row[DbSchema.tAmount] as int?) ?? 0,
      category: (row[DbSchema.tCategory] as String?) ?? '기타',
      subcategory: (row[DbSchema.tSubcategory] as String?) ?? '기타',
      method:
          PaymentMethodKind.fromCode(row[DbSchema.tPaymentMethod] as String?),
      cardName: row[DbSchema.tCardName] as String?,
      installmentMonths: (row[DbSchema.tInstallmentMonths] as int?) ?? 0,
      isCancelled: ((row[DbSchema.tIsCancelled] as int?) ?? 0) == 1,
      paymentDatetime: DateTime.fromMillisecondsSinceEpoch(
        (row[DbSchema.tPaymentDatetime] as int?) ?? 0,
      ),
      rawNotification: (row[DbSchema.tRawNotification] as String?) ?? '',
      sourcePackage: row[DbSchema.tSourcePackage] as String?,
      memo: row[DbSchema.tMemo] as String?,
      fingerprint: (row[DbSchema.tFingerprint] as String?) ?? '',
      classificationSource: ClassificationSource.fromCode(
        row[DbSchema.tClassificationSource] as String?,
      ),
      needsReview: ((row[DbSchema.tNeedsReview] as int?) ?? 0) == 1,
      // 조회 쿼리가 정산 합계를 함께 계산해 준 경우에만 값이 들어온다.
      settledAmount: _toInt(row[settledAmountColumn]),
      recurringRuleId: row[DbSchema.tRecurringRuleId] as int?,
      isAssetTransfer: ((row[DbSchema.tIsAssetTransfer] as int?) ?? 0) == 1,
      entrySource: EntrySource.fromCode(row[DbSchema.tEntrySource] as String?),
      direction:
          TransactionDirection.fromCode(row[DbSchema.tDirection] as String?),
      account: row[DbSchema.tAccount] as String?,
      accountId: row[DbSchema.tAccountId] as int?,
      accountNumber: row[DbSchema.tAccountNumber] as String?,
      balanceAfter: row[DbSchema.tBalanceAfter] as int?,
      mergedSources: _splitSources(row[DbSchema.tMergedSources] as String?),
      cancelsTransactionId: row[DbSchema.tCancelsTransactionId] as int?,
      assetKind: row[DbSchema.tAssetKind] as String?,
      aiStatus: AiStatus.fromCode(row[DbSchema.tAiStatus] as String?),
      aiProcessedAt: _toDate(row[DbSchema.tAiProcessedAt]),
      projectId: row[DbSchema.tProjectId] as int?,
      createdAt: _toDate(row[DbSchema.tCreatedAt]),
      updatedAt: _toDate(row[DbSchema.tUpdatedAt]),
    );
  }

  static Map<String, Object?> toRow(
    Transaction tx, {
    required DateTime now,
    bool includeCreatedAt = true,
  }) {
    return <String, Object?>{
      DbSchema.tMerchantId: tx.merchantId,
      DbSchema.tMerchantRaw: tx.merchantRaw,
      DbSchema.tBrand: tx.brand,
      DbSchema.tDisplayName: tx.userDisplayName,
      DbSchema.tTag: tx.tag,
      DbSchema.tAmount: tx.amount,
      DbSchema.tCategory: tx.category,
      DbSchema.tSubcategory: tx.subcategory,
      // 표시 문구가 아니라 안정적인 코드를 저장한다.
      DbSchema.tPaymentMethod: tx.method.code,
      DbSchema.tCardName: tx.cardName,
      DbSchema.tInstallmentMonths: tx.installmentMonths,
      DbSchema.tIsCancelled: tx.isCancelled ? 1 : 0,
      DbSchema.tPaymentDatetime: tx.paymentDatetime.millisecondsSinceEpoch,
      DbSchema.tRawNotification: tx.rawNotification,
      DbSchema.tSourcePackage: tx.sourcePackage,
      DbSchema.tMemo: tx.memo,
      DbSchema.tFingerprint: tx.fingerprint,
      DbSchema.tClassificationSource: tx.classificationSource.code,
      DbSchema.tNeedsReview: tx.needsReview ? 1 : 0,
      DbSchema.tRecurringRuleId: tx.recurringRuleId,
      DbSchema.tIsAssetTransfer: tx.isAssetTransfer ? 1 : 0,
      DbSchema.tEntrySource: tx.entrySource.code,
      DbSchema.tDirection: tx.direction.code,
      DbSchema.tAccount: tx.account,
      DbSchema.tAccountId: tx.accountId,
      DbSchema.tAccountNumber: tx.accountNumber,
      DbSchema.tBalanceAfter: tx.balanceAfter,
      DbSchema.tMergedSources:
          tx.mergedSources.isEmpty ? null : tx.mergedSources.join(','),
      DbSchema.tCancelsTransactionId: tx.cancelsTransactionId,
      DbSchema.tAssetKind: tx.assetKind,
      DbSchema.tAiStatus: tx.aiStatus.code,
      DbSchema.tAiProcessedAt: tx.aiProcessedAt?.millisecondsSinceEpoch,
      DbSchema.tProjectId: tx.projectId,
      if (includeCreatedAt)
        DbSchema.tCreatedAt: (tx.createdAt ?? now).millisecondsSinceEpoch,
      DbSchema.tUpdatedAt: now.millisecondsSinceEpoch,
    };
  }

  static DateTime? _toDate(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}

/// 쉼표로 이어 둔 패키지 목록을 되돌린다.
List<String> _splitSources(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  return raw
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
}
