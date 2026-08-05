import 'package:budget_book/features/merchants/domain/services/brand_learning_policy.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:flutter_test/flutter_test.dart';

/// 브랜드 학습 정책 테스트.
///
/// 이 정책이 깨지면 사람 이름이 브랜드로 학습되어, 그 상대방에게 보내는
/// 모든 송금이 엉뚱한 카테고리로 분류된다. 회귀 방지가 중요한 지점이다.
void main() {
  const BrandLearningPolicy policy = BrandLearningPolicy();

  BrandLearningDecision decide({
    required PaymentMethodKind method,
    required String brand,
    String? raw,
  }) {
    return policy.evaluate(method: method, brand: brand, merchantRaw: raw);
  }

  group('가맹점 결제 — 학습 허용', () {
    test('카드 승인은 학습한다', () {
      final BrandLearningDecision d = decide(
        method: PaymentMethodKind.card,
        brand: '메가커피',
        raw: '메가MGC커피 춘천후평점',
      );

      expect(d.stance, BrandLearningStance.allowed);
      expect(d.canToggle, isTrue);
      expect(d.defaultsOn, isTrue);
    });

    test('간편결제 가맹점 결제는 학습한다', () {
      expect(
        decide(
          method: PaymentMethodKind.easyPay,
          brand: '배달의민족',
          raw: '배달의민족',
        ).stance,
        BrandLearningStance.allowed,
      );
      expect(
        decide(
          method: PaymentMethodKind.easyPay,
          brand: '네이버페이',
          raw: '네이버페이 주문',
        ).stance,
        BrandLearningStance.allowed,
      );
    });

    test('성씨로 시작하는 실제 상호는 막지 않는다(선택 가능)', () {
      // '이마트', '김밥천국' 은 사람 이름이 아니라 브랜드다.
      // 자동으로 금지해 버리면 정상 학습을 방해한다.
      for (final String brand in <String>['김밥천국', '한솥도시락', '이디야커피']) {
        final BrandLearningDecision d =
            decide(method: PaymentMethodKind.card, brand: brand, raw: brand);
        expect(d.isBlocked, isFalse, reason: brand);
        expect(d.canToggle, isTrue, reason: brand);
      }
    });
  });

  group('이체 / 송금 — 학습 금지', () {
    test('계좌이체는 어떤 브랜드명을 넣어도 금지된다', () {
      final BrandLearningDecision d = decide(
        method: PaymentMethodKind.accountTransfer,
        brand: '메가커피',
        raw: '000 스마트폰',
      );

      expect(d.stance, BrandLearningStance.blocked);
      expect(d.canToggle, isFalse);
      expect(d.defaultsOn, isFalse);
      expect(d.reason, contains('자동 학습할 수 없습니다'));
      expect(d.detail, contains('거래 목적'));
    });

    test('송금은 금지된다', () {
      final BrandLearningDecision d = decide(
        method: PaymentMethodKind.remittance,
        brand: '메가커피',
        raw: '홍길동',
      );

      expect(d.stance, BrandLearningStance.blocked);
    });

    test('사용자가 유효한 브랜드로 바꿔도 이체는 여전히 금지된다', () {
      // 요구사항의 핵심 사례:
      // `000 스마트폰` -> `메가커피` 로 고쳐도 규칙으로 저장하면 안 된다.
      final BrandLearningDecision d = decide(
        method: PaymentMethodKind.accountTransfer,
        brand: '스타벅스',
        raw: '000 스마트폰',
      );

      expect(d.isBlocked, isTrue);
    });

    test('결제 수단을 알 수 없으면 학습하지 않는다', () {
      expect(
        decide(
          method: PaymentMethodKind.unknown,
          brand: '메가커피',
          raw: '메가커피',
        ).isBlocked,
        isTrue,
      );
    });
  });

  group('사람 이름 / 전화번호 기반 거래', () {
    test('전화번호는 금지된다', () {
      for (final String value in <String>[
        '01012345678',
        '010-1234-5678',
        '010 1234 5678',
      ]) {
        expect(
          decide(method: PaymentMethodKind.card, brand: value, raw: value)
              .isBlocked,
          isTrue,
          reason: value,
        );
      }
    });

    test('원본 거래명이 전화번호면 브랜드를 고쳐도 금지된다', () {
      expect(
        decide(
          method: PaymentMethodKind.card,
          brand: '메가커피',
          raw: '01012345678',
        ).isBlocked,
        isTrue,
      );
    });

    test('숫자/계좌번호만 있는 거래명은 금지된다', () {
      expect(
        decide(
          method: PaymentMethodKind.card,
          brand: '110-234-567890',
          raw: '110-234-567890',
        ).isBlocked,
        isTrue,
      );
    });

    test('마스킹된 사람 이름은 금지된다', () {
      for (final String value in <String>['홍*동', '김**']) {
        expect(
          decide(method: PaymentMethodKind.card, brand: value, raw: value)
              .isBlocked,
          isTrue,
          reason: value,
        );
      }
    });

    test('사람 이름처럼 보이면 권하지 않음(금지는 아님)', () {
      final BrandLearningDecision d = decide(
        method: PaymentMethodKind.card,
        brand: '홍길동',
        raw: '홍길동',
      );

      expect(d.stance, BrandLearningStance.discouraged);
      expect(d.canToggle, isTrue, reason: '사용자가 판단할 수 있어야 한다');
      expect(d.defaultsOn, isFalse, reason: '기본값은 꺼져 있어야 한다');
    });

    test('가맹점을 특정하지 못한 거래는 금지된다', () {
      expect(
        decide(
          method: PaymentMethodKind.card,
          brand: ParsedPayment.unknownMerchantLabel,
          raw: ParsedPayment.unknownMerchantLabel,
        ).isBlocked,
        isTrue,
      );
      expect(
        decide(method: PaymentMethodKind.card, brand: '   ', raw: '').isBlocked,
        isTrue,
      );
    });
  });

  group('사람 이름 판별', () {
    test('2~3글자 + 흔한 성씨 = 사람 이름', () {
      expect(policy.looksLikePersonName('홍길동'), isTrue);
      expect(policy.looksLikePersonName('김철수'), isTrue);
      expect(policy.looksLikePersonName('박민'), isTrue);
    });

    test('4글자 이상은 사람 이름으로 보지 않는다', () {
      expect(policy.looksLikePersonName('김밥천국'), isFalse);
      expect(policy.looksLikePersonName('한솥도시락'), isFalse);
    });

    test('상호 토큰이 있으면 사람 이름이 아니다', () {
      expect(policy.looksLikePersonName('최카페'), isFalse);
      expect(policy.looksLikePersonName('이마트'), isFalse);
    });

    test('한글이 아니면 사람 이름으로 보지 않는다', () {
      expect(policy.looksLikePersonName('KFC'), isFalse);
      expect(policy.looksLikePersonName('CU'), isFalse);
      expect(policy.looksLikePersonName('김A'), isFalse);
    });

    test('흔하지 않은 성씨로 시작하면 사람 이름으로 보지 않는다', () {
      expect(policy.looksLikePersonName('메가'), isFalse);
      expect(policy.looksLikePersonName('컴포즈'), isFalse);
    });
  });

  group('거래 유형 속성', () {
    test('가맹점을 특정하는 유형', () {
      expect(PaymentMethodKind.card.identifiesMerchant, isTrue);
      expect(PaymentMethodKind.easyPay.identifiesMerchant, isTrue);
      expect(PaymentMethodKind.accountTransfer.identifiesMerchant, isFalse);
      expect(PaymentMethodKind.remittance.identifiesMerchant, isFalse);
      expect(PaymentMethodKind.unknown.identifiesMerchant, isFalse);
    });

    test('이체 계열 판별', () {
      expect(PaymentMethodKind.accountTransfer.isTransfer, isTrue);
      expect(PaymentMethodKind.remittance.isTransfer, isTrue);
      expect(PaymentMethodKind.card.isTransfer, isFalse);
    });

    test('저장 코드와 옛 한국어 라벨을 모두 읽을 수 있다', () {
      expect(PaymentMethodKind.fromCode('card'), PaymentMethodKind.card);
      expect(
        PaymentMethodKind.fromCode('account_transfer'),
        PaymentMethodKind.accountTransfer,
      );
      // v2 까지 저장된 옛 값
      expect(PaymentMethodKind.fromCode('카드'), PaymentMethodKind.card);
      expect(
        PaymentMethodKind.fromCode('계좌출금'),
        PaymentMethodKind.accountTransfer,
      );
      expect(PaymentMethodKind.fromCode('간편결제'), PaymentMethodKind.easyPay);
      expect(PaymentMethodKind.fromCode(null), PaymentMethodKind.unknown);
      expect(PaymentMethodKind.fromCode('없는값'), PaymentMethodKind.unknown);
    });
  });
}
