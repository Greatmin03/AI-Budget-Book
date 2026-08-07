import 'package:budget_book/features/notifications/domain/entities/raw_notification.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/parsing/domain/services/payment_notification_parser.dart';
import 'package:budget_book/features/merchants/domain/services/brand_learning_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const PaymentNotificationParser parser = PaymentNotificationParser();

  /// 알림 수신 시각. 본문의 `MM/DD` 연도 추론 기준이 된다.
  final DateTime postedAt = DateTime(2026, 12, 25, 14, 33);

  RawNotification build({
    required String packageName,
    String title = '',
    String text = '',
    String? bigText,
    DateTime? at,
  }) {
    return RawNotification(
      packageName: packageName,
      title: title,
      text: text,
      bigText: bigText,
      postedAt: at ?? postedAt,
    );
  }

  ParsedPayment success(ParseOutcome outcome) {
    expect(outcome, isA<ParseSuccess>(), reason: '파싱이 성공해야 한다: $outcome');
    return (outcome as ParseSuccess).payment;
  }

  group('카드 승인 알림', () {
    test('KB국민카드 - 가맹점 / 금액 / 시각 / 일시불', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbcard.cxh.appcard',
            title: 'KB국민카드',
            text: 'KB국민카드 승인 홍*동 6,200원 일시불 12/25 14:33 '
                '스타벅스강남점 누적 1,234,567원',
          ),
        ),
      );

      expect(p.merchantRaw, '스타벅스강남점');
      expect(p.amount, 6200);
      expect(p.signedAmount, 6200);
      expect(p.cardName, 'KB국민카드');
      expect(p.installmentMonths, 0);
      expect(p.isCancellation, isFalse);
      expect(p.method, PaymentMethodKind.card);
      expect(p.paymentDatetime, DateTime(2026, 12, 25, 14, 33));
    });

    test('누적 금액을 결제 금액으로 오인하지 않는다 (누적이 앞에 와도)', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbcard.cxh.appcard',
            text: '누적 1,234,567원 승인 6,200원 스타벅스강남점',
          ),
        ),
      );

      expect(p.amount, 6200);
    });

    test('잔액 표기도 금액 후보에서 제외한다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.wooribank.smart.npib',
            text: '우리은행 출금 30,000원 잔액 1,500,000원 김밥천국',
          ),
        ),
      );

      expect(p.amount, 30000);
      expect(p.method, PaymentMethodKind.accountTransfer);
    });

    test('승인취소는 음수 금액이 된다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.shinhancard.smartshinhan',
            text: '신한카드(1234) 승인취소 6,200원 12/25 15:00 스타벅스강남점',
          ),
        ),
      );

      expect(p.isCancellation, isTrue);
      expect(p.amount, 6200, reason: 'amount 는 항상 양수');
      expect(p.signedAmount, -6200, reason: '합산에 쓰이는 값은 음수');
      expect(p.cardName, '신한카드');
      expect(p.merchantRaw, '스타벅스강남점');
    });

    test('할부 개월수를 추출한다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'kr.co.samsungcard.mpocket',
            text: '삼성카드 승인 450,000원 3개월 할부 12/25 11:20 하이마트수원점',
          ),
        ),
      );

      expect(p.amount, 450000);
      expect(p.installmentMonths, 3);
    });

    test('대괄호 카드사 표기와 Web발신 머리말을 걷어낸다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.samsung.android.messaging',
            title: '01012345678',
            text: '[Web발신]\n[KB국민카드] 승인 12,000원 12/25 19:04 배달의민족',
          ),
        ),
      );

      expect(p.merchantRaw, '배달의민족');
      expect(p.amount, 12000);
      expect(p.cardName, 'KB국민카드', reason: 'SMS 는 본문에서 카드사를 찾아야 한다');
    });

    test('가맹점이 공백을 포함해도 한 덩어리로 유지된다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.hyundaicard.appcard',
            text: '현대카드 승인 8,500원 일시불 12/25 12:10 메가MGC커피 춘천후평점',
          ),
        ),
      );

      expect(p.merchantRaw, '메가MGC커피 춘천후평점');
    });

    test('간편결제는 결제수단이 easyPay 로 분류된다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'viva.republica.toss',
            title: '토스',
            text: '6,200원 결제 스타벅스',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.easyPay);
      expect(p.merchantRaw, '스타벅스');
    });

    test('본문에 시각이 없으면 알림 수신 시각을 쓴다', () {
      final DateTime at = DateTime(2026, 8, 4, 9, 15);
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbcard.cxh.appcard',
            text: 'KB국민카드 승인 3,000원 만복국수',
            at: at,
          ),
        ),
      );

      expect(p.paymentDatetime, at);
    });

    test('연말/연초 경계: 12월 결제 알림을 1월에 처리해도 전년도로 본다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbcard.cxh.appcard',
            text: 'KB국민카드 승인 5,000원 12/31 23:50 스타벅스',
            at: DateTime(2027, 1, 1, 0, 5),
          ),
        ),
      );

      expect(p.paymentDatetime.year, 2026);
      expect(p.paymentDatetime.month, 12);
      expect(p.paymentDatetime.day, 31);
    });
  });

  group('거래 유형 판별 (브랜드 학습 여부를 좌우한다)', () {
    test('계좌 출금은 계좌이체로 본다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.wooribank.smart.npib',
            text: '우리은행 출금 50,000원 12/25 10:00 홍길동',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.accountTransfer);
      expect(p.method.isTransfer, isTrue);
      expect(p.method.identifiesMerchant, isFalse);
    });

    test('자동이체는 계좌이체로 본다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbstar.kbbank',
            text: 'KB국민은행 자동이체 55,000원 넷플릭스',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.accountTransfer);
    });

    test('간편결제 앱의 송금은 간편결제가 아니라 송금이다', () {
      // 순서가 중요한 지점: 카카오페이라는 이유로 간편결제(=가맹점 결제)로
      // 분류해 버리면 사람 이름이 브랜드로 학습될 수 있다.
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kakaopay.app',
            title: '카카오페이',
            text: '송금 30,000원 홍길동님에게 보냈습니다',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.remittance);
      expect(p.method.identifiesMerchant, isFalse);
    });

    test('토스 송금 문구도 잡아낸다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'viva.republica.toss',
            title: '토스',
            text: '홍길동님에게 20,000원을 보냈어요',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.remittance);
    });

    test('같은 앱의 가맹점 결제는 간편결제로 남는다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kakaopay.app',
            title: '카카오페이',
            text: '결제 6,200원 스타벅스 강남점',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.easyPay);
      expect(p.method.identifiesMerchant, isTrue);
    });

    test('카드 승인은 카드결제로 남는다', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbcard.cxh.appcard',
            text: 'KB국민카드 승인 6,200원 일시불 12/25 14:33 스타벅스강남점',
          ),
        ),
      );

      expect(p.method, PaymentMethodKind.card);
      expect(p.method.identifiesMerchant, isTrue);
    });
  });

  group('결제 알림이 아닌 것', () {
    test('결제 키워드가 없으면 무시한다', () {
      final ParseOutcome outcome = parser.parse(
        build(
          packageName: 'com.kakao.talk',
          title: '카카오톡',
          text: '새로운 메시지가 도착했습니다.',
        ),
      );

      expect(outcome, isA<ParseIgnored>());
    });

    test('광고/이벤트 알림은 제외 키워드로 걸러낸다', () {
      final ParseOutcome outcome = parser.parse(
        build(
          packageName: 'com.kbcard.cxh.appcard',
          text: '이벤트 응모하고 10,000원 쿠폰 받기! 결제 시 사용 가능',
        ),
      );

      expect(outcome, isA<ParseIgnored>());
    });

    test('금액을 찾을 수 없으면 실패로 기록한다(보관함 대상)', () {
      final ParseOutcome outcome = parser.parse(
        build(
          packageName: 'com.kbcard.cxh.appcard',
          text: 'KB국민카드 승인 내역을 확인하세요',
        ),
      );

      expect(outcome, isA<ParseFailed>());
    });

    test('빈 알림은 무시한다', () {
      final ParseOutcome outcome =
          parser.parse(build(packageName: 'com.kbcard.cxh.appcard'));

      expect(outcome, isA<ParseIgnored>());
    });
  });

  group('가맹점을 특정하지 못하는 경우', () {
    test('금액만 있으면 미확인 가맹점으로 기록한다(금액 유실 방지)', () {
      final ParsedPayment p = success(
        parser.parse(
          build(
            packageName: 'com.kbcard.cxh.appcard',
            text: 'KB국민카드 승인 7,000원 일시불 12/25 14:33',
          ),
        ),
      );

      expect(p.isMerchantUnknown, isTrue);
      expect(p.amount, 7000);
    });
  });

  group('체크카드 출금은 이체가 아니다', () {
    /// 실제 기기에서 온 알림. `출금` 이 들어 있어 이체로 오인됐고,
    /// 그 결과 상대방 이름 보호 정책이 걸려 카카오 조회도 AI 분류도
    /// 전부 막혀서 영영 미분류로 남았다.
    ParsedPayment parseBankCard(String merchant) {
      final ParseOutcome outcome = const PaymentNotificationParser().parse(
        RawNotification(
          packageName: 'com.kbstar.kbbank',
          title: 'KB국민은행',
          text: '출금 9,630원\n박*민님 08/06 13:06 942902-**-***245 '
              '$merchant 체크카드출금 9,630 잔액1,384,495',
          postedAt: DateTime(2026, 8, 6, 13, 6),
        ),
      );
      expect(outcome, isA<ParseSuccess>());
      return (outcome as ParseSuccess).payment;
    }

    test('카드 결제로 판정된다', () {
      expect(parseBankCard('퀴즈노스춘천').method, PaymentMethodKind.card);
    });

    test('가맹점 학습이 막히지 않는다', () {
      final ParsedPayment payment = parseBankCard('퀴즈노스춘천');
      const BrandLearningPolicy policy = BrandLearningPolicy();

      final BrandLearningDecision decision = policy.evaluate(
        method: payment.method,
        brand: payment.merchantRaw,
        merchantRaw: payment.merchantRaw,
      );

      // 막히면 카카오 조회도 AI 대기열도 못 간다.
      expect(decision.stance, BrandLearningStance.allowed);
    });

    test('직불카드도 마찬가지다', () {
      final ParseOutcome outcome = const PaymentNotificationParser().parse(
        RawNotification(
          packageName: 'com.kbstar.kbbank',
          title: 'KB국민은행',
          text: '출금 5,000원 홍*동님 직불카드출금 스타벅스 잔액100,000',
          postedAt: DateTime(2026, 8, 6, 13, 6),
        ),
      );
      expect(outcome, isA<ParseSuccess>());
      expect((outcome as ParseSuccess).payment.method, PaymentMethodKind.card);
    });

    test('진짜 이체는 그대로 이체다', () {
      final ParseOutcome outcome = const PaymentNotificationParser().parse(
        RawNotification(
          packageName: 'com.kbstar.kbbank',
          title: 'KB국민은행',
          text: '출금 50,000원 홍*동님 08/06 13:06 김철수 이체 잔액100,000',
          postedAt: DateTime(2026, 8, 6, 13, 6),
        ),
      );
      expect(outcome, isA<ParseSuccess>());
      // 상대방 이름이 브랜드로 학습되면 안 된다.
      expect(
        (outcome as ParseSuccess).payment.method,
        PaymentMethodKind.accountTransfer,
      );
    });
  });
}
