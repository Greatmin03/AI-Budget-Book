import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/usecases/process_ai_pending_queue.dart';
import '../controllers/ai_queue_controller.dart';

/// `AI 분석 대기 23건 [지금 분석]` 배너.
///
/// Ollama 에 닿을 때만 나타난다. 노트북이 꺼져 있으면 사용자가 할 수 있는 일이
/// 없으므로 배너를 띄우지 않는다(대기 건수는 설정 화면에서 볼 수 있다).
class AiQueueBanner extends StatelessWidget {
  const AiQueueBanner({required this.controller, super.key});

  final AiQueueController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        // 분석 중에는 건수가 0이 되어도 진행 표시를 유지한다.
        if (!controller.shouldShowBanner && !controller.isProcessing) {
          return const SizedBox.shrink();
        }
        return _Banner(controller: controller);
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller});

  final AiQueueController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool processing = controller.isProcessing;

    // 아래 여백을 배너가 직접 가진다. 숨겨질 때 빈 공간이 남지 않게 하려면
    // 호출하는 쪽에서 SizedBox 를 조건부로 넣는 것보다 이쪽이 안전하다.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: AppTheme.cardDecoration(context),
      child: Row(
        children: <Widget>[
          Icon(
            processing ? Icons.auto_awesome : Icons.auto_awesome_outlined,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  processing
                      ? 'AI 분석 중'
                      : 'AI 분석 대기 ${controller.pendingCount}건',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  processing
                      ? '같은 브랜드는 한 번만 물어봅니다. 그동안 앱은 그대로 쓸 수 있습니다.'
                      : 'Ollama 연결됨 · 미분류 거래를 브랜드별로 한 번씩 분석합니다.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (processing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton(
              onPressed: () => _run(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('지금 분석'),
            ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AiBatchResult? result = await controller.processNow();
    if (result == null) return;

    // context 를 await 뒤에 다시 쓰지 않는다(미리 잡아 둔 messenger 를 쓴다).
    messenger.showSnackBar(
      SnackBar(content: Text(_message(result))),
    );
  }

  static String _message(AiBatchResult result) {
    if (!result.didRun) return result.skippedReason!;
    if (!result.changedAnything && result.failures == 0) {
      return '새로 분류할 거래가 없었습니다.';
    }

    final StringBuffer text = StringBuffer(
      '거래 ${result.transactionsUpdated}건을 분류했습니다 '
      '(AI 호출 ${result.llmCalls}회',
    );
    if (result.cacheHits > 0) {
      text.write(', 캐시 ${result.cacheHits}건');
    }
    text.write(')');
    if (result.failures > 0) {
      text.write(' · ${result.failures}개 브랜드는 실패해 나중에 다시 시도합니다');
    }
    return text.toString();
  }
}
