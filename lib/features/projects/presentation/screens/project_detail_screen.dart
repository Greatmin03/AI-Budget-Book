import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../statistics/domain/entities/statistics.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/project.dart';

/// 프로젝트 상세: 총 지출 + 카테고리별 분해 + 거래 목록.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final int projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  ProjectDetail? _detail;
  List<Transaction> _transactions = const <Transaction>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ProjectDetail detail =
          await Injector.instance.projects.detail(widget.projectId);
      final List<Transaction> txs =
          await Injector.instance.projects.transactionsOf(widget.projectId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _transactions = txs;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('프로젝트 상세 조회 실패', e, stack);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('프로젝트를 삭제할까요?'),
        content: const Text('담겨 있던 거래는 그대로 남고 연결만 끊어집니다.'),
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
    if (ok != true || !mounted) return;

    await Injector.instance.projects.delete(widget.projectId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ProjectDetail? detail = _detail;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.project.name ?? '프로젝트'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '삭제',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: _isLoading && detail == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('불러오지 못했습니다: $_error'))
              : detail == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: <Widget>[
                          _TotalCard(detail: detail),
                          if (detail.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(
                                child: Text(
                                  '아직 담긴 거래가 없습니다.\n'
                                  '거래를 눌러 이 프로젝트를 지정해 보세요.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else ...<Widget>[
                            const SizedBox(height: 24),
                            const _SectionTitle('카테고리별'),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: AppTheme.cardDecoration(context),
                              child: Column(
                                children: detail.byCategory
                                    .map(
                                      (CategoryAmount c) => _CategoryRow(
                                        item: c,
                                        total: detail.total,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _SectionTitle(
                              '거래 내역',
                              subtitle: '${_transactions.length}건',
                            ),
                            const SizedBox(height: 12),
                            AppTheme.cardSurface(
                              context,
                              child: Column(
                                children: List<Widget>.generate(
                                  _transactions.length,
                                  (int i) => Column(
                                    children: <Widget>[
                                      if (i > 0) const Divider(height: 1),
                                      _TransactionRow(
                                        transaction: _transactions[i],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.detail});

  final ProjectDetail detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? ratio = detail.targetRatio;
    final int? remaining = detail.remainingToTarget;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '총 지출',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.signedWon(detail.total),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            <String>[
              '${detail.transactionCount}건',
              if (detail.project.periodLabel != null)
                detail.project.periodLabel!,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (ratio != null) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio > 1 ? 1 : ratio,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: ratio > 1 ? scheme.error : scheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              remaining == null
                  ? ''
                  : remaining >= 0
                      ? '목표까지 ${Formatters.won(remaining)} 남았습니다.'
                      : '목표를 ${Formatters.won(remaining.abs())} 초과했습니다.',
              style: TextStyle(
                fontSize: 12,
                color: (remaining ?? 0) < 0 ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.item, required this.total});

  final CategoryAmount item;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = CategoryColors.ofContext(context, item.name);
    final double ratio = item.ratioOf(total);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Text(
                Formatters.won(item.amount),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio <= 0 ? 0.01 : ratio,
                  child: Container(height: 4, color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(
        transaction.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${Formatters.monthDay(transaction.paymentDatetime)} · '
        '${transaction.category} · ${transaction.subcategory}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Text(
        Formatters.signedWon(transaction.netAmount),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: transaction.isIncome ? scheme.primary : null,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
