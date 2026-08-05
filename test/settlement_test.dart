import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/settlements/domain/entities/deposit.dart';
import 'package:budget_book/features/settlements/domain/entities/settlement.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// 정산(더치페이) 계산 테스트.
///
/// 핵심 불변식: **원본 거래 금액은 절대 바뀌지 않는다.**
/// 통계는 `netAmount`, 카드 명세 대조는 `amount` 를 쓴다.
void main() {
  Transaction tx({
    required int amount,
    int settled = 0,
    bool cancelled = false,
  }) {
    return Transaction(
      merchantRaw: '스타벅스 강남점',
      brand: '스타벅스',
      amount: amount,
      category: '식비',
      subcategory: '카페',
      method: PaymentMethodKind.card,
      paymentDatetime: DateTime(2026, 8, 4, 14, 33),
      rawNotification: '...',
      fingerprint: 'fp',
      classificationSource: ClassificationSource.seed,
      isCancelled: cancelled,
      settledAmount: settled,
    );
  }

  group('실제 부담 금액', () {
    test('정산이 없으면 원본 금액과 같다', () {
      final Transaction t = tx(amount: 30000);

      expect(t.amount, 30000);
      expect(t.netAmount, 30000);
      expect(t.hasSettlements, isFalse);
      expect(t.settlementStatus, SettlementStatus.none);
    });

    test('요구사항 예시: 30,000원 결제 + 20,000원 정산 = 10,000원 부담', () {
      final Transaction t = tx(amount: 30000, settled: 20000);

      // 원본은 그대로여야 한다. 카드 명세와 일치해야 하기 때문이다.
      expect(t.amount, 30000);
      expect(t.settledAmount, 20000);
      expect(t.netAmount, 10000);
      expect(t.settlementStatus, SettlementStatus.partial);
    });

    test('전액을 돌려받으면 부담 0, 상태는 정산 완료', () {
      final Transaction t = tx(amount: 30000, settled: 30000);

      expect(t.amount, 30000);
      expect(t.netAmount, 0);
      expect(t.settlementStatus, SettlementStatus.completed);
    });

    test('초과 입금도 허용한다(원본은 유지)', () {
      final Transaction t = tx(amount: 30000, settled: 35000);

      expect(t.amount, 30000);
      expect(t.netAmount, -5000);
      expect(t.settlementStatus, SettlementStatus.completed);
    });

    test('남은 금액 계산', () {
      expect(tx(amount: 30000).unsettledAmount, 30000);
      expect(tx(amount: 30000, settled: 10000).unsettledAmount, 20000);
      expect(tx(amount: 30000, settled: 30000).unsettledAmount, 0);
      expect(
        tx(amount: 30000, settled: 40000).unsettledAmount,
        0,
        reason: '음수가 되지 않아야 한다',
      );
    });

    test('취소 거래(음수)도 부호가 깨지지 않는다', () {
      final Transaction t = tx(amount: -6200, cancelled: true);

      expect(t.netAmount, -6200);
      expect(t.settlementStatus, SettlementStatus.none);
    });
  });

  group('copyWith 는 원본 금액을 바꾸지 않는다', () {
    test('분류를 고쳐도 amount 는 유지된다', () {
      final Transaction original = tx(amount: 30000, settled: 20000);
      final Transaction updated = original.copyWith(
        category: '문화/여가',
        subcategory: '영화',
        classificationSource: ClassificationSource.user,
      );

      expect(updated.amount, 30000, reason: '원본 결제 금액은 불변');
      expect(updated.settledAmount, 20000);
      expect(updated.netAmount, 10000);
    });
  });

  group('Settlement', () {
    test('입금에서 자동 생성된 정산은 표시가 남는다', () {
      final Settlement auto = Settlement(
        transactionId: 1,
        counterparty: '김철수',
        amount: 10000,
        settledAt: _fixedTime,
        depositId: 7,
      );

      expect(auto.isAutoLinked, isTrue);
    });

    test('수동 정산은 입금 연결 표시가 없다', () {
      final Settlement manual = Settlement(
        transactionId: 1,
        counterparty: '이영희',
        amount: 10000,
        settledAt: _fixedTime,
      );

      expect(manual.isAutoLinked, isFalse);
    });
  });

  group('Deposit', () {
    test('같은 입금은 같은 지문을 만든다', () {
      final String a = Deposit.buildFingerprint(
        counterparty: '홍길동',
        amount: 10000,
        depositedAt: DateTime(2026, 8, 4, 14, 33, 10),
      );
      final String b = Deposit.buildFingerprint(
        counterparty: '홍 길동',
        amount: 10000,
        depositedAt: DateTime(2026, 8, 4, 14, 33, 55),
      );

      expect(a, b, reason: '공백과 초 단위 차이는 무시한다');
    });

    test('금액이 다르면 다른 지문', () {
      expect(
        Deposit.buildFingerprint(
          counterparty: '홍길동',
          amount: 10000,
          depositedAt: _fixedTime,
        ),
        isNot(
          Deposit.buildFingerprint(
            counterparty: '홍길동',
            amount: 20000,
            depositedAt: _fixedTime,
          ),
        ),
      );
    });

    test('기본 상태는 연결 대기', () {
      final Deposit deposit = Deposit(
        counterparty: '홍길동',
        amount: 10000,
        depositedAt: _fixedTime,
        rawNotification: '...',
        fingerprint: 'fp',
      );

      expect(deposit.status, DepositStatus.pending);
      expect(deposit.isPending, isTrue);
    });

    test('상태 코드를 읽을 수 있다', () {
      expect(DepositStatus.fromCode('linked'), DepositStatus.linked);
      expect(DepositStatus.fromCode('ignored'), DepositStatus.ignored);
      expect(DepositStatus.fromCode(null), DepositStatus.pending);
      expect(DepositStatus.fromCode('없는값'), DepositStatus.pending);
    });
  });
}

final DateTime _fixedTime = DateTime(2026, 8, 4, 14, 33);
