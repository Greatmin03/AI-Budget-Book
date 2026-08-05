import 'package:flutter/material.dart';

import '../../../notifications/domain/entities/notification_source.dart';
import '../controllers/settings_controller.dart';

/// 어떤 앱의 알림을 수집할지 고르는 화면.
///
/// 목록은 "미리 정해둔 금융 앱 목록" 이 아니다. 실제로 결제 알림처럼 보이는
/// 알림을 보낸 앱만 쌓인다. 그래서 처음에는 비어 있을 수 있다.
class NotificationSourcesSheet extends StatelessWidget {
  const NotificationSourcesSheet({required this.controller, super.key});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final NotificationSourceConfig config = controller.sourceConfig;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '알림 수집 앱',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '다시 확인',
                    icon: const Icon(Icons.refresh),
                    onPressed: controller.refreshSources,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                config.isFiltering
                    ? '선택한 ${config.enabledCount}개 앱의 알림만 수집합니다. '
                        '나머지는 저장되지 않고 즉시 무시됩니다.'
                    : '아직 선택한 앱이 없어 결제 알림을 보내는 모든 앱을 수집합니다.\n'
                        '하나라도 선택하면 그 앱들만 수집합니다.',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: config.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: config.sources.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final NotificationSource source =
                            config.sources[index];
                        return SwitchListTile(
                          title: Text(source.displayName),
                          subtitle: Text(
                            source.hasReadableName
                                ? '${source.packageName}\n'
                                    '${_lastSeen(source)}'
                                : _lastSeen(source),
                          ),
                          isThreeLine: source.hasReadableName,
                          value: source.enabled,
                          onChanged: (bool value) => controller.toggleSource(
                            packageName: source.packageName,
                            enabled: value,
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

  static String _lastSeen(NotificationSource source) {
    final DateTime? at = source.lastSeenAt;
    if (at == null) return '수집 기록 없음';
    return '마지막 알림 '
        '${at.month}/${at.day} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '아직 감지된 앱이 없습니다.\n\n'
          '카드/은행 앱에서 결제 알림이 한 번 오면 여기에 나타납니다. '
          '그때 수집할 앱만 켜 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
      ),
    );
  }
}
