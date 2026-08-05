import 'package:budget_book/features/classification/data/datasources/ollama_remote_datasource.dart';
import 'package:budget_book/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// 모델별 요청 호환성.
///
/// 사용자가 설정에서 어떤 Ollama 모델이든 넣을 수 있으므로 요청이 모델에
/// 맞춰 달라져야 한다.
///
/// **틀렸을 때의 손해가 비대칭이다.**
///  - 추론 모델을 못 알아보면 `<think>` 블록이 섞여 오는데, 응답 정리
///    단계에서 어차피 제거한다 → 회복 가능
///  - 일반 모델에 `think` 필드를 보내면 최신 Ollama 가
///    "does not support thinking" 으로 **요청 전체를 거절한다** → 분류 실패
///
/// 그래서 확실한 것만 추론 모델로 판단한다.
void main() {
  group('추론 모델 판별', () {
    test('Qwen3 계열은 추론 모델이다', () {
      expect(OllamaRemoteDataSource.isThinkingModel('qwen3:4b'), isTrue);
      expect(OllamaRemoteDataSource.isThinkingModel('qwen3:8b'), isTrue);
      expect(OllamaRemoteDataSource.isThinkingModel('QWEN3:4B'), isTrue);
    });

    test('DeepSeek-R1 계열은 추론 모델이다', () {
      expect(
        OllamaRemoteDataSource.isThinkingModel('deepseek-r1:7b'),
        isTrue,
      );
      expect(OllamaRemoteDataSource.isThinkingModel('qwq-r1'), isTrue);
    });

    test('Gemma3 는 추론 모델이 아니다', () {
      expect(OllamaRemoteDataSource.isThinkingModel('gemma3:4b'), isFalse);
      expect(OllamaRemoteDataSource.isThinkingModel('gemma3:12b'), isFalse);
    });

    test('일반 모델들도 추론 모델이 아니다', () {
      for (final String model in <String>[
        'llama3.2:3b',
        'mistral:7b',
        'phi4',
        'qwen2.5:7b', // qwen 이지만 3세대가 아니다
      ]) {
        expect(
          OllamaRemoteDataSource.isThinkingModel(model),
          isFalse,
          reason: '$model 에 think 를 보내면 요청이 거절된다',
        );
      }
    });
  });

  group('프롬프트', () {
    test('추론 모델에는 /no_think 를 붙인다', () {
      final String prompt = OllamaRemoteDataSource.buildPrompt(
        '메가커피',
        suppressThinking: true,
      );
      expect(prompt.startsWith('/no_think'), isTrue);
    });

    test('일반 모델에는 붙이지 않는다', () {
      final String prompt = OllamaRemoteDataSource.buildPrompt(
        '메가커피',
        suppressThinking: false,
      );
      expect(prompt.contains('/no_think'), isFalse);
      expect(prompt.startsWith('당신은'), isTrue);
    });

    test('어느 쪽이든 분류 지시와 가맹점명은 들어간다', () {
      for (final bool suppress in <bool>[true, false]) {
        final String prompt = OllamaRemoteDataSource.buildPrompt(
          '행복반점',
          suppressThinking: suppress,
        );
        expect(prompt, contains('행복반점'));
        expect(prompt, contains('JSON'));
        // 허용 카테고리를 프롬프트에 나열해 환각을 줄인다.
        expect(prompt, contains('식비'));
      }
    });

    test('기본값은 붙이지 않는 쪽이다', () {
      // 기본 모델이 일반 모델이므로 안전한 쪽이 기본이어야 한다.
      expect(
        OllamaRemoteDataSource.buildPrompt('메가커피').contains('/no_think'),
        isFalse,
      );
    });
  });

  group('기본 설정', () {
    test('기본 모델은 gemma3:4b 다', () {
      expect(AppSettings.defaultOllamaModel, 'gemma3:4b');
      expect(const AppSettings().ollamaModel, 'gemma3:4b');
    });

    test('기본 모델은 추론 모델이 아니므로 think 를 보내지 않는다', () {
      expect(
        OllamaRemoteDataSource.isThinkingModel(
          AppSettings.defaultOllamaModel,
        ),
        isFalse,
      );
    });

    test('AI 는 기본으로 꺼져 있다', () {
      // 이 앱의 원칙이다. LLM 은 필수 요소가 아니다.
      expect(const AppSettings().llmEnabled, isFalse);
    });
  });
}
