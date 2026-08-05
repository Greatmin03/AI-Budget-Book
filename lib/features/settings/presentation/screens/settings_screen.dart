import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../classification/data/datasources/place_api_datasource.dart';
import '../../../classification/domain/entities/llm_health.dart';
import '../../../classification/domain/usecases/process_ai_pending_queue.dart';
import '../../../classification/presentation/controllers/ai_queue_controller.dart';
import '../../../ingest/domain/services/notification_ingest_service.dart';
import '../controllers/settings_controller.dart';
import '../../../notifications/domain/entities/notification_source.dart';
import '../widgets/ingest_failures_sheet.dart';
import '../widgets/notification_sources_sheet.dart';
import '../widgets/text_setting_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _controller;

  NotificationIngestService get _ingest => Injector.instance.ingestService;

  @override
  void initState() {
    super.initState();
    final Injector di = Injector.instance;
    _controller = SettingsController(
      settings: di.settings,
      classifier: di.classifier,
      merchants: di.merchants,
      transactions: di.transactions,
      failures: di.ingestFailures,
      notifications: di.notifications,
      sources: di.notificationSources,
      brandMetadata: di.brandMetadata,
      lookupIndustry: di.lookupBrandIndustry,
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
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            const _SectionHeader('알림 수집'),
            _StatusTile(
              icon: Icons.notifications_active_outlined,
              title: '알림 접근 권한',
              value: _controller.permissionGranted ? '허용됨' : '허용되지 않음',
              isGood: _controller.permissionGranted,
              onTap: () async {
                await _controller.openPermissionSettings();
                await _controller.load();
              },
            ),
            _StatusTile(
              icon: Icons.cable_outlined,
              title: '리스너 서비스',
              value: _controller.serviceConnected ? '연결됨' : '연결 안 됨',
              isGood: _controller.serviceConnected,
              onTap: _controller.load,
            ),
            ListTile(
              leading: const Icon(Icons.apps_outlined),
              title: const Text('알림 수집 앱'),
              subtitle: Text(_sourcesSubtitle()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) =>
                    NotificationSourcesSheet(controller: _controller),
              ),
            ),
            ValueListenableBuilder<IngestStatus>(
              valueListenable: _ingest.status,
              builder: (BuildContext context, IngestStatus status, _) {
                return ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('처리 현황'),
                  subtitle: Text(
                    '저장 ${status.savedCount} · 중복 ${status.duplicateCount} · '
                    '무시 ${status.ignoredCount} · 실패 ${status.failedCount}\n'
                    'AI 호출 ${status.llmCallCount}회'
                    '${status.queued > 0 ? ' · 대기 ${status.queued}건' : ''}'
                    '${status.lastMessage == null ? '' : '\n최근: ${status.lastMessage}'}',
                  ),
                  isThreeLine: true,
                  trailing: status.isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_gmailerrorred_outlined),
              title: const Text('파싱 실패 보관함'),
              subtitle: const Text('결제 알림처럼 보였지만 해석하지 못한 알림'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => IngestFailuresSheet(controller: _controller),
              ),
            ),

            const Divider(),
            const _SectionHeader('브랜드 자동 분류 (선택)'),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '처음 보는 브랜드의 업종을 카카오 지도에서 한 번만 찾아 자동 분류합니다.\n'
                '카카오 로컬 API 는 무료이고 카드 등록이 필요 없습니다. '
                '본인 키를 넣기 때문에 요금이 청구될 구조가 아닙니다.\n'
                '키가 없어도 앱은 그대로 동작합니다(처음 보는 브랜드만 직접 한 번 선택).',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.travel_explore_outlined),
              title: const Text('업종 조회 사용'),
              subtitle: Text(
                _controller.settings.placeApiKey.trim().isEmpty
                    ? '키를 입력하면 동작합니다.'
                    : '브랜드당 최대 1회만 조회하고 결과를 저장합니다.',
              ),
              value: _controller.settings.placeApiEnabled,
              onChanged: _controller.setPlaceApiEnabled,
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('카카오 REST API 키'),
              subtitle: Text(_maskedKey(_controller.settings.placeApiKey)),
              onTap: () async {
                final String? value = await showTextSettingDialog(
                  context: context,
                  title: '카카오 REST API 키',
                  initialValue: _controller.settings.placeApiKey,
                  helperText: 'developers.kakao.com > 내 애플리케이션 > '
                      '앱 키 > REST API 키\n'
                      '카카오 로컬 API 는 무료입니다(카드 등록 불필요).',
                );
                if (value != null) await _controller.setPlaceApiKey(value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('키 확인'),
              subtitle: _buildPlaceApiSubtitle(context),
              trailing: _controller.isTestingPlaceApi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              onTap: _controller.isTestingPlaceApi
                  ? null
                  : _controller.testPlaceApi,
            ),
            if (_controller.settings.isPlaceApiThrottled)
              ListTile(
                leading: Icon(
                  Icons.pause_circle_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('호출 한도 초과로 쉬는 중'),
                subtitle: Text(
                  '${_formatUntil(_controller.settings.placeApiBlockedUntil)}'
                  ' 까지 조회를 멈춥니다. 그동안에도 기록은 정상 동작합니다.',
                ),
                trailing: TextButton(
                  onPressed: _controller.clearPlaceApiThrottle,
                  child: const Text('지금 재시도'),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.cached_outlined),
              title: const Text('업종 조회 기록'),
              subtitle: const Text('탭하면 비웁니다(직접 지정한 분류는 남습니다).'),
              trailing: Text('${_controller.brandMetadataCount}개'),
              onTap: _clearLookupCache,
            ),

            const Divider(),
            const _SectionHeader('AI 분류 (선택)'),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'AI 는 필수가 아닙니다. 꺼져 있어도 모든 결제는 정상 기록되며, '
                '처음 보는 브랜드만 한 번 직접 분류하면 됩니다.\n'
                '켜면 그 한 번의 선택까지 AI 가 대신합니다.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 자동 분류 사용'),
              subtitle: Text(
                _controller.settings.llmEnabled
                    ? '처음 보는 브랜드를 Ollama 가 분류합니다.'
                    : '처음 보는 브랜드는 "분류 필요" 목록에 쌓입니다.',
              ),
              value: _controller.settings.llmEnabled,
              onChanged: _controller.setLlmEnabled,
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Ollama 주소'),
              subtitle: Text(_controller.settings.ollamaBaseUrl),
              onTap: () async {
                final String? value = await showTextSettingDialog(
                  context: context,
                  title: 'Ollama 주소',
                  initialValue: _controller.settings.ollamaBaseUrl,
                  helperText: '에뮬레이터: http://10.0.2.2:11434\n'
                      '실제 기기: http://<PC의 LAN IP>:11434',
                );
                if (value != null) await _controller.setOllamaBaseUrl(value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: const Text('모델'),
              subtitle: Text(_controller.settings.ollamaModel),
              onTap: () async {
                final String? value = await showTextSettingDialog(
                  context: context,
                  title: '모델 이름',
                  initialValue: _controller.settings.ollamaModel,
                  helperText: '예: gemma3:4b, qwen3:4b, llama3.2:3b',
                );
                if (value != null) await _controller.setOllamaModel(value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('응답 제한 시간'),
              subtitle: Text('${_controller.settings.requestTimeoutSeconds}초'),
              onTap: () async {
                final String? value = await showTextSettingDialog(
                  context: context,
                  title: '응답 제한 시간(초)',
                  initialValue:
                      _controller.settings.requestTimeoutSeconds.toString(),
                  keyboardType: TextInputType.number,
                );
                final int? seconds = value == null ? null : int.tryParse(value);
                if (seconds != null && seconds > 0) {
                  await _controller.setTimeout(seconds);
                }
              },
            ),
            // 대기열은 AI 를 껐을 때도 보여 준다. "왜 미분류가 쌓이는지" 를
            // 설명하는 화면이기 때문이다.
            ListenableBuilder(
              listenable: Injector.instance.aiQueue,
              builder: (BuildContext context, Widget? child) {
                final AiQueueController queue = Injector.instance.aiQueue;
                return ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 분석 대기'),
                  subtitle: Text(
                    queue.pendingCount == 0
                        ? '대기 중인 거래가 없습니다.'
                        : '미분류 거래 ${queue.pendingCount}건. '
                            'Ollama 가 연결되면 브랜드별로 한 번씩 분석합니다.',
                  ),
                  trailing: queue.isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : queue.pendingCount == 0
                          ? null
                          : TextButton(
                              onPressed: () => _runAiQueue(queue),
                              child: const Text('지금 분석'),
                            ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.network_check_outlined),
              title: const Text('연결 테스트'),
              subtitle: _buildHealthSubtitle(context),
              trailing: _controller.isTestingConnection
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              onTap: _controller.isTestingConnection
                  ? null
                  : _controller.testConnection,
            ),

            const Divider(),
            const _SectionHeader('학습'),
            SwitchListTile(
              secondary: const Icon(Icons.school_outlined),
              title: const Text('브랜드 규칙 자동 학습'),
              subtitle: const Text(
                'AI 분류 결과를 브랜드 규칙으로 저장해, 같은 브랜드의 다른 지점도 '
                'AI 없이 바로 분류합니다.',
              ),
              value: _controller.settings.autoLearnBrandRule,
              onChanged: _controller.setAutoLearnBrandRule,
            ),
            ListTile(
              leading: const Icon(Icons.percent_outlined),
              title: const Text('학습 최소 확신도'),
              subtitle: Text(
                '${(_controller.settings.minConfidenceToLearn * 100).toStringAsFixed(0)}% '
                '미만이면 학습하지 않습니다.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Slider(
                value: _controller.settings.minConfidenceToLearn,
                min: 0,
                max: 1,
                divisions: 10,
                label:
                    '${(_controller.settings.minConfidenceToLearn * 100).toStringAsFixed(0)}%',
                onChanged: _controller.setMinConfidence,
              ),
            ),

            const Divider(),
            const _SectionHeader('데이터'),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('학습된 가맹점'),
              trailing: Text('${_controller.learnedMerchants}개'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('기록된 거래'),
              trailing: Text('${_controller.transactionCount}건'),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('동작 로그'),
              subtitle: const Text('최근 처리 내역(앱 내부에만 저장됩니다)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const _LogSheet(),
              ),
            ),

            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                '모든 데이터는 이 기기 안에만 저장됩니다.\n'
                'AI 분류는 사용자가 지정한 로컬 Ollama 서버로만 요청하며, '
                '외부 클라우드로 전송되지 않습니다.\n'
                '업종 조회는 브랜드 이름만 카카오에 보냅니다. '
                '금액·카드·날짜는 전송되지 않습니다.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        );
      },
    );
  }

  String _sourcesSubtitle() {
    final NotificationSourceConfig config = _controller.sourceConfig;
    if (config.isEmpty) return '아직 감지된 앱이 없습니다.';
    if (!config.isFiltering) {
      return '감지된 ${config.sources.length}개 앱 전체를 수집하고 있습니다.';
    }
    return '${config.sources.length}개 중 ${config.enabledCount}개만 수집합니다.';
  }

  /// 대기열을 지금 처리한다. 결과를 스낵바로 알려 준다.
  Future<void> _runAiQueue(AiQueueController queue) async {
    final AiBatchResult? result = await queue.processNow();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.didRun
              ? '거래 ${result.transactionsUpdated}건 분류 · '
                  'AI 호출 ${result.llmCalls}회'
              : result.skippedReason!,
        ),
      ),
    );
  }

  Future<void> _clearLookupCache() async {
    final int removed = await _controller.clearBrandLookupCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('업종 조회 기록 $removed건을 비웠습니다.')),
    );
  }

  Widget _buildPlaceApiSubtitle(BuildContext context) {
    final PlaceLookupResult? result = _controller.placeApiResult;
    if (result == null) {
      return const Text('탭하면 키가 유효한지 1회 조회해 확인합니다.');
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String message = switch (result.status) {
      PlaceLookupStatus.success =>
        '정상 동작합니다. (${result.placeName} · ${result.categoryName})',
      PlaceLookupStatus.notFound => '응답은 정상이지만 결과가 없었습니다.',
      PlaceLookupStatus.quotaExceeded => '호출 한도를 초과했습니다.',
      PlaceLookupStatus.failed => result.message ?? '실패했습니다.',
    };
    return Text(
      message,
      style: TextStyle(
        color: result.isSuccess ? scheme.primary : scheme.error,
      ),
    );
  }

  /// 키 전체를 화면에 남기지 않는다.
  static String _maskedKey(String key) {
    final String trimmed = key.trim();
    if (trimmed.isEmpty) return '입력되지 않음';
    if (trimmed.length <= 8) return '*' * trimmed.length;
    return '${trimmed.substring(0, 4)}${'*' * 8}'
        '${trimmed.substring(trimmed.length - 4)}';
  }

  static String _formatUntil(DateTime? until) {
    if (until == null) return '-';
    return '${until.month}/${until.day} '
        '${until.hour.toString().padLeft(2, '0')}:'
        '${until.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildHealthSubtitle(BuildContext context) {
    final LlmHealth? health = _controller.health;
    if (health == null) {
      return const Text('탭하여 Ollama 연결을 확인합니다.');
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Text(
      health.message,
      style: TextStyle(
        color: health.isUsable ? scheme.primary : scheme.error,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.isGood,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool isGood;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Row(
        children: <Widget>[
          // 색만으로 상태를 표현하지 않는다(아이콘 + 텍스트 동반).
          Icon(
            isGood ? Icons.check_circle : Icons.error_outline,
            size: 14,
            color: isGood ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 4),
          Text(value),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 최근 동작 로그.
class _LogSheet extends StatelessWidget {
  const _LogSheet();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppLogger.revision,
      builder: (BuildContext context, int revision, _) {
        final List<LogEntry> entries = AppLogger.entries;
        return Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '동작 로그',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: AppLogger.clear,
                    child: Text('지우기'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('기록이 없습니다.'))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final LogEntry entry = entries[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            entry.message,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${entry.level.name.toUpperCase()}  '
                            '${entry.time.hour.toString().padLeft(2, '0')}:'
                            '${entry.time.minute.toString().padLeft(2, '0')}:'
                            '${entry.time.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
