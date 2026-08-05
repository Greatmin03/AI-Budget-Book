/// 카테고리 분류가 어디서 나왔는지.
///
/// 우선순위가 중요하다. 사용자가 직접 고친 분류는 어떤 자동 분류보다 강하며,
/// LLM 결과가 사용자 수정을 덮어쓰면 안 된다.
enum ClassificationSource {
  /// 아직 분류되지 않음. 사용자 확인을 기다리는 상태.
  ///
  /// 처음 보는 브랜드는 이 상태로 저장되고, 사용자가 카테고리를 한 번 고르면
  /// [user] 로 승격된다. 우선순위가 가장 낮아 어떤 분류든 덮어쓸 수 있다.
  pending('pending', '분류 필요', 0),

  /// 앱 내장 브랜드 사전.
  seed('seed', '내장 사전', 1),

  /// 키워드 규칙 기반 폴백.
  rule('rule', '규칙 분류', 2),

  /// Ollama(LLM) 분류.
  llm('llm', 'AI 분류', 3),

  /// 사용자가 직접 지정 — 가장 강함.
  user('user', '직접 수정', 4);

  const ClassificationSource(this.code, this.label, this.priority);

  final String code;
  final String label;
  final int priority;

  bool get isUserDefined => this == ClassificationSource.user;

  bool get isPending => this == ClassificationSource.pending;

  /// 이 출처가 [other] 를 덮어써도 되는지.
  bool canOverride(ClassificationSource other) => priority >= other.priority;

  static ClassificationSource fromCode(String? code) {
    for (final ClassificationSource source in ClassificationSource.values) {
      if (source.code == code) return source;
    }
    return ClassificationSource.rule;
  }
}
