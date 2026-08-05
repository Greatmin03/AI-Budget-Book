import 'package:flutter/material.dart';

import '../../core/di/injector.dart';

/// 알림 접근 권한이 없을 때 상단에 뜨는 안내 배너.
///
/// 이 권한이 없으면 앱의 존재 이유가 사라지므로 강하게 노출한다.
class PermissionBanner extends StatelessWidget {
  const PermissionBanner({required this.onGranted, super.key});

  /// 설정 화면에서 돌아온 뒤 권한을 다시 확인하기 위한 콜백.
  final Future<void> Function() onGranted;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: <Widget>[
          Icon(Icons.notifications_off_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '알림 접근 권한이 필요합니다',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '결제 알림을 읽어야 가계부가 자동으로 작성됩니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await Injector.instance.notifications.openPermissionSettings();
              // 시스템 설정에서 돌아오면 lifecycle 로도 갱신되지만,
              // 즉시 반영을 위해 한 번 더 확인한다.
              await onGranted();
            },
            child: const Text('허용'),
          ),
        ],
      ),
    );
  }
}
