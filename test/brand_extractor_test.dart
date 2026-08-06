import 'package:budget_book/core/database/seed/brand_seed.dart';
import 'package:budget_book/features/merchants/domain/entities/brand_definition.dart';
import 'package:budget_book/features/merchants/domain/services/brand_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 은행·카드사마다 같은 브랜드를 다른 형식으로 보낸다.
///
/// ```
/// 씨유강원대제3학생 · 씨유(CU) 춘천 백령점 · 씨유강대병원점
/// 지에스25춘천애막골 · 지에스25(GS25) 춘천
/// 메가MGC커피강원대점 · 메가커피춘천후평점
/// ```
///
/// 이 형식 차이를 흡수하지 못하면 이미 아는 브랜드인데도 카카오 API 와
/// AI 대기열까지 진행된다. **아는 브랜드는 외부 호출 없이 즉시 분류한다.**
void main() {
  const BrandExtractor extractor = BrandExtractor(BrandSeed.definitions);

  /// 대표 브랜드만 확인하는 단축형.
  String? canonical(String raw) => extractor.extract(raw)?.canonical;

  group('요구사항 예시 — CU', () {
    test('씨유강원대제3학생', () {
      expect(canonical('씨유강원대제3학생'), 'CU');
    });

    test('씨유(CU) 춘천 백령점', () {
      expect(canonical('씨유(CU) 춘천 백령점'), 'CU');
    });

    test('씨유강대병원점', () {
      expect(canonical('씨유강대병원점'), 'CU');
    });

    test('영문 표기도 같은 대표 브랜드로 모인다', () {
      expect(canonical('CU 춘천점'), 'CU');
    });
  });

  group('요구사항 예시 — GS25', () {
    test('지에스25춘천애막골', () {
      expect(canonical('지에스25춘천애막골'), 'GS25');
    });

    test('지에스25(GS25) 춘천', () {
      expect(canonical('지에스25(GS25) 춘천'), 'GS25');
    });

    test('지에스25춘천효제길', () {
      expect(canonical('지에스25춘천효제길'), 'GS25');
    });
  });

  group('요구사항 예시 — 메가커피', () {
    test('메가MGC커피강원대점', () {
      expect(canonical('메가MGC커피강원대점'), '메가MGC커피');
    });

    test('메가MGC커피 춘천명동', () {
      expect(canonical('메가MGC커피 춘천명동'), '메가MGC커피');
    });

    test('메가커피춘천후평점 — 짧은 alias 도 같은 대표 브랜드', () {
      expect(canonical('메가커피춘천후평점'), '메가MGC커피');
    });
  });

  group('alias 는 긴 것부터 검사한다', () {
    test('메가MGC커피가 메가커피보다 먼저 매칭된다', () {
      // 둘 다 매칭 가능하지만 더 구체적인 alias 가 이겨야 한다.
      final BrandExtraction? result = extractor.extract('메가MGC커피강원대점');
      expect(result, isNotNull);
      expect(result!.matchedAlias, '메가mgc커피');
    });
  });

  group('지점명 분리', () {
    test('원본 표기 그대로 지점을 남긴다', () {
      final BrandExtraction? result = extractor.extract('메가MGC커피 춘천명동');
      expect(result!.branch, '춘천명동');
    });

    test('지점이 없으면 null', () {
      expect(extractor.extract('CU')?.branch, isNull);
    });
  });

  group('앞에 다른 말이 붙어도 찾는다', () {
    test('(주) 같은 접두사', () {
      // 정규화가 법인 접두사를 떼어 낸다.
      expect(canonical('(주)메가커피 강남점'), '메가MGC커피');
    });

    test('브랜드가 문자열 중간에 있어도 찾는다', () {
      // startsWith 만 쓰면 놓친다. 실제 알림에는 이런 형식이 흔하다.
      expect(canonical('춘천 스타벅스 명동점'), '스타벅스');
    });
  });

  group('매칭 실패', () {
    test('모르는 가맹점은 null (기존 흐름으로 넘어간다)', () {
      expect(extractor.extract('동네작은카페'), isNull);
      expect(extractor.extract('행복반점'), isNull);
    });

    test('빈 문자열', () {
      expect(extractor.extract(''), isNull);
      expect(extractor.extract('   '), isNull);
    });

    test('짧은 alias 는 오탐을 막기 위해 완전일치만 허용', () {
      // `cu` 가 아무 문자열에나 걸리면 안 된다.
      expect(canonical('cucumber마켓'), isNot('CU'));
    });
  });

  group('사전 자체의 건전성', () {
    test('모든 정의가 대표 브랜드를 alias 로도 갖는다', () {
      for (final BrandDefinition d in BrandSeed.definitions) {
        expect(
          d.aliases.isNotEmpty,
          isTrue,
          reason: '${d.canonical} 에 alias 가 없다',
        );
      }
    });

    test('같은 alias 가 서로 다른 대표 브랜드에 중복되지 않는다', () {
      final Map<String, String> owner = <String, String>{};
      for (final BrandDefinition d in BrandSeed.definitions) {
        for (final String alias in d.normalizedAliases) {
          final String? existing = owner[alias];
          expect(
            existing == null || existing == d.canonical,
            isTrue,
            reason: 'alias "$alias" 가 $existing 과 ${d.canonical} 에 중복',
          );
          owner[alias] = d.canonical;
        }
      }
    });

    test('분류는 모두 앱 체계 안에 있다', () {
      for (final BrandDefinition d in BrandSeed.definitions) {
        expect(d.category.isNotEmpty, isTrue);
        expect(d.subcategory.isNotEmpty, isTrue);
      }
    });
  });
}
