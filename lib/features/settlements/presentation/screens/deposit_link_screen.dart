import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/deposit.dart';

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

    final Transaction? picked = await showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CandidateSheet(deposit: deposit, candidates: candidates),
    );
    if (picked == null || !mounted) return;

    await Injector.instance.linkDeposit.link(
      deposit: deposit,
      transaction: picked,
    );
    if (!mounted) return;

    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${deposit.counterparty} +${Formatters.won(deposit.amount)} 을 '
          '"${picked.displayName}" 정산으로 연결했습니다.',
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
class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.deposit, required this.candidates});

  final Deposit deposit;
  final List<Transaction> candidates;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${deposit.counterparty} +${Formatters.won(deposit.amount)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '다음 거래와 연결할까요?',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Transaction tx = candidates[index];
              final bool exactMatch = tx.unsettledAmount == deposit.amount;

              return ListTile(
                onTap: () => Navigator.of(context).pop(tx),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '금액 일치',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
          ),
        ),
      ],
    );
  }
}
