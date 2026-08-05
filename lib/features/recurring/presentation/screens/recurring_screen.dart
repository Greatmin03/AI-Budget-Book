import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/recurring_rule.dart';
import '../../domain/services/recurring_detector.dart';

/// 정기결제 관리 화면.
///
/// 위쪽에 자동 감지된 후보를, 아래에 등록된 규칙을 보여 준다.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<RecurringRule> _rules = const <RecurringRule>[];
  List<RecurringCandidate> _candidates = const <RecurringCandidate>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final List<RecurringRule> rules =
          await Injector.instance.recurring.findAll();
      final List<RecurringCandidate> candidates =
          await Injector.instance.recurring.detectCandidates();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _candidates = candidates;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('정기결제 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _register(RecurringCandidate candidate) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('정기결제로 등록할까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              candidate.brand,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('${candidate.cycle.label} · '
                '${Formatters.won(candidate.expectedAmount)}'),
            const SizedBox(height: 4),
            Text(
              '최근 ${candidate.occurrenceCount}회 결제를 근거로 추정했습니다.\n'
              '다음 예정: ${Formatters.yearMonthDay(candidate.nextExpectedAt)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('아니오'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('예'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final RecurringRule saved =
        await Injector.instance.recurring.save(candidate.toRule());
    // 과거 거래에도 정기결제 표시를 붙인다.
    await Injector.instance.recurring.backfillTransactions(saved);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${candidate.brand}" 를 ${candidate.cycle.label} '
            '정기결제로 등록했습니다.'),
      ),
    );
  }

  Future<void> _toggleActive(RecurringRule rule) async {
    final int? id = rule.id;
    if (id == null) return;
    await Injector.instance.recurring.setActive(id, !rule.isActive);
    await _load();
  }

  Future<void> _delete(RecurringRule rule) async {
    final int? id = rule.id;
    if (id == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('정기결제를 삭제할까요?'),
        content: const Text('기록된 거래는 그대로 남습니다.'),
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
    if (confirmed != true) return;

    await Injector.instance.recurring.delete(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('정기결제')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: <Widget>[
                  if (_candidates.isNotEmpty) ...<Widget>[
                    const _SectionTitle(
                      '감지된 후보',
                      subtitle: '반복 패턴이 보입니다',
                    ),
                    const SizedBox(height: 10),
                    ..._candidates.map(
                      (RecurringCandidate c) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CandidateCard(
                          candidate: c,
                          onRegister: () => _register(c),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  _SectionTitle(
                    '등록된 정기결제',
                    subtitle: '${_rules.where((RecurringRule r) => r.isActive).length}개 활성',
                  ),
                  const SizedBox(height: 10),
                  if (_rules.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: AppTheme.cardDecoration(context),
                      child: const Text(
                        '등록된 정기결제가 없습니다.\n'
                        '같은 브랜드가 일정한 주기로 3회 이상 결제되면 '
                        '후보로 제안됩니다.',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    )
                  else
                    Container(
                      decoration: AppTheme.cardDecoration(context),
                      child: Column(
                        children: List<Widget>.generate(_rules.length, (int i) {
                          final RecurringRule rule = _rules[i];
                          return Column(
                            children: <Widget>[
                              if (i > 0) const Divider(height: 1),
                              _RuleTile(
                                rule: rule,
                                onToggle: () => _toggleActive(rule),
                                onDelete: () => _delete(rule),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onRegister});

  final RecurringCandidate candidate;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  candidate.brand,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              Text(
                Formatters.won(candidate.expectedAmount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${candidate.cycle.label} · ${candidate.occurrenceCount}회 결제 · '
            '확신도 ${(candidate.confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 10),
          // 근거가 된 결제 내역. 왜 후보로 올랐는지 보여 준다.
          ...candidate.occurrences.take(3).map(
                (Transaction tx) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${Formatters.yearMonthDay(tx.paymentDatetime)}'
                    '  ${Formatters.won(tx.amount)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '다음 예정 '
                  '${Formatters.yearMonthDay(candidate.nextExpectedAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              FilledButton(
                onPressed: onRegister,
                child: const Text('등록'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onToggle,
    required this.onDelete,
  });

  final RecurringRule rule;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int? days = rule.daysUntilNext();
    final bool overdue = rule.isOverdue();

    return ListTile(
      leading: Icon(
        Icons.autorenew,
        color: rule.isActive ? scheme.primary : scheme.outline,
      ),
      title: Text(
        rule.brand,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: rule.isActive ? null : scheme.outline,
        ),
      ),
      subtitle: Text(
        <String>[
          rule.cycle.label,
          '${rule.category} · ${rule.subcategory}',
          if (rule.nextExpectedAt != null)
            overdue
                ? '예정일 지남'
                : (days == null
                    ? ''
                    : (days == 0 ? '오늘 예정' : '$days일 후')),
        ].where((String s) => s.isNotEmpty).join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            Formatters.won(rule.expectedAmount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: rule.isActive ? null : scheme.outline,
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'toggle') onToggle();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'toggle',
                child: Text(rule.isActive ? '일시 중지' : '다시 활성화'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('삭제'),
              ),
            ],
          ),
        ],
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
