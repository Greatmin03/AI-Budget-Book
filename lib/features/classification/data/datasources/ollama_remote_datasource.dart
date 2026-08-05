import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/constants/app_categories.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/llm_health.dart';

/// 로컬에서 실행 중인 Ollama 서버와 통신한다.
///
/// 주의: 이 호출은 사용자의 PC(로컬 네트워크)로만 나간다.
/// 외부 클라우드로 개인정보를 보내지 않는다는 설계 원칙을 지킨다.
class OllamaRemoteDataSource {
  OllamaRemoteDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 서버가 살아 있는지 + 지정한 모델이 설치되어 있는지 확인한다.
  Future<LlmHealth> checkHealth({
    required String baseUrl,
    required String model,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Uri uri = _resolve(baseUrl, '/api/tags');
    try {
      final http.Response response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return LlmHealth(
          reachable: false,
          message: 'HTTP ${response.statusCode}',
        );
      }

      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final List<String> models = <String>[];
      if (decoded is Map<String, Object?>) {
        final Object? list = decoded['models'];
        if (list is List<Object?>) {
          for (final Object? item in list) {
            if (item is Map<String, Object?>) {
              final Object? name = item['name'] ?? item['model'];
              if (name is String) models.add(name);
            }
          }
        }
      }

      final bool hasModel = models.any(
        (String m) => m == model || m.startsWith('$model:') || m.split(':').first == model.split(':').first,
      );
      return LlmHealth(
        reachable: true,
        installedModels: models,
        modelInstalled: hasModel,
        message: hasModel
            ? '연결 성공'
            : '서버는 연결됐지만 모델 "$model" 이 없습니다. `ollama pull $model` 을 실행하세요.',
      );
    } on Object catch (e) {
      return LlmHealth(reachable: false, message: _describeError(e));
    }
  }

  /// 가맹점명을 분류하고 **모델의 원본 응답 문자열**을 반환한다.
  ///
  /// 파싱/검증은 상위 계층(`ClassificationDto`)의 책임이다.
  Future<String> classifyMerchant({
    required String baseUrl,
    required String model,
    required String merchantName,
    required Duration timeout,
  }) async {
    final Uri uri = _resolve(baseUrl, '/api/generate');
    // 모델이 추론(thinking) 모델인지에 따라 요청이 달라진다.
    // 사용자가 설정에서 어떤 모델이든 넣을 수 있으므로 여기서 적응해야 한다.
    final bool thinking = isThinkingModel(model);

    final Map<String, Object?> body = <String, Object?>{
      'model': model,
      'prompt': buildPrompt(merchantName, suppressThinking: thinking),
      'stream': false,
      // Ollama 의 강제 JSON 출력 모드.
      'format': 'json',
      // **추론 모델에만** think 필드를 보낸다.
      // 최신 Ollama 는 thinking 을 지원하지 않는 모델(gemma3 등)에 이 필드가
      // 오면 "does not support thinking" 으로 요청 전체를 거절한다.
      if (thinking) 'think': false,
      'options': <String, Object?>{
        'temperature': 0,
        'top_p': 0.9,
        'num_predict': 200,
      },
    };

    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw LlmFailure(
          'Ollama 응답 오류: ${utf8.decode(response.bodyBytes)}',
          statusCode: response.statusCode,
        );
      }

      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const LlmContractFailure('응답이 JSON 객체가 아닙니다.');
      }
      final Object? content = decoded['response'];
      if (content is! String || content.trim().isEmpty) {
        throw const LlmContractFailure('응답에 response 필드가 없습니다.');
      }
      return content;
    } on LlmFailure {
      rethrow;
    } on LlmContractFailure {
      rethrow;
    } on Object catch (e) {
      throw LlmFailure(_describeError(e));
    }
  }

  /// 분류 프롬프트.
  ///
  /// 설계 의도
  ///  - **JSON 만** 출력하도록 반복 지시한다.
  ///  - 허용 카테고리를 프롬프트에 모두 나열해 환각을 줄인다.
  ///  - few-shot 예시로 출력 형태를 고정한다.
  ///  - 브랜드/지점 분리를 명시적으로 요구한다.
  /// 모델 이름으로 추론(thinking) 모델인지 판단한다.
  ///
  /// 완벽할 수 없는 판단이지만, 틀려도 손해가 비대칭이다.
  ///  - 추론 모델을 놓치면 `<think>` 블록이 섞여 오는데, 응답 정리 단계에서
  ///    어차피 제거한다.
  ///  - 반대로 일반 모델에 `think` 를 보내면 **요청 자체가 거절된다.**
  /// 그래서 확실한 것만 추론 모델로 본다.
  static bool isThinkingModel(String model) {
    final String name = model.toLowerCase();
    return name.startsWith('qwen3') ||
        name.contains('deepseek-r1') ||
        name.contains('-r1') ||
        name.contains('thinking') ||
        name.startsWith('o1') ||
        name.startsWith('magistral');
  }

  static String buildPrompt(
    String merchantName, {
    bool suppressThinking = false,
  }) {
    final StringBuffer taxonomy = StringBuffer();
    CategoryTaxonomy.tree.forEach((String category, List<String> subs) {
      taxonomy.writeln('- $category: ${subs.join(', ')}');
    });

    // `/no_think` 는 Qwen3 계열이 알아듣는 지시다. 다른 모델에는 의미 없는
    // 토큰이므로 붙이지 않는다.
    final String prefix = suppressThinking ? '/no_think\n' : '';

    return '''$prefix당신은 한국 카드 결제 내역의 가맹점명을 분류하는 시스템입니다.
설명이나 인사말 없이 JSON 객체 하나만 출력하세요.

[허용된 카테고리 / 서브카테고리]
$taxonomy
[규칙]
1. category 는 위 목록의 카테고리 중 하나여야 합니다.
2. subcategory 는 해당 category 에 속한 값이어야 합니다.
3. brand 는 지점명을 제외한 대표 브랜드명입니다. (예: "메가MGC커피 춘천후평점" -> "메가커피")
4. branch 는 지점명입니다. 없으면 null 을 넣으세요.
5. confidence 는 0.0~1.0 의 확신도입니다. 모르는 가맹점이면 낮게 주세요.
6. 판단이 불가능하면 category="기타", subcategory="미분류" 로 하세요.

[예시]
입력: 메가MGC커피 춘천후평점
출력: {"brand":"메가커피","branch":"춘천후평점","category":"식비","subcategory":"카페","confidence":0.95}

입력: 만복국수
출력: {"brand":"만복국수","branch":null,"category":"식비","subcategory":"한식","confidence":0.8}

입력: GS25 역삼점
출력: {"brand":"GS25","branch":"역삼점","category":"생활","subcategory":"편의점","confidence":0.97}

입력: 주식회사케이엘디
출력: {"brand":"주식회사케이엘디","branch":null,"category":"기타","subcategory":"미분류","confidence":0.2}

[분류할 가맹점]
입력: $merchantName
출력:''';
  }

  Uri _resolve(String baseUrl, String path) {
    final String trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed$path');
  }

  static String _describeError(Object error) {
    final String raw = error.toString();
    if (raw.contains('TimeoutException')) {
      return '응답 시간 초과. Ollama 가 실행 중인지 확인하세요.';
    }
    if (raw.contains('SocketException') || raw.contains('Connection refused')) {
      return 'Ollama 서버에 연결할 수 없습니다. 주소와 실행 상태를 확인하세요.';
    }
    return raw;
  }

  void dispose() => _client.close();
}

