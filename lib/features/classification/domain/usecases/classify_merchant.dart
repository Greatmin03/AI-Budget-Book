import '../../../../core/error/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../entities/merchant_classification.dart';
import '../repositories/classifier_repository.dart';
import '../services/rule_based_classifier.dart';

/// 처음 보는 가맹점을 분류한다.
///
/// 이 유즈케이스는 **절대 예외를 던지지 않는다.**
/// LLM 이 꺼져 있거나 서버가 죽어 있거나 이상한 응답을 주더라도
/// 규칙 기반 분류로 폴백해 반드시 결과를 돌려준다.
/// (가계부 기록이 LLM 상태 때문에 유실되면 안 된다)
class ClassifyMerchant {
  const ClassifyMerchant({
    required ClassifierRepository classifier,
    RuleBasedClassifier ruleBased = const RuleBasedClassifier(),
  })  : _classifier = classifier,
        _ruleBased = ruleBased;

  final ClassifierRepository _classifier;
  final RuleBasedClassifier _ruleBased;

  Future<MerchantClassification> call(String merchantRaw) async {
    if (merchantRaw.trim().isEmpty) {
      return _ruleBased.classify(merchantRaw);
    }

    if (!_classifier.isEnabled) {
      AppLogger.d('LLM 비활성 → 규칙 기반 분류 사용: $merchantRaw');
      return _ruleBased.classify(merchantRaw);
    }

    try {
      return await _classifier.classifyWithLlm(merchantRaw);
    } on Failure catch (e) {
      AppLogger.w('LLM 분류 실패 → 규칙 기반 폴백 ($merchantRaw): ${e.message}');
      return _ruleBased.classify(merchantRaw);
    } on Object catch (e, stack) {
      // 예상하지 못한 예외까지 삼켜서 파이프라인을 지킨다.
      AppLogger.e('LLM 분류 중 예외 → 규칙 기반 폴백 ($merchantRaw)', e, stack);
      return _ruleBased.classify(merchantRaw);
    }
  }
}
