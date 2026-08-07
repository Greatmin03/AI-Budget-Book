import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/classification_diagnostics.dart';

/// 분류 진단(개발자용).
///
/// 감이 아니라 숫자로 봐야 어디를 고칠지 알 수 있다. 자동 분류가 잘 되는데
/// 매핑표를 늘리는 것은 낭비고, 카카오가 계속 실패하는데 사전만 손보는 것도
/// 마찬가지다.
///
/// **디버그 빌드에서만 열린다.** 진입점(설정 화면)이 `kDebugMode` 로 막혀 있다.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  ClassificationDiagnostics _data = const ClassificationDiagnostics.empty();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ClassificationDiagnostics data =
          await Injector.instance.classificationDiagnostics.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('진단 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearUnmapped() async {
    await Injector.instance.classificationDiagnostics.clearUnmapped();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('분류 진단')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: <Widget>[
                  if (_data.isEmpty)
                    const _Empty()
                  else ...<Widget>[
                    _section('자동 분류'),
                    AppTheme.cardSurface(
                      context,
                      child: Column(
                        children: <Widget>[
                          _RateTile(
                            label: '자동 분류 성공률',
                            rate: _data.autoClassifiedRate,
                            detail: '전체 ${_data.totalTransactions}건',
                          ),
                          const Divider(height: 1),
                          _RateTile(
                            label: '브랜드 사전',
                            rate: _data.brandExtractorRate,
                            detail: '외부 호출 없이 해결',
                          ),
                          const Divider(height: 1),
                          _RateTile(
                            label: '장소 API 규칙',
                            rate: _data.placeRuleRate,
                            detail: '업종 조회로 해결',
                          ),
                          const Divider(height: 1),
                          _RateTile(
                            label: 'AI 대기열 진입률',
                            rate: _data.aiQueueRate,
                            // LLM 은 최후의 수단이다. 낮을수록 좋다.
                            detail: '낮을수록 좋다',
                          ),
                          const Divider(height: 1),
                          _RateTile(
                            label: '사용자 수정률',
                            rate: _data.userCorrectionRate,
                            detail: '높으면 앞단이 틀리고 있다',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _section('미분류 / 대기'),
                    AppTheme.cardSurface(
                      context,
                      child: Column(
                        children: <Widget>[
                          _CountTile(
                            label: '분류 필요',
                            count: _data.needsReview,
                          ),
                          const Divider(height: 1),
                          _CountTile(label: 'AI 대기', count: _data.aiPending),
                          const Divider(height: 1),
                          _CountTile(label: 'AI 완료', count: _data.aiCompleted),
                          const Divider(height: 1),
                          _CountTile(label: 'AI 실패', count: _data.aiFailed),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _section('장소 API'),
                    AppTheme.cardSurface(
                      context,
                      child: Column(
                        children: <Widget>[
                          _RateTile(
                            label: '조회 성공률',
                            rate: _data.placeLookupRate,
                            detail: '성공 ${_data.brandLookupsFound}건 / '
                                '실패 ${_data.brandLookupsNotFound}건',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _section('매핑하지 못한 업종'),
                    _buildUnmapped(context),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );

  Widget _buildUnmapped(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (_data.unmapped.isEmpty) {
      return Text(
        '아직 없습니다.\n'
        '장소 API 가 준 업종을 모두 우리 체계로 옮길 수 있었습니다.',
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '자주 막히는 것부터 매핑표에 넣습니다.\n'
          '추측으로 규칙을 늘리지 않기 위한 근거입니다.',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        AppTheme.cardSurface(
          context,
          child: Column(
            children: List<Widget>.generate(_data.unmapped.length, (int i) {
              final UnmappedPlaceCategory item = _data.unmapped[i];
              return Column(
                children: <Widget>[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(
                      item.categoryName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: item.sampleMerchant == null
                        ? null
                        : Text(
                            '예: ${item.sampleMerchant}',
                            style: const TextStyle(fontSize: 11),
                          ),
                    trailing: Text(
                      '${item.hitCount}회',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _clearUnmapped,
            child: const Text('기록 비우기'),
          ),
        ),
      ],
    );
  }
}

/// 비율 한 줄. 막대로도 보여 준다(숫자만 있으면 감이 안 온다).
class _RateTile extends StatelessWidget {
  const _RateTile({
    required this.label,
    required this.rate,
    required this.detail,
  });

  final String label;
  final double rate;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                Formatters.percent(rate),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate.clamp(0, 1),
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        '$count건',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(Icons.query_stats_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            '아직 거래가 없습니다.\n'
            '결제가 몇 건 쌓이면 분류가 어디서 막히는지 보입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
