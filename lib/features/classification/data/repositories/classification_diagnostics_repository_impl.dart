import 'package:sqflite/sqflite.dart';

import '../../../../core/constants/classification_source.dart';
import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/classification_diagnostics.dart';
import '../../domain/repositories/classification_diagnostics_repository.dart';

/// 분류 파이프라인 계측.
///
/// **읽기 전용이 원칙이다.** 한 가지 예외가 [recordUnmapped] 인데, 매핑표를
/// 추측으로 늘리지 않으려면 실제로 무엇이 막히는지 남겨 두어야 한다.
class ClassificationDiagnosticsRepositoryImpl
    implements ClassificationDiagnosticsRepository {
  ClassificationDiagnosticsRepositoryImpl(this._db);

  final Database _db;

  static const String _unmapped = DbSchema.tableUnmappedPlaceCategories;

  @override
  Future<void> recordUnmapped({
    required String categoryName,
    String? sampleMerchant,
  }) async {
    final String key = categoryName.trim();
    if (key.isEmpty) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      // 같은 업종이 또 와도 행을 늘리지 않는다. 무엇이 **자주** 막히는지가
      // 알고 싶은 것이다.
      final int updated = await _db.rawUpdate(
        'UPDATE $_unmapped SET '
        '${DbSchema.upcHitCount} = ${DbSchema.upcHitCount} + 1, '
        '${DbSchema.upcLastSeenAt} = ? '
        'WHERE ${DbSchema.upcCategoryName} = ?',
        <Object?>[now, key],
      );
      if (updated > 0) return;

      await _db.insert(_unmapped, <String, Object?>{
        DbSchema.upcCategoryName: key,
        DbSchema.upcSampleMerchant: sampleMerchant,
        DbSchema.upcHitCount: 1,
        DbSchema.upcFirstSeenAt: now,
        DbSchema.upcLastSeenAt: now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } on Object catch (e, stack) {
      // 진단 기록 실패가 분류를 막아서는 안 된다.
      AppLogger.e('미매핑 업종 기록 실패: $key', e, stack);
    }
  }

  @override
  Future<List<UnmappedPlaceCategory>> findUnmapped({int limit = 50}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _unmapped,
      orderBy: '${DbSchema.upcHitCount} DESC, ${DbSchema.upcLastSeenAt} DESC',
      limit: limit,
    );
    return rows.map(_unmappedFromRow).toList();
  }

  @override
  Future<void> clearUnmapped() async {
    await _db.delete(_unmapped);
    AppLogger.i('미매핑 업종 기록을 비웠습니다.');
  }

  @override
  Future<ClassificationDiagnostics> load() async {
    final Map<String, int> bySource = <String, int>{
      for (final Map<String, Object?> row in await _db.rawQuery(
        'SELECT ${DbSchema.tClassificationSource} AS source, '
        'COUNT(*) AS cnt FROM ${DbSchema.tableTransactions} '
        'GROUP BY ${DbSchema.tClassificationSource}',
      ))
        (row['source'] as String?) ?? ClassificationSource.pending.code:
            (row['cnt'] as int?) ?? 0,
    };

    final Map<String, int> byAiStatus = <String, int>{
      for (final Map<String, Object?> row in await _db.rawQuery(
        'SELECT ${DbSchema.tAiStatus} AS status, COUNT(*) AS cnt '
        'FROM ${DbSchema.tableTransactions} GROUP BY ${DbSchema.tAiStatus}',
      ))
        (row['status'] as String?) ?? 'none': (row['cnt'] as int?) ?? 0,
    };

    final Map<String, int> byFound = <String, int>{
      for (final Map<String, Object?> row in await _db.rawQuery(
        'SELECT ${DbSchema.bmFound} AS found, COUNT(*) AS cnt '
        'FROM ${DbSchema.tableBrandMetadata} GROUP BY ${DbSchema.bmFound}',
      ))
        '${row['found']}': (row['cnt'] as int?) ?? 0,
    };

    return ClassificationDiagnostics(
      totalTransactions:
          bySource.values.fold<int>(0, (int sum, int n) => sum + n),
      bySource: bySource,
      needsReview: await _count(
        'SELECT COUNT(*) AS c FROM ${DbSchema.tableTransactions} '
        'WHERE ${DbSchema.tNeedsReview} = 1',
      ),
      aiPending: byAiStatus['pending'] ?? 0,
      aiCompleted: byAiStatus['completed'] ?? 0,
      aiFailed: byAiStatus['failed'] ?? 0,
      brandLookupsFound: byFound['1'] ?? 0,
      brandLookupsNotFound: byFound['0'] ?? 0,
      unmapped: await findUnmapped(),
    );
  }

  Future<int> _count(String sql) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(sql);
    return rows.isEmpty ? 0 : (rows.first['c'] as int?) ?? 0;
  }

  static UnmappedPlaceCategory _unmappedFromRow(Map<String, Object?> row) {
    final int? lastSeen = row[DbSchema.upcLastSeenAt] as int?;
    return UnmappedPlaceCategory(
      categoryName: (row[DbSchema.upcCategoryName] as String?) ?? '',
      hitCount: (row[DbSchema.upcHitCount] as int?) ?? 0,
      sampleMerchant: row[DbSchema.upcSampleMerchant] as String?,
      lastSeenAt: lastSeen == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSeen),
    );
  }
}
