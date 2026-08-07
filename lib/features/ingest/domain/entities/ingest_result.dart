import '../../../transactions/domain/entities/transaction.dart';

/// 알림 한 건을 처리한 결과.
sealed class IngestResult {
  const IngestResult();

  String get summary;
}

/// 가계부에 새로 기록되었다.
/// 다른 앱이 이미 알린 결제였다. **거래를 새로 만들지 않고 정보만 얹었다.**
///
/// 중복(`IngestDuplicate`)과 구분한다. 중복은 버린 것이고, 병합은 값을
/// 더한 것이다 — 사용자에게 보여 줄 말도 달라야 한다.
class IngestMerged extends IngestResult {
  const IngestMerged({
    required this.transaction,
    required this.sourcePackage,
  });

  final Transaction transaction;

  /// 정보를 더해 준 앱.
  final String sourcePackage;

  @override
  String get summary => '병합: ${transaction.displayName} '
      '${transaction.amount}원 (알림 ${transaction.mergedSources.length}개)';
}

class IngestSaved extends IngestResult {
  const IngestSaved(this.transaction);

  final Transaction transaction;

  @override
  String get summary => '저장: ${transaction.displayName} '
      '${transaction.amount}원 (${transaction.category})';
}

/// 이미 저장된 알림이었다(중복 수신).
class IngestDuplicate extends IngestResult {
  const IngestDuplicate();

  @override
  String get summary => '중복 알림 무시';
}

/// 입금 알림이었다. 지출로 기록하지 않고 정산 후보로 저장했다.
class IngestDepositRecorded extends IngestResult {
  const IngestDepositRecorded({
    required this.counterparty,
    required this.amount,
  });

  final String counterparty;
  final int amount;

  @override
  String get summary => '입금 $counterparty +$amount원 (정산 후보)';
}

/// 결제 알림이 아니었다.
class IngestIgnored extends IngestResult {
  const IngestIgnored(this.reason);

  final String reason;

  @override
  String get summary => '무시: $reason';
}

/// 결제 알림처럼 보였지만 추출에 실패했다(보관함에 저장됨).
class IngestFailed extends IngestResult {
  const IngestFailed(this.reason);

  final String reason;

  @override
  String get summary => '파싱 실패: $reason';
}
