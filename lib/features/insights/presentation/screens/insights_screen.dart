import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../domain/entities/insight_facts.dart';
import '../../domain/services/insight_narrator.dart';
import '../widgets/saving_simulator_sheet.dart';

/// 소비 분석 · 절약 제안 · 소비 습관.
///
/// 화면에 보이는 **모든 숫자는 앱이 계산한 값**이다.
/// LLM 을 켜더라도 문장 표현만 바뀌고 숫자는 그대로다.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  DateRange _range = DateRange.month();
  InsightFacts? _facts;
  bool _isLoading = true;
  String? _error;

  InsightNarrator get _narrator => Injector.instance.narrator;

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
      final InsightFacts facts =
          await Injector.instance.insights.facts(_range);
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('분석 계산 실패', e, stack);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  void _changeRange(DateRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _facts = null;
    });
    _load();
  }

  Future<void> _openSimulator(String target) async {
    final InsightFacts? facts = _facts;
    if (facts == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SavingSimulatorSheet(facts: facts, target: target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('분석')),
      body: Column(
        children: <Widget>[
          PeriodSelector(range: _range, onChanged: _changeRange),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final InsightFacts? facts = _facts;

    if (_isLoading && facts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('불러오지 못했습니다: $_error'));
    }
    if (facts == null || facts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '이 기간에는 분석할 거래가 없습니다.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final List<Insight> analysis = _narrator.analyze(facts);
    final List<Insight> suggestions = _narrator.suggestions(facts);
    final List<Insight> habits = _narrator.habits(facts);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _Section(
            title: '소비 분석',
            subtitle: '${facts.range.previousLabel} 대비',
            child: analysis.isEmpty
                ? const _EmptyNote('비교할 이전 기간 데이터가 없습니다.')
                : Column(
                    children: analysis
                        .map((Insight i) => _InsightRow(insight: i))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),

          _Section(
            title: '절약 제안',
            subtitle: '자주 쓰는 항목 기준',
            child: suggestions.isEmpty
                ? const _EmptyNote(
                    '아직 제안할 항목이 없습니다.\n'
                    '같은 곳을 여러 번 이용하면 절약 여지를 찾아 드립니다.',
                  )
                : Column(
                    children: suggestions
                        .map(
                          (Insight i) => _InsightRow(
                            insight: i,
                            onTap: i.target == null
                                ? null
                                : () => _openSimulator(i.target!),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),

          _Section(
            title: '소비 습관',
            subtitle: '최근 8주',
            child: habits.isEmpty
                ? const _EmptyNote('반복되는 패턴이 아직 보이지 않습니다.')
                : Column(
                    children:
                        habits.map((Insight i) => _InsightRow(insight: i)).toList(),
                  ),
          ),
          const SizedBox(height: 24),

          // "만약 ~ 하면?" 진입점
          _Section(
            title: '만약 줄이면?',
            subtitle: '항목을 눌러 시뮬레이션',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: facts
                  .reducibleItems(limit: 8)
                  .map(
                    (ItemFact f) => ActionChip(
                      label: Text('${f.name} (${f.count}회)'),
                      onPressed: () => _openSimulator(f.name),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight, this.onTap});

  final Insight insight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // 색만으로 구분하지 않는다. 아이콘 + 라벨을 함께 쓴다.
    final IconData icon;
    switch (insight.kind) {
      case InsightKind.increase:
        icon = Icons.trending_up;
      case InsightKind.decrease:
        icon = Icons.trending_down;
      case InsightKind.suggestion:
        icon = Icons.lightbulb_outline;
      case InsightKind.habit:
        icon = Icons.repeat;
      case InsightKind.summary:
        icon = Icons.summarize_outlined;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 17, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    insight.headline,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (insight.detail != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      insight.detail!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
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
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(context),
          child: child,
        ),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
