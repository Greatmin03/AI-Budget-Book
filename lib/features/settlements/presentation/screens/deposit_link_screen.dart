import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/deposit.dart';
import '../../domain/usecases/manage_settlements.dart';

/// 입금 알림을 미정산 거래와 연결하는 화면.
///
/// 브랜드 학습과는 완전히 분리된 흐름이다.
/// `홍길동 10,000원 입금` 은 브랜드가 되지 않지만, 정산 후보로는 쓸 수 있다.
class DepositLinkScreen extends StatefulWidget {
  const DepositLinkScreen({super.key});

  @override
  State<DepositLinkScreen> createState() => _DepositLinkScreenState();
}

class _DepositLinkScreenState extends State<DepositLinkScreen> {
  List<Deposit> _deposits = const <Deposit>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final List<Deposit> items =
          await Injector.instance.deposits.findPending();
      if (!mounted) return;
      setState(() {
        _deposits = items;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('입금 목록 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openCandidates(Deposit deposit) async {
    final List<Transaction> candidates =
        await Injector.instance.linkDeposit.findCandidates(deposit);
    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('연결할 만한 미정산 거래가 없습니다.'),
        ),
      );
      return;
    }

    final List<Transaction>? picked =
        await showModalBottomSheet<List<Transaction>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CandidateSheet(deposit: deposit, candidates: candidates),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    final DepositAllocation result;
    try {
      result = await Injector.instance.linkDeposit.linkMany(
        deposit: deposit,
        transactions: picked,
      );
    } on Object catch (e, stack) {
      AppLogger.e('입금 연결 실패', e, stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('연결하지 못했습니다. ($e)')));
      return;
    }
    if (!mounted) return;

    await _load();
    if (!mounted) return;

    // 남은 금액이 있으면 반드시 알린다. 조용히 넘어가면 사용자는 전액이
    // 정산된 줄 안다.
    final String leftover = result.isFullyAllocated
        ? ''
        : ' (${Formatters.won(result.unallocated)}은 남았습니다)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${deposit.counterparty} +${Formatters.won(deposit.amount)} 을 '
          '거래 ${result.settlements.length}건에 연결했습니다.$leftover',
        ),
      ),
    );
  }

  Future<void> _ignore(Deposit deposit) async {
    await Injector.instance.linkDeposit.ignore(deposit);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('입금 연결'),
        actions: <Widget>[
          if (_deposits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_deposits.length}건',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deposits.isEmpty
              ? _buildEmpty(context)
              : ListView.separated(
                  itemCount: _deposits.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) return _buildHeader(context);
                    final Deposit deposit = _deposits[index - 1];
                    return ListTile(
                      title: Text(
                        deposit.counterparty,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        <String>[
                          Formatters.monthDay(deposit.depositedAt),
                          Formatters.time(deposit.depositedAt),
                          if (deposit.bankName != null) deposit.bankName!,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '+${Formatters.won(deposit.amount)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: '정산이 아님',
                            onPressed: () => _ignore(deposit),
                          ),
                        ],
                      ),
                      onTap: () => _openCandidates(deposit),
                    );
                  },
                ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerLow,
      child: Text(
        '받은 돈입니다. 어떤 결제의 정산인지 연결하면\n'
        '그 거래의 실제 부담 금액이 줄어듭니다.',
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            const Text('연결을 기다리는 입금이 없습니다.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// 후보 거래 선택 시트.
///
/// **여러 건을 고를 수 있다.** 친구가 한 번에 보낸 돈이 결제 두 건을 덮는
/// 경우가 흔하다. 하나만 고를 수 있으면 나머지는 영영 미정산으로 남아
/// 실제 부담이 부풀어 보인다.
class _CandidateSheet extends StatefulWidget {
  const _CandidateSheet({required this.deposit, required this.candidates});

  final Deposit deposit;
  final List<Transaction> candidates;

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  /// 고른 거래의 id.
  ///
  /// 배분은 **화면에 보이는 순서**대로 한다. 고른 순서로 하면 목록에서 본
  /// 것과 금액이 다르게 붙어 혼란스럽다.
  final Set<int> _selected = <int>{};

  List<Transaction> get _picked => widget.candidates
      .where((Transaction t) => _selected.contains(t.id))
      .toList();

  /// 위에서부터 채웠을 때 각 거래에 붙을 금액.
  ///
  /// 미리 보여 주지 않으면 "왜 이 거래에 이 금액이 붙었지" 를 나중에 알게 된다.
  Map<int, int> get _allocation {
    final Map<int, int> result = <int, int>{};
    int remaining = widget.deposit.amount;

    for (final Transaction tx in _picked) {
      if (remaining <= 0) break;
      final int room = tx.unsettledAmount;
      final int amount = room < remaining ? room : remaining;
      if (amount <= 0) continue;
      result[tx.id!] = amount;
      remaining -= amount;
    }
    return result;
  }

  int get _allocated =>
      _allocation.values.fold<int>(0, (int sum, int n) => sum + n);

  int get _unallocated => widget.deposit.amount - _allocated;

  void _toggle(Transaction tx) {
    final int? id = tx.id;
    if (id == null) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Map<int, int> allocation = _allocation;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${widget.deposit.counterparty} '
                '+${Formatters.won(widget.deposit.amount)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '연결할 거래를 고르세요. 여러 건을 고르면 위에서부터 채웁니다.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Transaction tx = widget.candidates[index];
              final int? amount = allocation[tx.id];
              final bool exactMatch =
                  tx.unsettledAmount == widget.deposit.amount;

              return CheckboxListTile(
                value: _selected.contains(tx.id),
                onChanged: (_) => _toggle(tx),
                controlAffinity: ListTileControlAffinity.leading,
                title: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        tx.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (exactMatch) ...<Widget>[
                      const SizedBox(width: 6),
                      _Badge(
                        label: '금액 일치',
                        color: scheme.primaryContainer,
                        onColor: scheme.onPrimaryContainer,
                      ),
                    ],
                    // 실제로 얼마가 붙는지 그 자리에서 보여 준다.
                    if (amount != null) ...<Widget>[
                      const SizedBox(width: 6),
                      _Badge(
                        label: Formatters.won(amount),
                        color: scheme.secondaryContainer,
                        onColor: scheme.onSecondaryContainer,
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  '${Formatters.monthDay(tx.paymentDatetime)} · '
                  '${tx.category} · '
                  '총 ${Formatters.won(tx.amount)} · '
                  '남은 ${Formatters.won(tx.unsettledAmount)}',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: <Widget>[
              if (_selected.isNotEmpty) ...<Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '배분 ${Formatters.won(_allocated)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    // 남은 돈을 조용히 마지막 거래에 몰아붙이지 않는다.
                    // 부담을 실제보다 적게 보이게 만드는 쪽이 더 나쁘다.
                    if (_unallocated > 0)
                      Text(
                        '남음 ${Formatters.won(_unallocated)}',
                        style: TextStyle(fontSize: 13, color: scheme.error),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: allocation.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_picked),
                      child: Text(
                        allocation.length <= 1
                            ? '연결'
                            : '연결 (${allocation.length}건)',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 거래 줄에 붙는 작은 표식.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: onColor,
        ),
      ),
    );
  }
}
