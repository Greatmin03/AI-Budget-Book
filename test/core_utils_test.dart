import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/core/utils/month_range.dart';
import 'package:budget_book/core/utils/text_normalizer.dart';
import 'package:budget_book/features/classification/domain/entities/merchant_classification.dart';
import 'package:budget_book/features/classification/domain/services/rule_based_classifier.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:budget_book/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextNormalizer', () {
    test('공백/특수문자를 제거하고 영문을 소문자화한다', () {
      expect(TextNormalizer.normalize('스타벅스 강남점'), '스타벅스강남점');
      expect(TextNormalizer.normalize('메가MGC커피 춘천후평점'), '메가mgc커피춘천후평점');
      expect(TextNormalizer.normalize('GS25 역삼점'), 'gs25역삼점');
    });

    test('법인 접두어를 제거한다', () {
      expect(TextNormalizer.normalize('(주)스타벅스코리아'), '스타벅스코리아');
      expect(TextNormalizer.normalize('주식회사카카오'), '카카오');
    });

    test('normalize 와 normalizeWithIndex 의 결과가 일치한다', () {
      const List<String> samples = <String>[
        '스타벅스 강남점',
        '(주)스타벅스코리아',
        '메가MGC커피 춘천후평점',
        'GS25',
      ];
      for (final String sample in samples) {
        expect(
          TextNormalizer.normalizeWithIndex(sample).value,
          TextNormalizer.normalize(sample),
          reason: '두 함수가 어긋나면 브랜드 매칭이 깨진다: $sample',
        );
      }
    });

    test('정규화 인덱스로 원본 지점명을 잘라낼 수 있다', () {
      final NormalizedText n =
          TextNormalizer.normalizeWithIndex('메가MGC커피 춘천후평점');
      final int index = n.value.indexOf('메가mgc커피');

      expect(index, 0);
      expect(n.rawTailFrom('메가mgc커피'.length), '춘천후평점');
    });

    test('지점 접미사만 떼어낸다 (문자열 전체를 지우지 않는다)', () {
      expect(TextNormalizer.stripBranchSuffix('스타벅스강남점'), '스타벅스강남');
      expect(TextNormalizer.stripBranchSuffix('이마트본점'), '이마트');
      // 너무 짧아지면 원본을 유지한다.
      expect(TextNormalizer.stripBranchSuffix('약국'), '약국');
    });

    test('마스킹된 사람 이름을 식별한다', () {
      expect(TextNormalizer.isMaskedPersonName('홍*동'), isTrue);
      expect(TextNormalizer.isMaskedPersonName('김**'), isTrue);
      expect(TextNormalizer.isMaskedPersonName('스타벅스'), isFalse);
    });
  });

  group('MonthRange', () {
    test('월 경계를 정확히 계산한다', () {
      final MonthRange august = MonthRange(2026, 8);

      expect(august.start, DateTime(2026, 8, 1));
      expect(august.endExclusive, DateTime(2026, 9, 1));
    });

    test('12월의 다음 달은 다음 해 1월', () {
      final MonthRange next = MonthRange(2026, 12).next();

      expect(next.year, 2027);
      expect(next.month, 1);
    });

    test('1월의 이전 달은 전년 12월', () {
      final MonthRange previous = MonthRange(2026, 1).previous();

      expect(previous.year, 2025);
      expect(previous.month, 12);
    });

    test('범위를 벗어난 월 값을 정규화한다', () {
      final MonthRange normalized = MonthRange(2026, 13);

      expect(normalized.year, 2027);
      expect(normalized.month, 1);
    });

    test('lastMonths 는 오래된 순으로 반환한다', () {
      final List<MonthRange> months = MonthRange(2026, 2).lastMonths(4);

      expect(months.length, 4);
      expect(months.first.toString(), '2025-11');
      expect(months.last.toString(), '2026-02');
    });
  });

  group('CategoryTaxonomy', () {
    test('모든 카테고리에 기타 서브카테고리가 있다', () {
      for (final String category in CategoryTaxonomy.categories) {
        expect(
          CategoryTaxonomy.subcategoriesOf(category),
          contains('기타'),
          reason: '$category 에 기타 항목이 없으면 보정이 실패한다',
        );
      }
    });

    test('유효하지 않은 카테고리는 기타/미분류로 보정된다', () {
      final CategoryPair pair = CategoryTaxonomy.coerce('없는카테고리', '없는항목');

      expect(pair.category, '기타');
      expect(pair.subcategory, '미분류');
    });

    test('null 과 빈 문자열도 보정된다', () {
      expect(CategoryTaxonomy.coerce(null, null).category, '기타');
      expect(CategoryTaxonomy.coerce('  ', '  ').category, '기타');
    });

    test('유효한 조합은 그대로 통과한다', () {
      final CategoryPair pair = CategoryTaxonomy.coerce('식비', '카페');

      expect(pair.category, '식비');
      expect(pair.subcategory, '카페');
    });
  });

  group('RuleBasedClassifier (LLM 폴백)', () {
    const RuleBasedClassifier classifier = RuleBasedClassifier();

    test('업종 키워드로 분류한다', () {
      expect(classifier.classify('만복국수').subcategory, '한식');
      expect(classifier.classify('행복카페').subcategory, '카페');
      expect(classifier.classify('노랑통닭').subcategory, '치킨/피자');
      expect(classifier.classify('우리약국').subcategory, '약국');
    });

    test('긴 키워드가 먼저 적용된다', () {
      // '동물병원' 이 '병원' 보다 먼저 매칭되어야 한다.
      final MerchantClassification result = classifier.classify('행복동물병원');

      expect(result.category, '생활');
      expect(result.subcategory, '반려동물');
    });

    test('매칭이 없으면 기타/미분류를 반환하되 예외를 던지지 않는다', () {
      final MerchantClassification result = classifier.classify('주식회사케이엘디');

      expect(result.category, '기타');
      expect(result.subcategory, '미분류');
      expect(result.confidence, lessThan(0.5));
    });

    test('빈 문자열에도 결과를 반환한다', () {
      expect(() => classifier.classify(''), returnsNormally);
    });

    test('결과는 항상 허용 목록 안의 값이다', () {
      const List<String> samples = <String>[
        '만복국수',
        '메가커피',
        '알수없는가게123',
        '',
        '!!!',
      ];
      for (final String sample in samples) {
        final MerchantClassification result = classifier.classify(sample);
        expect(
          CategoryTaxonomy.isValidPair(result.category, result.subcategory),
          isTrue,
          reason: '$sample -> ${result.category}/${result.subcategory}',
        );
      }
    });
  });

  group('Transaction.buildFingerprint (중복 알림 방지)', () {
    test('같은 결제는 같은 지문을 만든다', () {
      final DateTime at = DateTime(2026, 8, 4, 14, 33);
      final String a = Transaction.buildFingerprint(
        merchantRaw: '스타벅스 강남점',
        signedAmount: 6200,
        paymentDatetime: at,
        cardName: 'KB국민카드',
      );
      final String b = Transaction.buildFingerprint(
        // 표기가 달라도 정규화 후 같으면 같은 지문
        merchantRaw: '스타벅스강남점',
        signedAmount: 6200,
        paymentDatetime: at,
        cardName: 'KB국민카드',
      );

      expect(a, b);
    });

    test('초 단위 차이는 무시한다', () {
      final String a = Transaction.buildFingerprint(
        merchantRaw: '스타벅스',
        signedAmount: 6200,
        paymentDatetime: DateTime(2026, 8, 4, 14, 33, 5),
      );
      final String b = Transaction.buildFingerprint(
        merchantRaw: '스타벅스',
        signedAmount: 6200,
        paymentDatetime: DateTime(2026, 8, 4, 14, 33, 52),
      );

      expect(a, b);
    });

    test('금액이 다르면 다른 지문', () {
      final DateTime at = DateTime(2026, 8, 4, 14, 33);
      expect(
        Transaction.buildFingerprint(
          merchantRaw: '스타벅스',
          signedAmount: 6200,
          paymentDatetime: at,
        ),
        isNot(
          Transaction.buildFingerprint(
            merchantRaw: '스타벅스',
            signedAmount: 5200,
            paymentDatetime: at,
          ),
        ),
      );
    });

    test('승인과 승인취소는 다른 지문 (부호가 다르다)', () {
      final DateTime at = DateTime(2026, 8, 4, 14, 33);
      expect(
        Transaction.buildFingerprint(
          merchantRaw: '스타벅스',
          signedAmount: 6200,
          paymentDatetime: at,
        ),
        isNot(
          Transaction.buildFingerprint(
            merchantRaw: '스타벅스',
            signedAmount: -6200,
            paymentDatetime: at,
          ),
        ),
      );
    });
  });
  group('Formatters.flowAmount (부호 규칙 단일 구현)', () {
    test('수입은 +', () {
      expect(Formatters.flowAmount(300000, isIncome: true), '+300,000원');
    });

    test('지출은 - (양수로 저장되므로 부호를 직접 붙인다)', () {
      expect(Formatters.flowAmount(15000, isIncome: false), '-15,000원');
    });

    test('지출인데 음수면 실제로 돌려받은 것이므로 +', () {
      // 취소/환불 거래는 amount 가 음수로 저장된다.
      expect(Formatters.flowAmount(-30000, isIncome: false), '+30,000원');
    });

    test('0은 부호를 붙이지 않는다', () {
      // 취소로 상쇄되어 0이 된 날. `-0원` 은 읽히지 않는다.
      expect(Formatters.flowAmount(0, isIncome: false), '0원');
      expect(Formatters.flowAmount(0, isIncome: true), '0원');
    });

    test('수입과 지출은 같은 금액에서 반대 부호가 된다', () {
      expect(
        Formatters.flowAmount(1000, isIncome: true),
        isNot(Formatters.flowAmount(1000, isIncome: false)),
      );
    });
  });
}
