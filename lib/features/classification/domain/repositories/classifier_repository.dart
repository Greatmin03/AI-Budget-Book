import '../entities/llm_health.dart';
import '../entities/merchant_classification.dart';

/// LLM 분류 경계.
abstract interface class ClassifierRepository {
  /// LLM 으로 분류한다.
  ///
  /// 실패 시 `LlmFailure` / `LlmContractFailure` 를 던진다.
  /// 폴백 처리는 호출자(`ClassifyMerchant` 유즈케이스)의 책임이다.
  Future<MerchantClassification> classifyWithLlm(String merchantRaw);

  /// 설정 화면의 연결 테스트.
  Future<LlmHealth> checkHealth();

  /// 설정상 LLM 을 쓸 수 있는 상태인지(스위치가 켜져 있는지).
  bool get isEnabled;
}
