/// LLM(Ollama) 연결 상태.
///
/// 설정 화면의 "연결 테스트" 결과를 표현한다.
class LlmHealth {
  const LlmHealth({
    required this.reachable,
    required this.message,
    this.modelInstalled = false,
    this.installedModels = const <String>[],
  });

  const LlmHealth.disabled()
      : reachable = false,
        modelInstalled = false,
        installedModels = const <String>[],
        message = 'AI 분류가 꺼져 있습니다.';

  /// 서버에 HTTP 로 닿는지.
  final bool reachable;

  /// 설정된 모델이 실제로 설치되어 있는지.
  final bool modelInstalled;

  final List<String> installedModels;
  final String message;

  bool get isUsable => reachable && modelInstalled;
}
