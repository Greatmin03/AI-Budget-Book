import 'dart:convert';

import '../../../../core/constants/app_categories.dart';
import '../../../../core/constants/classification_source.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/merchant_classification.dart';

/// LLM 원본 응답 -> 검증된 [MerchantClassification].
///
/// LLM 출력은 절대 신뢰하지 않는다. 다음을 모두 통과해야 저장된다.
///  1. `<think>` 블록 제거 (Qwen3 는 추론 모델이라 사고 과정을 뱉을 수 있다)
///  2. 앞뒤 잡담/코드펜스를 무시하고 첫 JSON 객체만 추출
///  3. 필수 필드 존재 및 타입 확인
///  4. 카테고리/서브카테고리가 허용 목록에 있는지 검증 → 아니면 보정
class ClassificationDto {
  const ClassificationDto._();

  /// 파싱 실패 시 [LlmContractFailure] 를 던진다.
  static MerchantClassification parse({
    required String rawResponse,
    required String merchantNameFallback,
  }) {
    final String cleaned = _stripThinking(rawResponse);
    final String? jsonText = _extractFirstJsonObject(cleaned);
    if (jsonText == null) {
      throw LlmContractFailure(
        'JSON 객체를 찾을 수 없습니다.',
        rawResponse: rawResponse,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw LlmContractFailure('JSON 파싱 실패: ${e.message}', rawResponse: rawResponse);
    }

    if (decoded is! Map<String, Object?>) {
      throw LlmContractFailure('JSON 최상위가 객체가 아닙니다.', rawResponse: rawResponse);
    }

    final String brand = _nonEmptyString(decoded['brand']) ?? merchantNameFallback;
    final String? branch = _nonEmptyString(decoded['branch']);

    // 허용 목록 대조 및 보정. 여기서 잘못된 값이 걸러진다.
    final CategoryPair pair = CategoryTaxonomy.coerce(
      _nonEmptyString(decoded['category']),
      _nonEmptyString(decoded['subcategory']),
    );

    return MerchantClassification(
      brand: brand,
      branch: branch,
      category: pair.category,
      subcategory: pair.subcategory,
      source: ClassificationSource.llm,
      confidence: _confidence(decoded['confidence']),
    );
  }

  /// Qwen3 등 추론 모델의 `<think> ... </think>` 블록 제거.
  static String _stripThinking(String raw) {
    return raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        // 닫는 태그가 없는 채로 잘린 경우도 방어한다.
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'```(?:json)?'), '')
        .trim();
  }

  /// 첫 번째 균형 잡힌 `{...}` 블록을 추출한다.
  ///
  /// 문자열 리터럴 안의 중괄호와 이스케이프를 고려한다.
  static String? _extractFirstJsonObject(String text) {
    final int start = text.indexOf('{');
    if (start < 0) return null;

    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = start; i < text.length; i++) {
      final String char = text[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    // 모델이 문자열 "null" 을 넣는 경우가 흔하다.
    if (trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }

  /// 범위를 벗어나거나 형식이 틀리면 보수적인 기본값(0.7).
  static double _confidence(Object? value) {
    double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(value.trim());
    }
    if (parsed == null) return 0.7;
    if (parsed.isNaN) return 0.7;
    // clamp 의 정적 반환형은 num 이므로 double 로 변환해 반환한다.
    return parsed.clamp(0.0, 1.0).toDouble();
  }
}
