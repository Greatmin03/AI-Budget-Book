import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/recurring/domain/entities/recurring_rule.dart';
import 'package:budget_book/features/recurring/domain/services/recurring_detector.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const RecurringDetector detector = RecurringDetector();

  Transaction payment({
    required String brand,
    required int amount,
    required DateTime at,
    bool cancelled = false,
    bool assetTransfer = false,
    String category = '주거/통신',
    String subcategory = '구독료',
  }) {
    return Transaction(
      merchantRaw: brand,
      brand: brand,
      amount: amount,
      category: category,
      subcategory: subcategory,
      method: PaymentMethodKind.card,
      paymentDatetime: at,
      rawNotification: '...',
      fingerprint: '$brand$amount${at.millisecondsSinceEpoch}',
      classificationSource: ClassificationSource.seed,
      isCancelled: cancelled,
      isAssetTransfer: assetTransfer,
    );
  }

  group('월 주기 감지', () {
    test('요구사항 예시: 매달 15일 17,000원 -> 월 정기결제', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 6, 15)),
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 7, 15)),
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 8, 15)),
      ];

      final RecurringCandidate? c = detector.analyzeBrand('Netflix', items);

      expect(c, isNotNull);
      expect(c!.cycle, RecurringCycle.monthly);
      expect(c.expectedAmount, 17000);
      expect(c.occurrenceCount, 3);
      expect(c.lastPaidAt, DateTime(2026, 8, 15));
      // 다음 예정은 같은 날짜를 유지한다.
      expect(c.nextExpectedAt, DateTime(2026, 9, 15));
    });

    test('며칠씩 밀려도 월 주기로 본다', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: 'ChatGPT', amount: 29000, at: DateTime(2026, 6, 3)),
        payment(brand: 'ChatGPT', amount: 29000, at: DateTime(2026, 7, 5)),
        payment(brand: 'ChatGPT', amount: 29000, at: DateTime(2026, 8, 4)),
      ];

      final RecurringCandidate? c = detector.analyzeBrand('ChatGPT', items);

      expect(c?.cycle, RecurringCycle.monthly);
    });

    test('금액이 조금 달라도(환율 변동) 허용한다', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: 'Apple', amount: 29000, at: DateTime(2026, 6, 10)),
        payment(brand: 'Apple', amount: 30500, at: DateTime(2026, 7, 10)),
        payment(brand: 'Apple', amount: 28500, at: DateTime(2026, 8, 10)),
      ];

      final RecurringCandidate? c = detector.analyzeBrand('Apple', items);

      expect(c, isNotNull);
      expect(c!.expectedAmount, 29000, reason: '중앙값을 대표 금액으로 쓴다');
    });
  });

  group('다른 주기', () {
    test('주 단위', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: '헬스장', amount: 20000, at: DateTime(2026, 8, 1)),
        payment(brand: '헬스장', amount: 20000, at: DateTime(2026, 8, 8)),
        payment(brand: '헬스장', amount: 20000, at: DateTime(2026, 8, 15)),
      ];

      expect(
        detector.analyzeBrand('헬스장', items)?.cycle,
        RecurringCycle.weekly,
      );
    });

    test('연 단위', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: '보험', amount: 300000, at: DateTime(2024, 3, 10)),
        payment(brand: '보험', amount: 300000, at: DateTime(2025, 3, 10)),
        payment(brand: '보험', amount: 300000, at: DateTime(2026, 3, 10)),
      ];

      expect(
        detector.analyzeBrand('보험', items)?.cycle,
        RecurringCycle.yearly,
      );
    });
  });

  group('감지하지 않아야 하는 경우', () {
    test('2회는 후보가 아니다 (우연일 수 있다)', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 7, 15)),
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 8, 15)),
      ];

      expect(detector.analyzeBrand('Netflix', items), isNull);
    });

    test('금액이 크게 다르면 후보가 아니다', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: '스타벅스', amount: 4500, at: DateTime(2026, 6, 15)),
        payment(brand: '스타벅스', amount: 17000, at: DateTime(2026, 7, 15)),
        payment(brand: '스타벅스', amount: 9000, at: DateTime(2026, 8, 15)),
      ];

      expect(detector.analyzeBrand('스타벅스', items), isNull);
    });

    test('간격이 불규칙하면 후보가 아니다', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: '식당', amount: 12000, at: DateTime(2026, 8, 1)),
        payment(brand: '식당', amount: 12000, at: DateTime(2026, 8, 3)),
        payment(brand: '식당', amount: 12000, at: DateTime(2026, 8, 20)),
      ];

      expect(detector.analyzeBrand('식당', items), isNull);
    });

    test('간격이 어떤 주기에도 맞지 않으면 후보가 아니다', () {
      // 45일 간격은 월도 분기도 아니다.
      final List<Transaction> items = <Transaction>[
        payment(brand: '무엇', amount: 10000, at: DateTime(2026, 1, 1)),
        payment(brand: '무엇', amount: 10000, at: DateTime(2026, 2, 15)),
        payment(brand: '무엇', amount: 10000, at: DateTime(2026, 4, 1)),
      ];

      expect(detector.analyzeBrand('무엇', items), isNull);
    });
  });

  group('detect (전체 거래에서 브랜드별로)', () {
    final List<Transaction> mixed = <Transaction>[
      // 정기결제 패턴
      payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 6, 15)),
      payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 7, 15)),
      payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 8, 15)),
      // 불규칙한 소비
      payment(brand: '스타벅스', amount: 6200, at: DateTime(2026, 8, 1)),
      payment(brand: '스타벅스', amount: 4500, at: DateTime(2026, 8, 3)),
    ];

    test('패턴이 있는 브랜드만 후보로 올린다', () {
      final List<RecurringCandidate> candidates = detector.detect(mixed);

      expect(candidates.length, 1);
      expect(candidates.first.brand, 'Netflix');
    });

    test('이미 규칙이 있는 브랜드는 건너뛴다', () {
      final List<RecurringCandidate> candidates = detector.detect(
        mixed,
        existingBrands: <String>{'Netflix'},
      );

      expect(candidates, isEmpty);
    });

    test('취소 거래는 제외한다', () {
      final List<Transaction> items = <Transaction>[
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 6, 15)),
        payment(brand: 'Netflix', amount: 17000, at: DateTime(2026, 7, 15)),
        payment(
          brand: 'Netflix',
          amount: -17000,
          at: DateTime(2026, 8, 15),
          cancelled: true,
        ),
      ];

      expect(detector.detect(items), isEmpty);
    });

    test('자산 이동은 제외한다', () {
      final List<Transaction> items = <Transaction>[
        payment(
          brand: '청년미래적금',
          amount: 500000,
          at: DateTime(2026, 6, 15),
          assetTransfer: true,
        ),
        payment(
          brand: '청년미래적금',
          amount: 500000,
          at: DateTime(2026, 7, 15),
          assetTransfer: true,
        ),
        payment(
          brand: '청년미래적금',
          amount: 500000,
          at: DateTime(2026, 8, 15),
          assetTransfer: true,
        ),
      ];

      expect(
        detector.detect(items),
        isEmpty,
        reason: '자산 이동은 소비가 아니므로 정기결제 후보로도 올리지 않는다',
      );
    });

    test('확신도 높은 후보가 먼저 온다', () {
      final List<Transaction> items = <Transaction>[
        // 정확히 규칙적
        payment(brand: 'A', amount: 10000, at: DateTime(2026, 5, 10)),
        payment(brand: 'A', amount: 10000, at: DateTime(2026, 6, 10)),
        payment(brand: 'A', amount: 10000, at: DateTime(2026, 7, 10)),
        payment(brand: 'A', amount: 10000, at: DateTime(2026, 8, 10)),
        // 며칠씩 흔들림
        payment(brand: 'B', amount: 20000, at: DateTime(2026, 6, 1)),
        payment(brand: 'B', amount: 20000, at: DateTime(2026, 7, 5)),
        payment(brand: 'B', amount: 20000, at: DateTime(2026, 8, 2)),
      ];

      final List<RecurringCandidate> candidates = detector.detect(items);

      expect(candidates.length, 2);
      expect(candidates.first.brand, 'A');
      expect(
        candidates.first.confidence,
        greaterThan(candidates.last.confidence),
      );
    });
  });

  group('RecurringCycle 다음 예정일', () {
    test('월말 결제가 짧은 달로 넘어갈 때 날짜를 잘라 준다', () {
      // 1월 31일 + 1개월 = 2월 28일 (3월 3일이 되면 안 된다)
      final DateTime next =
          RecurringCycle.monthly.nextAfter(DateTime(2026, 1, 31));

      expect(next.year, 2026);
      expect(next.month, 2);
      expect(next.day, 28);
    });

    test('12월 -> 다음 해 1월', () {
      final DateTime next =
          RecurringCycle.monthly.nextAfter(DateTime(2026, 12, 15));

      expect(next, DateTime(2027, 1, 15));
    });

    test('윤년 2월 29일 처리', () {
      final DateTime next =
          RecurringCycle.yearly.nextAfter(DateTime(2024, 2, 29));

      expect(next.year, 2025);
      expect(next.month, 2);
      expect(next.day, 28, reason: '2025년은 윤년이 아니다');
    });

    test('주/분기 주기', () {
      expect(
        RecurringCycle.weekly.nextAfter(DateTime(2026, 8, 10)),
        DateTime(2026, 8, 17),
      );
      expect(
        RecurringCycle.quarterly.nextAfter(DateTime(2026, 1, 15)),
        DateTime(2026, 4, 15),
      );
    });
  });

  group('RecurringRule 금액 매칭', () {
    const RecurringRule rule = RecurringRule(
      brand: 'Netflix',
      category: '주거/통신',
      subcategory: '구독료',
      cycle: RecurringCycle.monthly,
      expectedAmount: 17000,
    );

    test('예상 금액 근처는 같은 정기결제로 본다', () {
      expect(rule.matchesAmount(17000), isTrue);
      expect(rule.matchesAmount(18000), isTrue);
      expect(rule.matchesAmount(15500), isTrue);
    });

    test('크게 다르면 일회성 결제로 본다', () {
      expect(rule.matchesAmount(50000), isFalse);
      expect(rule.matchesAmount(5000), isFalse);
    });
  });
}
