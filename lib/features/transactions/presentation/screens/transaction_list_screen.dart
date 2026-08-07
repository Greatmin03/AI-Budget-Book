import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../../assets/presentation/widgets/asset_transfer_sheet.dart';
import '../../../settlements/presentation/widgets/settlement_sheet.dart';
import 'manual_entry_screen.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/usecases/apply_user_correction.dart';
import '../controllers/transaction_list_controller.dart';
import '../widgets/cancellation_link_sheet.dart';
import '../widgets/cancellation_tile.dart';
import '../widgets/transaction_day_header.dart';
import '../widgets/transaction_group_label.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/transaction_period_totals.dart';
import '../widgets/transaction_tile.dart';

/// 월별 거래 목록.
class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  /// 펼쳐 둔 날짜.
  ///
  /// 기본은 전부 접힘이다. 하루 요약을 먼저 보고 궁금한 날만 펼친다.
  /// 한 달치를 한 줄씩 늘어놓으면 스크롤만 길어진다.
  final Set<DateTime> _expandedDays = <DateTime>{};

  void _toggleDay(DateTime day) {
    setState(() {
      if (!_expandedDays.remove(day)) _expandedDays.add(day);
    });
  }
  late final TransactionListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TransactionListController(
      repository: Injector.instance.transactions,
      applyUserCorrection: Injector.instance.applyUserCorrection,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openEditSheet(Transaction transaction) async {
    final TransactionEditResult? result =
        await showModalBottomSheet<TransactionEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          TransactionEditSheet(transaction: transaction),
    );
    if (result == null) return;

    // 시트를 await 한 뒤이므로 화면이 이미 사라졌을 수 있다.
    // 아래에서 context 를 다시 쓰기 전에 확인한다.
    if (!mounted) return;

    if (result.delete) {
      await _controller.delete(transaction);
      return;
    }

    // 정산 / 자산 이동 시트로 넘어가는 경로.
    // 분류 변경은 저장하지 않고 해당 기능만 다룬다.
    if (result.openSettlements) {
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SettlementSheet(transaction: transaction),
      );
      await _controller.load();
      return;
    }

    if (result.openAssetTransfer) {
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AssetTransferSheet(transaction: transaction),
      );
      await _controller.load();
      return;
    }

    // 프로젝트 지정은 분류 학습과 무관하므로 따로 처리한다.
    final int? transactionId = transaction.id;
    if (result.projectChanged && transactionId != null) {
      await Injector.instance.projects.assign(
        transactionId: transactionId,
        projectId: result.projectId,
      );
    }

    final CorrectionResult? outcome = await _controller.correct(
      transaction: transaction,
      category: result.category,
      subcategory: result.subcategory,
      brand: result.brand,
      memo: result.memo,
      displayName: result.displayName,
      tag: result.tag,
      applyToBrand: result.applyToBrand,
      reclassifyPast: result.reclassifyPast,
      amount: result.amount,
      paymentDatetime: result.paymentDatetime,
      direction: result.direction,
      accountId: result.accountId,
      accountName: result.accountName,
      accountChanged: result.accountChanged,
    );

    if (!mounted || outcome == null) return;

    // 학습이 정책상 막힌 경우 왜 막혔는지 알려 준다.
    final String message;
    if (outcome.blockedReason != null) {
      message = '이번 거래만 ${result.category}/${result.subcategory} 로 '
          '변경했습니다. ${outcome.blockedReason}';
    } else if (outcome.learned && result.applyToBrand) {
      message = '"${result.brand}" 브랜드 전체를 '
          '${result.category}/${result.subcategory} 로 학습했습니다.';
    } else if (outcome.learned) {
      message = '${result.category}/${result.subcategory} 로 수정하고 학습했습니다.';
    } else {
      message = '이번 거래만 ${result.category}/${result.subcategory} 로 변경했습니다.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        // 직접 추가 버튼. 자동 수집되지 않는 거래를 넣는 유일한 경로다.
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: _openManualEntry,
            tooltip: '직접 추가',
            child: const Icon(Icons.add),
          ),
          body: Column(
          children: <Widget>[
            PeriodSelector(
              range: _controller.range,
              onChanged: _controller.changeRange,
              trailing: TransactionPeriodTotals(controller: _controller),
            ),
            _FilterTabs(controller: _controller),
            Expanded(child: _buildBody(context)),
          ],
          ),
        );
      },
    );
  }

  Future<void> _openManualEntry() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ManualEntryScreen()),
    );
    if (saved != true) return;
    await _controller.load();
  }

  Widget _tile(Transaction tx) => TransactionTile(
        transaction: tx,
        onTap: () => _openEditSheet(tx),
      );

  /// 취소 목록. 원결제 연결을 관리한다.
  Widget _buildCancellations(BuildContext context) {
    final List<Transaction> items = _controller.transactions;
    if (items.isEmpty) {
      return const _Message(
        icon: Icons.undo_outlined,
        message: '이 기간에는 취소된 거래가 없습니다.',
      );
    }

    return RefreshIndicator(
      onRefresh: _controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          final Transaction cancellation = items[index];
          return CancellationTile(
            cancellation: cancellation,
            original: _controller.originalOf(cancellation),
            onLink: () => _linkCancellation(cancellation),
            onUnlink: () => _unlinkCancellation(cancellation),
          );
        },
      ),
    );
  }

  /// 어느 결제를 취소한 것인지 사용자가 고른다.
  Future<void> _linkCancellation(Transaction cancellation) async {
    final List<Transaction> candidates =
        await _controller.candidatesFor(cancellation);
    if (!mounted) return;

    final Transaction? picked = await showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CancellationLinkSheet(
        cancellation: cancellation,
        candidates: candidates,
      ),
    );
    if (picked == null || !mounted) return;

    await _controller.linkCancellation(
      cancellation: cancellation,
      original: picked,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${picked.displayName}" 결제를 취소로 처리했습니다.'),
      ),
    );
  }

  Future<void> _unlinkCancellation(Transaction cancellation) async {
    await _controller.unlinkCancellation(cancellation);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('연결을 해제했습니다. 원결제가 통계로 돌아옵니다.')),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.isLoading && _controller.transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final String? error = _controller.error;
    if (error != null && _controller.transactions.isEmpty) {
      return _Message(icon: Icons.error_outline, message: error);
    }

    if (_controller.transactions.isEmpty) {
      return const _Message(
        icon: Icons.receipt_long_outlined,
        message: '이 기간에는 기록된 결제가 없습니다.\n'
            '카드 결제 알림이 오면 자동으로 기록됩니다.',
      );
    }

    if (_controller.filter == TransactionFilter.cancelled) {
      return _buildCancellations(context);
    }

    final List<DaySection> sections = _controller.daySections;

    return RefreshIndicator(
      onRefresh: _controller.load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: sections.length,
        itemBuilder: (BuildContext context, int index) {
          final DaySection section = sections[index];
          final bool expanded = _expandedDays.contains(section.day);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TransactionDayHeader(
                day: section.day,
                items: section.all,
                expanded: expanded,
                onToggle: () => _toggleDay(section.day),
              ),

              // 같은 날 안에서 지출 -> 수입 순으로 묶는다.
              if (expanded) ...<Widget>[
                if (section.hasExpenses) ...<Widget>[
                  if (section.needsGroupLabels)
                    const TransactionGroupLabel(label: '지출'),
                  ...section.expenses.map(_tile),
                ],
                if (section.hasIncomes) ...<Widget>[
                  if (section.needsGroupLabels)
                    const TransactionGroupLabel(label: '수입'),
                  ...section.incomes.map(_tile),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// 일반 / 전체 / 취소.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.controller});

  final TransactionListController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int unmatched = controller.unmatchedCancellationCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: <Widget>[
          for (final TransactionFilter f in TransactionFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(f.label),
                    // 원결제를 못 찾은 취소가 있으면 알린다. 그대로 두면
                    // 쓰지도 않은 돈이 통계에 남는다.
                    if (f == TransactionFilter.cancelled && unmatched > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$unmatched',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: scheme.onError,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                selected: controller.filter == f,
                onSelected: (_) => controller.changeFilter(f),
              ),
            ),
        ],
      ),
    );
  }
}
