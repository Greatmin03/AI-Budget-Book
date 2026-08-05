import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';

/// 거래 한 줄.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    required this.transaction,
    required this.onTap,
    super.key,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color categoryColor =
        CategoryColors.ofContext(context, transaction.category);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: categoryColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          _initial(transaction.displayName),
          style: TextStyle(
            color: categoryColor,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              transaction.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (transaction.isCancelled) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(label: '취소', color: scheme.error),
          ],
          if (transaction.isInstallment) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(
              label: '${transaction.installmentMonths}개월',
              color: scheme.tertiary,
            ),
          ],
          // 이체/송금은 거래명이 상대방이라는 점을 드러낸다.
          if (transaction.isTransfer) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(label: transaction.method.label, color: scheme.secondary),
          ],
          // 처음 보는 브랜드는 확인이 필요하다는 것을 눈에 띄게 표시한다.
          if (transaction.needsReview) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(label: '분류 필요', color: scheme.primary),
          ],
          if (transaction.hasSettlements) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(
              label: transaction.settlementStatus.label,
              color: scheme.tertiary,
            ),
          ],
          if (transaction.isRecurring) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(label: '🔁 정기결제', color: scheme.primary),
          ],
          // 자산 이동은 소비 통계에 안 들어간다는 점을 목록에서도 알린다.
          if (transaction.isAssetTransfer) ...<Widget>[
            const SizedBox(width: 6),
            _Chip(label: '자산 이동', color: scheme.secondary),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            <String>[
              Formatters.time(transaction.paymentDatetime),
              '${transaction.category} · ${transaction.subcategory}',
              if (transaction.tag != null) '#${transaction.tag}',
              if (transaction.cardName != null) transaction.cardName!,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          // 표시 이름을 따로 지정했으면 원본 거래명을 잃지 않게 함께 보여 준다.
          if (transaction.secondaryName != null)
            Text(
              transaction.secondaryName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          // 원본 결제 금액. 카드 명세와 항상 일치한다.
          //
          // 부호와 색으로 수입/지출을 구분한다. 색만으로 구분하지 않도록
          // 부호를 항상 붙인다(`-4,500원` / `+300,000원`).
          Text(
            _signedText(transaction.amount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              // 정산이 있으면 원본은 보조 정보가 된다.
              decoration: transaction.hasSettlements
                  ? TextDecoration.lineThrough
                  : null,
              color: transaction.hasSettlements
                  ? scheme.onSurfaceVariant
                  : _amountColor(context),
            ),
          ),
          // 실제 부담 금액.
          if (transaction.hasSettlements)
            Text(
              _signedText(transaction.netAmount),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: _amountColor(context),
              ),
            )
          else if (!transaction.isUserClassified)
            Text(
              transaction.classificationSource.label,
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
        ],
      ),
    );
  }

  /// 부호를 붙인 금액.
  ///
  /// 수입은 `+`, 지출은 `-`. 지출도 양수로 저장되므로 부호를 직접 붙인다.
  /// 취소 거래(음수)는 실제로 돌려받은 것이므로 지출인데도 `+` 가 된다.
  String _signedText(int amount) {
    if (amount == 0) return Formatters.won(0);
    final int signed = transaction.isIncome ? amount : -amount;
    return signed > 0
        ? '+${Formatters.won(signed)}'
        : '-${Formatters.won(-signed)}';
  }

  /// 수입은 파랑, 지출은 빨강. 자산 이동은 사라진 돈이 아니므로 중립색.
  Color _amountColor(BuildContext context) {
    if (transaction.isAssetTransfer) return FlowColors.assetTransfer(context);
    return transaction.isIncome
        ? FlowColors.income(context)
        : FlowColors.expense(context);
  }

  /// 아이콘 대신 쓰는 첫 글자.
  static String _initial(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
