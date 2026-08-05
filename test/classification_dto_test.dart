import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/error/failures.dart';
import 'package:budget_book/features/classification/data/models/classification_dto.dart';
import 'package:budget_book/features/classification/domain/entities/merchant_classification.dart';
import 'package:flutter_test/flutter_test.dart';

/// LLM 응답 검증 테스트.
///
/// "모든 AI 응답은 검증 후 DB 에 저장한다" 원칙이 실제로 지켜지는지 확인한다.
void main() {
  MerchantClassification parse(String raw, {String fallback = '테스트가맹점'}) {
    return ClassificationDto.parse(
      rawResponse: raw,
      merchantNameFallback: fallback,
    );
  }

  group('정상 응답', () {
    test('깨끗한 JSON 을 그대로 파싱한다', () {
      final MerchantClassification result = parse(
        '{"brand":"메가커피","branch":"춘천후평점","category":"식비",'
        '"subcategory":"카페","confidence":0.95}',
      );

      expect(result.brand, '메가커피');
      expect(result.branch, '춘천후평점');
      expect(result.category, '식비');
      expect(result.subcategory, '카페');
      expect(result.confidence, closeTo(0.95, 0.001));
      expect(result.source, ClassificationSource.llm);
    });
  });

  group('추론 모델 대응', () {
    test('<think> 블록을 제거한다 (Qwen3)', () {
      final MerchantClassification result = parse(
        '<think>사용자가 커피 가맹점을 물었다. 카페로 분류해야 한다.</think>\n'
        '{"brand":"스타벅스","branch":null,"category":"식비","subcategory":"카페"}',
      );

      expect(result.brand, '스타벅스');
      expect(result.subcategory, '카페');
      expect(result.branch, isNull);
    });

    test('닫히지 않은 <think> 도 방어한다', () {
      final MerchantClassification result = parse(
        '{"brand":"스타벅스","category":"식비","subcategory":"카페"}\n'
        '<think>추가로 생각하면...',
      );

      expect(result.brand, '스타벅스');
    });

    test('코드펜스로 감싼 응답을 처리한다', () {
      final MerchantClassification result = parse(
        '```json\n{"brand":"GS25","category":"생활","subcategory":"편의점"}\n```',
      );

      expect(result.brand, 'GS25');
      expect(result.category, '생활');
    });

    test('앞뒤 잡담이 있어도 첫 JSON 객체만 추출한다', () {
      final MerchantClassification result = parse(
        '알겠습니다. 결과는 다음과 같습니다:\n'
        '{"brand":"다이소","category":"생활","subcategory":"생활용품"}\n'
        '도움이 되었길 바랍니다.',
      );

      expect(result.brand, '다이소');
      expect(result.subcategory, '생활용품');
    });

    test('문자열 안의 중괄호에 속지 않는다', () {
      final MerchantClassification result = parse(
        r'{"brand":"이상한{가게}","category":"식비","subcategory":"한식"}',
      );

      expect(result.brand, '이상한{가게}');
      expect(result.category, '식비');
    });
  });

  group('허용 목록 검증 (환각 방어)', () {
    test('존재하지 않는 카테고리는 기타/미분류로 보정한다', () {
      final MerchantClassification result = parse(
        '{"brand":"무엇","category":"우주여행","subcategory":"로켓"}',
      );

      expect(result.category, '기타');
      expect(result.subcategory, '미분류');
    });

    test('카테고리는 맞고 서브카테고리만 틀리면 해당 카테고리의 기타로 보정한다', () {
      final MerchantClassification result = parse(
        '{"brand":"무엇","category":"식비","subcategory":"우주식량"}',
      );

      expect(result.category, '식비');
      expect(result.subcategory, '기타');
    });

    test('카테고리/서브카테고리가 뒤바뀌어 있으면 보정된다', () {
      final MerchantClassification result = parse(
        '{"brand":"무엇","category":"카페","subcategory":"식비"}',
      );

      expect(result.category, '기타');
      expect(result.subcategory, '미분류');
    });
  });

  group('필드 누락 / 형식 오류', () {
    test('brand 가 없으면 가맹점 원본 문자열로 대체한다', () {
      final MerchantClassification result = parse(
        '{"category":"식비","subcategory":"한식"}',
        fallback: '만복국수',
      );

      expect(result.brand, '만복국수');
    });

    test('문자열 "null" 을 실제 null 로 처리한다', () {
      final MerchantClassification result = parse(
        '{"brand":"스타벅스","branch":"null","category":"식비","subcategory":"카페"}',
      );

      expect(result.branch, isNull);
    });

    test('confidence 가 없으면 보수적인 기본값을 쓴다', () {
      final MerchantClassification result = parse(
        '{"brand":"스타벅스","category":"식비","subcategory":"카페"}',
      );

      expect(result.confidence, closeTo(0.7, 0.001));
    });

    test('confidence 가 범위를 벗어나면 0~1 로 자른다', () {
      expect(
        parse('{"brand":"A","category":"식비","subcategory":"카페","confidence":5}')
            .confidence,
        1.0,
      );
      expect(
        parse('{"brand":"A","category":"식비","subcategory":"카페","confidence":-2}')
            .confidence,
        0.0,
      );
    });

    test('confidence 가 문자열이어도 파싱한다', () {
      final MerchantClassification result = parse(
        '{"brand":"A","category":"식비","subcategory":"카페","confidence":"0.8"}',
      );

      expect(result.confidence, closeTo(0.8, 0.001));
    });
  });

  group('완전 실패', () {
    test('JSON 이 없으면 LlmContractFailure 를 던진다', () {
      expect(
        () => parse('죄송하지만 분류할 수 없습니다.'),
        throwsA(isA<LlmContractFailure>()),
      );
    });

    test('닫히지 않은 JSON 도 실패로 처리한다', () {
      expect(
        () => parse('{"brand":"스타벅스","category":"식비"'),
        throwsA(isA<LlmContractFailure>()),
      );
    });

    test('JSON 배열은 거부한다', () {
      expect(
        () => parse('[1, 2, 3]'),
        throwsA(isA<LlmContractFailure>()),
      );
    });
  });
}
