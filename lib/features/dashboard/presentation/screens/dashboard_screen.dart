import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../../statistics/domain/entities/analytics.dart';
import '../../../classification/presentation/widgets/ai_queue_banner.dart';
import '../widgets/flow_summary_card.dart';
import '../widgets/top_row.dart';
import '../../../recurring/domain/entities/recurring_rule.dart';
import '../../../recurring/presentation/screens/recurring_screen.dart';
import '../../../settlements/presentation/screens/deposit_link_screen.dart';
import '../../../statistics/presentation/widgets/highlight_cards.dart';
import '../../../transactions/presentation/screens/review_queue_screen.dart';
import '../controllers/dashboard_controller.dart';

/// 소비 현황을 한눈에 보여 주는 대시보드(앱 첫 화면).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(
      analytics: Injector.instance.analytics,
      transactions: Injector.instance.transactions,
      deposits: Injector.instance.deposits,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final DashboardSummary summary = _controller.summary;

        return Column(
          children: <Widget>[
            PeriodSelector(
              range: _controller.range,
              onChanged: _controller.changeRange,
            ),
            Expanded(
              child: _controller.isLoading && !_controller.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _controller.load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: <Widget>[
                          // 사용자 조치가 필요한 항목을 가장 위에 노출한다.
                          // AI 대기열 배너. Ollama 에 닿을 때만 나타난다.
                          AiQueueBanner(
                            controller: Injector.instance.aiQueue,
                          ),
                          if (summary.needsReviewCount > 0) ...<Widget>[
                            _ReviewPrompt(count: summary.needsReviewCount),
                            const SizedBox(height: 16),
                          ],
                          if (summary.pendingDepositCount > 0) ...<Widget>[
                            _DepositPrompt(
                              count: summary.pendingDepositCount,
                              onDone: _controller.load,
                            ),
                            const SizedBox(height: 16),
                          ],
                          // 수입이 있으면 수입/지출/순증가를 먼저 보여 준다.
                          // 지출만 있는 달에는 기존 소비 카드가 더 정확하다.
                          if (summary.hasIncome) ...<Widget>[
                            FlowSummaryCard(summary: summary),
                            const SizedBox(height: 12),
                          ],
                          _TotalCard(summary: summary),
                          if (summary.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(
                                child: Text('이 기간에는 기록된 결제가 없습니다.'),
                              ),
                            )
                          else ...<Widget>[
                            const SizedBox(height: 16),
                            TopRow(summary: summary),
                            const SizedBox(height: 16),
                            HighlightCards(highlights: summary.highlights),
                            if (summary.upcomingRecurring.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 20),
                              _UpcomingRecurring(
                                rules: summary.upcomingRecurring,
                                onDone: _controller.load,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// "분류가 필요한 거래 N건" 안내.
class _ReviewPrompt extends StatelessWidget {
  const _ReviewPrompt({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ReviewQueueScreen(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.help_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '분류가 필요한 거래 $count건',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '처음 보는 브랜드입니다. 한 번만 골라 주면 다음부터 자동 분류됩니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// "연결할 입금 N건" 안내.
///
/// 받은 돈을 어떤 결제의 정산인지 연결하면 그 거래의 실제 부담이 줄어든다.
class _DepositPrompt extends StatelessWidget {
  const _DepositPrompt({required this.count, required this.onDone});

  final int count;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DepositLinkScreen(),
            ),
          );
          await onDone();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.call_received, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '연결할 입금 $count건',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '받은 돈을 결제와 연결하면 실제 부담 금액이 정확해집니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 총 소비 + 평균 하루 소비.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? rate = summary.changeRate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary.hasSettlements
                ? '${summary.range.label} 실제 부담'
                : '${summary.range.label} 총 소비',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.signedWon(summary.total),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          ),
          // 정산이 있으면 원본 결제 합계도 함께 보여 준다.
          if (summary.hasSettlements) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '총 결제 ${Formatters.signedWon(summary.grossTotal)} · '
              '정산 ${Formatters.won(summary.settledTotal)} 받음',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          // 자산 이동이 있으면 소비와 현금 흐름을 구분해서 보여 준다.
          if (summary.hasAssetTransfers) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '자산 이동 ${Formatters.won(summary.assetTransferTotal)} 제외 · '
              '통장 유출 ${Formatters.signedWon(summary.cashOutflow)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: <Widget>[
              _Meta(
                icon: Icons.receipt_long_outlined,
                label: '${summary.transactionCount}건',
              ),
              _Meta(
                icon: Icons.today_outlined,
                label: '평균 하루 ${Formatters.won(summary.dailyAverage)}',
              ),
              if (rate != null)
                _Meta(
                  icon: rate >= 0 ? Icons.trending_up : Icons.trending_down,
                  label: '${summary.range.previousLabel}보다 '
                      '${Formatters.changeLabel(rate)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 예정된 정기결제.
class _UpcomingRecurring extends StatelessWidget {
  const _UpcomingRecurring({required this.rules, required this.onDone});

  final List<RecurringRule> rules;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '예정된 정기결제',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecurringScreen(),
                  ),
                );
                await onDone();
              },
              child: const Text('관리'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: AppTheme.cardDecoration(context),
          child: Column(
            children: List<Widget>.generate(rules.length, (int index) {
              final RecurringRule rule = rules[index];
              final int? days = rule.daysUntilNext();
              final bool overdue = rule.isOverdue();

              return Column(
                children: <Widget>[
                  if (index > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.autorenew,
                      size: 18,
                      color: overdue ? scheme.error : scheme.primary,
                    ),
                    title: Text(
                      rule.brand,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      rule.nextExpectedAt == null
                          ? rule.cycle.label
                          : '${Formatters.monthDay(rule.nextExpectedAt!)}'
                              '${overdue ? ' · 예정일 지남' : (days == 0 ? ' · 오늘' : ' · $days일 후')}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      Formatters.won(rule.expectedAmount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

