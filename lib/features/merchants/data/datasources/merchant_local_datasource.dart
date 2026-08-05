import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';

/// `merchants` / `brand_rules` 테이블에 대한 순수 SQLite 접근.
///
/// 도메인 타입을 모르게 하려면 Map 을 반환하는 편이 깔끔하지만,
/// 이 앱 규모에서는 DTO 변환까지 여기서 처리하는 편이 실용적이다.
class MerchantLocalDataSource {
  MerchantLocalDataSource(this._db);

  final Database _db;

  Future<Map<String, Object?>?> findByNormalizedName(String normalized) async {
    final List<Map<String, Object?>> rows = await _db.query(
      DbSchema.tableMerchants,
      where: '${DbSchema.mNormalizedName} = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      DbSchema.tableMerchants,
      where: '${DbSchema.mId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> findByBrand(String brand) {
    return _db.query(
      DbSchema.tableMerchants,
      where: '${DbSchema.mBrand} = ?',
      whereArgs: <Object?>[brand],
      orderBy: '${DbSchema.mHitCount} DESC',
    );
  }

  Future<int> insert(Map<String, Object?> row) {
    return _db.insert(
      DbSchema.tableMerchants,
      row,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> update(int id, Map<String, Object?> row) {
    return _db.update(
      DbSchema.tableMerchants,
      row,
      where: '${DbSchema.mId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> incrementHitCount(int id) {
    return _db.rawUpdate(
      'UPDATE ${DbSchema.tableMerchants} '
      'SET ${DbSchema.mHitCount} = ${DbSchema.mHitCount} + 1 '
      'WHERE ${DbSchema.mId} = ?',
      <Object?>[id],
    );
  }

  /// 브랜드 단위 분류 일괄 변경. 사용자 지정(user)으로 고정된 행은 건드리지 않는다.
  Future<int> updateClassificationForBrand({
    required String brand,
    required String category,
    required String subcategory,
    required String sourceCode,
    required int updatedAt,
    bool preserveUserOverrides = true,
  }) {
    final String userGuard = preserveUserOverrides
        ? " AND ${DbSchema.mSource} != 'user'"
        : '';
    return _db.rawUpdate(
      'UPDATE ${DbSchema.tableMerchants} SET '
      '${DbSchema.mCategory} = ?, '
      '${DbSchema.mSubcategory} = ?, '
      '${DbSchema.mSource} = ?, '
      '${DbSchema.mUpdatedAt} = ? '
      'WHERE ${DbSchema.mBrand} = ?$userGuard',
      <Object?>[category, subcategory, sourceCode, updatedAt, brand],
    );
  }

  Future<int> count() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM ${DbSchema.tableMerchants}'),
        ) ??
        0;
  }

  // ------------------------------------------------------------- brand_rules
  Future<List<Map<String, Object?>>> allBrandRules() {
    return _db.query(DbSchema.tableBrandRules);
  }

  Future<void> upsertBrandRule(Map<String, Object?> row) async {
    await _db.insert(
      DbSchema.tableBrandRules,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteBrandRule(String pattern) {
    return _db.delete(
      DbSchema.tableBrandRules,
      where: '${DbSchema.brPattern} = ?',
      whereArgs: <Object?>[pattern],
    );
  }

  /// 학습된 가맹점 전체(설정 화면 목록용).
  Future<List<Map<String, Object?>>> all({int? limit}) {
    return _db.query(
      DbSchema.tableMerchants,
      orderBy: '${DbSchema.mHitCount} DESC, ${DbSchema.mUpdatedAt} DESC',
      limit: limit,
    );
  }

}
