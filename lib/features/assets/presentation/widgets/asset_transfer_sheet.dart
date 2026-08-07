import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/utils/formatters.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/asset_transfer.dart';

/// 거래를 자산 이동(적금 납입 등)으로 표시하는 시트.
///
/// 표시하면 **소비 통계에서 제외**된다. 거래 자체는 그대로 남는다.
class AssetTransferSheet extends StatefulWidget {
  const AssetTransferSheet({required this.transaction, super.key});

  final Transaction transaction;

  @override
  State<AssetTransferSheet> createState() => _AssetTransferSheetState();
}

class _AssetTransferSheetState extends State<AssetTransferSheet> {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  AssetTransfer? _existing;
  List<String> _knownAccounts = const <String>[];

  /// 등록된 계좌. 받는 곳을 여기서 고르면 그 계좌 잔액이 실제로 늘어난다.
  List<Account> _accounts = const <Account>[];

  /// 고른 받는 계좌. null 이면 추적하지 않는 곳으로 나간 것이다.
  int? _toAccountId;
  bool _isLoading = true;
  bool _isSaving = false;

  /// 저축 / 청약 / 투자. 자산 통계를 나누는 기준이다.
  AssetKind _kind = AssetKind.saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int? id = widget.transaction.id;
    if (id == null) {
      setState(() => _isLoading = false);
      return;
    }

    final AssetTransfer? existing =
        await Injector.instance.assets.findByTransaction(id);
    final List<String> accounts =
        await Injector.instance.assets.knownAccounts();
    final List<Account> registered = await Injector.instance.accounts.findAll();
    if (!mounted) return;

    setState(() {
      _existing = existing;
      _knownAccounts = accounts;
      _accounts = registered;
      // 이름이 정확히 같은 계좌가 있으면 미리 골라 둔다. 대부분의 경우
      // 사용자가 한 번 더 고르지 않아도 된다.
      _toAccountId = existing?.toAccountId ??
          _accounts
              .where((Account a) => a.name == widget.transaction.displayName)
              .map((Account a) => a.id)
              .firstOrNull;
      _kind = widget.transaction.assetKindValue ?? AssetKind.saving;
      _fromController.text = existing?.fromAccount ?? '입출금 계좌';
      // 적금 이름은 보통 가맹점명으로 들어온다.
      _toController.text = existing?.toAccount ?? widget.transaction.displayName;
      _noteController.text = existing?.note ?? '';
      _isLoading = false;
    });
  }

  bool get _canSave =>
      _fromController.text.trim().isNotEmpty &&
      _toController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final int? id = widget.transaction.id;
    if (id == null) return;

    setState(() => _isSaving = true);
    try {
      await Injector.instance.assets.markTransaction(
        transactionId: id,
        fromAccount: _fromController.text,
        toAccount: _toController.text,
        toAccountId: _toAccountId,
        amount: widget.transaction.amount.abs(),
        transferredAt: widget.transaction.paymentDatetime,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        kind: _kind,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _unmark() async {
    final int? id = widget.transaction.id;
    if (id == null) return;

    setState(() => _isSaving = true);
    try {
      await Injector.instance.assets.unmarkTransaction(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Transaction tx = widget.transaction;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              '자산 이동',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${tx.displayName} · ${Formatters.signedWon(tx.amount)}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '적금 납입처럼 내 계좌 사이를 옮긴 돈은 소비가 아닙니다.\n'
                '자산 이동으로 표시하면 소비 통계에서 제외되고, '
                '현금 흐름과 자산 현황에는 남습니다.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              const _Label('종류'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AssetKind.values
                    .map(
                      (AssetKind kind) => ChoiceChip(
                        label: Text(kind.label),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 6),
              Text(
                '어느 종류든 소비 통계에서는 제외됩니다. '
                '자산 통계에서만 나눠 보여 줍니다.',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
              const SizedBox(height: 14),

              const _Label('보낸 곳'),
              const SizedBox(height: 6),
              TextField(
                controller: _fromController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '예: KB 입출금',
                ),
              ),
              const SizedBox(height: 14),

              const _Label('받는 곳'),
              const SizedBox(height: 6),
              TextField(
                controller: _toController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '예: KB 청년미래적금',
                ),
              ),

              // 등록된 계좌를 고르면 그 계좌 잔액이 실제로 늘어난다.
              // 이름만 적으면 나간 쪽만 줄고 받는 쪽은 늘지 않는다.
              if (_accounts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                const _Label('어느 계좌로 들어가나요?'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final Account account in _accounts)
                      ChoiceChip(
                        label: Text(
                          account.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: _toAccountId == account.id,
                        onSelected: (_) => setState(() {
                          _toAccountId = account.id;
                          _toController.text = account.name;
                        }),
                      ),
                    ChoiceChip(
                      label: const Text(
                        '등록 안 된 곳',
                        style: TextStyle(fontSize: 11),
                      ),
                      selected: _toAccountId == null,
                      onSelected: (_) => setState(() => _toAccountId = null),
                    ),
                  ],
                ),
                if (_toAccountId == null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '받는 계좌를 고르지 않으면 나간 계좌만 줄어듭니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],

              // 이전에 쓴 계좌 이름을 빠르게 넣을 수 있게 한다.
              if (_knownAccounts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _knownAccounts
                      .take(8)
                      .map(
                        (String account) => ActionChip(
                          label: Text(
                            account,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => setState(
                            () => _toController.text = account,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),

              const _Label('메모'),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '선택 사항',
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: <Widget>[
                  if (_existing != null || tx.isAssetTransfer) ...<Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _unmark,
                        child: const Text('표시 해제'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: (_canSave && !_isSaving) ? _save : null,
                      child: Text(_existing == null ? '자산 이동으로 표시' : '수정'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
