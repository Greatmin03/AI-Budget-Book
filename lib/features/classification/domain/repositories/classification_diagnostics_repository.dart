import '../entities/classification_diagnostics.dart';

/// 분류 파이프라인이 실제로 얼마나 일하고 있는지 재는 곳.
///
/// 감이 아니라 숫자로 봐야 어디를 고칠지 알 수 있다.
abstract interface class ClassificationDiagnosticsRepository {
  /// 우리 체계로 옮기지 못한 카카오 업종을 남긴다.
  ///
  /// 같은 업종은 행을 늘리지 않고 횟수만 올린다.
  /// **실패해도 예외를 던지지 않는다** — 진단이 분류를 막으면 안 된다.
  Future<void> recordUnmapped({
    required String categoryName,
    String? sampleMerchant,
  });

  /// 자주 막힌 순서대로.
  Future<List<UnmappedPlaceCategory>> findUnmapped({int limit = 50});

  Future<void> clearUnmapped();

  Future<ClassificationDiagnostics> load();
}
