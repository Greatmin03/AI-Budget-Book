import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/account.dart';

/// 자산 현황.
///
/// 은행 연동이 없으므로 잔액은 사용자가 입력한다.
/// 대신 갱신할 때마다 기록을 남겨 "지난달 대비" 를 계산한다.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  AssetOverview _overview = const AssetOverview.empty();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final AssetOverview overview =
          await Injector.instance.accounts.overview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('자산 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editAccount([Account? existing]) async {
    final Account? result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountFormSheet(account: existing),
    );
    if (result == null) return;

    try {
      await Injector.instance.accounts.save(result);
      // 새 계좌를 넣었으면 기준 기록을 만들어 둔다.
      await Injector.instance.accounts.recordSnapshot();
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했습니다. 같은 이름의 계좌가 있는지 확인하세요. ($e)')),
      );
    }
  }

  Future<void> _updateBalance(Account account) async {
    final int? id = account.id;
    if (id == null) return;

    final int? value = await showDialog<int>(
      context: context,
      builder: (_) => _BalanceDialog(account: account),
    );
    if (value == null) return;

    await Injector.instance.accounts.updateBalance(id: id, balance: value);
    await _load();
  }

  Future<void> _delete(Account account) async {
    final int? id = account.id;
    if (id == null) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${account.name}을(를) 삭제할까요?'),
        content: const Text('잔액 기록도 함께 삭제됩니다. 거래 내역은 영향받지 않습니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await Injector.instance.accounts.delete(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editAccount,
        icon: const Icon(Icons.add),
        label: const Text('계좌'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: <Widget>[
                  _TotalCard(overview: _overview),
                  if (_overview.isEmpty)
                    _buildEmpty(context)
                  else ...<Widget>[
                    const SizedBox(height: 20),
                    ..._overview.groups.map(
                      (AccountGroup group) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _GroupCard(
                          group: group,
                          onTapAccount: _updateBalance,
                          onEditAccount: _editAccount,
                          onDeleteAccount: _delete,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '금액을 누르면 잔액을 갱신할 수 있습니다.\n'
                      '갱신할 때마다 기록이 남아 자산 추이가 계산됩니다.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(Icons.account_balance_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            '등록된 계좌가 없습니다.\n\n'
            '입출금·적금·현금·증권 계좌를 추가하면\n'
            '총 자산과 변화를 볼 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.overview});

  final AssetOverview overview;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int change = overview.change;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '총 자산',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.won(overview.totalAssets),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          ),
          if (overview.hasComparison) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(
                  change >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${change >= 0 ? '+' : '-'}'
                  '${Formatters.won(change.abs())}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (overview.lastRecordedAt != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    '(${Formatters.yearMonthDay(overview.lastRecordedAt!)} 대비)',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: 12),
          // 거래로 움직인 금액. 스냅샷 비교와 달리 "오늘 얼마 나갔나" 에 답한다.
          Row(
            children: <Widget>[
              _ChangeCell(label: '오늘', amount: overview.todayChange),
              _ChangeCell(label: '이번 주', amount: overview.weekChange),
              _ChangeCell(label: '이번 달', amount: overview.monthChange),
            ],
          ),
        ],
      ),
    );
  }
}

/// 기간별 잔액 변화 한 칸.
class _ChangeCell extends StatelessWidget {
  const _ChangeCell({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          // 부호를 항상 붙인다(색만으로 증감을 표현하지 않는다).
          Text(
            Formatters.signedWonWithPlus(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: amount == 0
                  ? scheme.onSurfaceVariant
                  : FlowColors.net(context, amount),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onTapAccount,
    required this.onEditAccount,
    required this.onDeleteAccount,
  });

  final AccountGroup group;
  final void Function(Account) onTapAccount;
  final void Function(Account) onEditAccount;
  final void Function(Account) onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              group.type.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              Formatters.won(group.total),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTheme.cardSurface(
          context,
          child: Column(
            children: List<Widget>.generate(group.accounts.length, (int i) {
              final Account account = group.accounts[i];
              return Column(
                children: <Widget>[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      account.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _accountSubtitle(account),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          // 기준 잔액이 아니라 거래까지 반영한 현재 잔액.
                          Formatters.won(account.currentBalance),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (String value) {
                            if (value == 'edit') onEditAccount(account);
                            if (value == 'delete') onDeleteAccount(account);
                          },
                          itemBuilder: (_) => const <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Text('이름·종류 수정'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('삭제'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => onTapAccount(account),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  /// 잔액이 어떻게 나온 값인지 한 줄로 설명한다.
  ///
  /// 사용자가 입력한 숫자와 화면의 숫자가 다르면 "왜 다른지" 를 알려 줘야 한다.
  static String _accountSubtitle(Account account) {
    final DateTime? at = account.balanceAsOf ?? account.updatedAt;
    final String stamp =
        at == null ? '' : '${Formatters.yearMonthDay(at)} 기준';

    if (!account.hasMovement) {
      return stamp.isEmpty ? '거래 반영 없음' : stamp;
    }
    final String delta = Formatters.signedWonWithPlus(account.transactionDelta);
    return stamp.isEmpty
        ? '거래 $delta 반영'
        : '$stamp ${Formatters.won(account.balance)} · 거래 $delta';
  }
}

/// 잔액 입력 다이얼로그.
class _BalanceDialog extends StatefulWidget {
  const _BalanceDialog({required this.account});

  final Account account;

  @override
  State<_BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<_BalanceDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.account.currentBalance.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.account.name} 잔액'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          suffixText: '원',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final String digits =
                _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
            Navigator.of(context).pop(int.tryParse(digits) ?? 0);
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 계좌 생성/수정 시트.
class _AccountFormSheet extends StatefulWidget {
  const _AccountFormSheet({this.account});

  final Account? account;

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.account?.name ?? '');
  late final TextEditingController _balanceController = TextEditingController(
    text: widget.account?.balance.toString() ?? '',
  );
  late AccountType _type = widget.account?.type ?? AccountType.checking;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  void _submit() {
    final String digits =
        _balanceController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final int balance = int.tryParse(digits) ?? 0;

    Navigator.of(context).pop(
      (widget.account ??
              Account(name: '', type: _type, balance: 0))
          .copyWith(
        name: _nameController.text.trim(),
        type: _type,
        balance: balance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

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
            Text(
              widget.account == null ? '계좌 추가' : '계좌 수정',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),

            TextField(
              controller: _nameController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: '예: KB 입출금, 청년미래적금',
              ),
            ),
            const SizedBox(height: 14),

            Text(
              '종류',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AccountType.displayOrder
                  .map(
                    (AccountType type) => ChoiceChip(
                      label: Text(type.label),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _balanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '현재 잔액',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: '원',
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _submit : null,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
