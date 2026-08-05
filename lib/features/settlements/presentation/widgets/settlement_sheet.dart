import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/settlement.dart';

/// 거래의 정산(더치페이)을 관리하는 시트.
///
/// 원본 결제 금액은 읽기 전용으로만 보여 준다. 여기서 바꾸는 것은
/// "누가 얼마를 돌려줬는지" 뿐이다.
class SettlementSheet extends StatefulWidget {
  const SettlementSheet({required this.transaction, super.key});

  final Transaction transaction;

  @override
  State<SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<SettlementSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _peopleController =
      TextEditingController(text: '2');

  List<Settlement> _settlements = const <Settlement>[];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _peopleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int? id = widget.transaction.id;
    if (id == null) {
      setState(() => _isLoading = false);
      return;
    }
    final List<Settlement> items =
        await Injector.instance.manageSettlements.forTransaction(id);
    if (!mounted) return;
    setState(() {
      _settlements = items;
      _isLoading = false;
    });
  }

  int get _settledTotal =>
      _settlements.fold<int>(0, (int sum, Settlement s) => sum + s.amount);

  int get _netAmount => widget.transaction.amount - _settledTotal;

  Future<void> _addSettlement() async {
    final int? amount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (amount == null || amount <= 0) return;

    setState(() => _isSaving = true);
    try {
      await Injector.instance.manageSettlements.add(
        transaction: widget.transaction,
        counterparty: _nameController.text,
        amount: amount,
      );
      _nameController.clear();
      _amountController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 균등 분할: 총 인원을 입력하면 본인 몫을 뺀 나머지를 정산으로 만든다.
  Future<void> _splitEvenly() async {
    final int? people = int.tryParse(_peopleController.text.trim());
    if (people == null || people < 2) return;

    // 본인을 제외한 인원 수만큼 이름 없는 정산을 만든다.
    final List<String> others = List<String>.generate(
      people - 1,
      (int i) => '참여자 ${i + 1}',
    );

    setState(() => _isSaving = true);
    try {
      await Injector.instance.manageSettlements.splitEvenly(
        transaction: widget.transaction,
        counterparties: others,
        totalPeople: people,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _remove(Settlement settlement) async {
    final int? id = settlement.id;
    if (id == null) return;
    await Injector.instance.manageSettlements.remove(id);
    await _load();
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

            Text(
              '정산 · ${tx.displayName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------- 금액 요약
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(context),
              child: Column(
                children: <Widget>[
                  _AmountRow(
                    label: '총 결제',
                    value: Formatters.signedWon(tx.amount),
                    caption: '카드 명세와 동일 (수정 불가)',
                  ),
                  const SizedBox(height: 10),
                  _AmountRow(
                    label: '받은 금액',
                    value: _settledTotal == 0
                        ? '-'
                        : '+${Formatters.won(_settledTotal)}',
                  ),
                  const Divider(height: 20),
                  _AmountRow(
                    label: '실제 부담',
                    value: Formatters.signedWon(_netAmount),
                    emphasize: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------- 정산 목록
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_settlements.isNotEmpty) ...<Widget>[
              Text(
                '받은 내역',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              ..._settlements.map(
                (Settlement s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s.counterparty,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    <String>[
                      Formatters.yearMonthDay(s.settledAt),
                      if (s.isAutoLinked) '입금 자동 연결',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '+${Formatters.won(s.amount)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _remove(s),
                        tooltip: '정산 삭제',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ------------------------------------------------- 정산 추가
            Text(
              '정산 추가',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '이름 (예: 김철수)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '금액',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isSaving ? null : _addSettlement,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '추가',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------- 균등 분할
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '균등 분할',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _peopleController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixText: '명',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isSaving ? null : _splitEvenly,
                  child: const Text('나누기'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '본인 몫을 제외한 인원수만큼 정산을 만듭니다.',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('완료'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.caption,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String? caption;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: emphasize ? 14 : 13,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
                  color: emphasize ? null : scheme.onSurfaceVariant,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: TextStyle(fontSize: 10, color: scheme.outline),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 20 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
