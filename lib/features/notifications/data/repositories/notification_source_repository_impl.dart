import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/notification_source.dart';
import '../../domain/repositories/notification_source_repository.dart';
import '../datasources/notification_platform_channel.dart';

/// 수집 대상 앱 관리.
///
/// 원본은 SQLite(`notification_sources`)이고, 네이티브 SharedPreferences 는
/// 리스너가 빠르게 읽는 **캐시**다. 두 곳이 어긋나면 사용자가 끈 앱이 계속
/// 수집되므로, 저장할 때 항상 함께 갱신한다.
class NotificationSourceRepositoryImpl
    implements NotificationSourceRepository {
  NotificationSourceRepositoryImpl({
    required Database db,
    required NotificationPlatformChannel channel,
  })  : _db = db,
        _channel = channel;

  final Database _db;
  final NotificationPlatformChannel _channel;

  static const String _table = DbSchema.tableNotificationSources;

  @override
  Future<NotificationSourceConfig> load() async {
    // 1) 네이티브가 발견한 앱들을 DB 에 반영(새 앱은 기본 비허용으로 추가)
    final List<Map<String, Object?>> seen = await _channel.seenSources();
    if (seen.isNotEmpty) {
      final Batch batch = _db.batch();
      for (final Map<String, Object?> row in seen) {
        final String? packageName = row['packageName'] as String?;
        if (packageName == null || packageName.isEmpty) continue;

        batch.insert(
          _table,
          <String, Object?>{
            DbSchema.nsPackageName: packageName,
            DbSchema.nsDisplayName:
                (row['displayName'] as String?) ?? packageName,
            DbSchema.nsEnabled: 0,
            DbSchema.nsLastSeenAt: _int(row['lastSeenAt']),
            DbSchema.nsDetectedAt: _int(row['detectedAt']),
          },
          // 이미 있으면 사용자의 enabled 선택을 지우지 않는다.
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);

      // 이름과 마지막 감지 시각만 갱신한다(선택은 건드리지 않는다).
      for (final Map<String, Object?> row in seen) {
        final String? packageName = row['packageName'] as String?;
        if (packageName == null || packageName.isEmpty) continue;
        await _db.update(
          _table,
          <String, Object?>{
            DbSchema.nsDisplayName:
                (row['displayName'] as String?) ?? packageName,
            DbSchema.nsLastSeenAt: _int(row['lastSeenAt']),
          },
          where: '${DbSchema.nsPackageName} = ?',
          whereArgs: <Object?>[packageName],
        );
      }
    }

    // 2) 전체 목록을 최근 감지 순으로 읽는다.
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      orderBy: '${DbSchema.nsLastSeenAt} DESC, ${DbSchema.nsDisplayName} ASC',
    );

    final List<NotificationSource> sources = rows.map(_fromRow).toList();

    // 하나라도 허용된 것이 있으면 "설정을 마쳤다" 로 본다.
    final bool configured =
        sources.any((NotificationSource s) => s.enabled);

    return NotificationSourceConfig(
      sources: sources,
      isConfigured: configured,
    );
  }

  @override
  Future<void> setEnabled(Set<String> enabledPackages) async {
    final Batch batch = _db.batch();
    // 전체를 끄고 선택된 것만 켠다. 목록에 없는 패키지가 남아도 안전하다.
    batch.update(
      _table,
      <String, Object?>{DbSchema.nsEnabled: 0},
    );
    for (final String packageName in enabledPackages) {
      batch.update(
        _table,
        <String, Object?>{DbSchema.nsEnabled: 1},
        where: '${DbSchema.nsPackageName} = ?',
        whereArgs: <Object?>[packageName],
      );
    }
    await batch.commit(noResult: true);

    await _pushToNative(enabledPackages.toList());
    AppLogger.i('수집 대상 앱 ${enabledPackages.length}개 저장');
  }

  @override
  Future<void> toggle({
    required String packageName,
    required bool enabled,
  }) async {
    await _db.update(
      _table,
      <String, Object?>{DbSchema.nsEnabled: enabled ? 1 : 0},
      where: '${DbSchema.nsPackageName} = ?',
      whereArgs: <Object?>[packageName],
    );
    await syncToNative();
  }

  @override
  Future<void> syncToNative() async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      columns: <String>[DbSchema.nsPackageName],
      where: '${DbSchema.nsEnabled} = 1',
    );
    await _pushToNative(
      rows
          .map((Map<String, Object?> r) => r[DbSchema.nsPackageName] as String?)
          .whereType<String>()
          .toList(),
    );
  }

  Future<void> _pushToNative(List<String> packages) async {
    try {
      await _channel.setEnabledSources(packages);
    } on Object catch (e, stack) {
      // 네이티브 반영이 실패하면 필터가 옛 설정으로 동작한다.
      // 기록 자체는 계속되므로 앱을 멈추지는 않되, 반드시 남긴다.
      AppLogger.e('수집 대상 앱 네이티브 반영 실패', e, stack);
    }
  }

  static NotificationSource _fromRow(Map<String, Object?> row) {
    final String packageName =
        (row[DbSchema.nsPackageName] as String?) ?? '';
    return NotificationSource(
      packageName: packageName,
      displayName: (row[DbSchema.nsDisplayName] as String?) ?? packageName,
      enabled: ((row[DbSchema.nsEnabled] as int?) ?? 0) == 1,
      lastSeenAt: _toDate(row[DbSchema.nsLastSeenAt]),
      detectedAt: _toDate(row[DbSchema.nsDetectedAt]),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return DateTime.now().millisecondsSinceEpoch;
  }
}
