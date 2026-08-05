import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../domain/entities/brand_metadata.dart';
import '../../domain/repositories/brand_metadata_repository.dart';

class BrandMetadataRepositoryImpl implements BrandMetadataRepository {
  BrandMetadataRepositoryImpl(this._db);

  final Database _db;

  static const String _table = DbSchema.tableBrandMetadata;

  @override
  Future<BrandMetadata?> find(String brand) async {
    final String key = TextNormalizer.normalize(brand);
    if (key.isEmpty) return null;

    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.bmNormalizedBrand} = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<BrandMetadata> save(BrandMetadata metadata) async {
    // 사용자가 고친 값을 자동 조회 결과로 덮어쓰지 않는다.
    final BrandMetadata? existing = await find(metadata.brand);
    if (existing != null &&
        existing.userModified &&
        metadata.source != BrandMetadataSource.user) {
      AppLogger.d('사용자 지정 메타데이터 보존: ${metadata.brand}');
      return existing;
    }

    await _db.insert(
      _table,
      <String, Object?>{
        DbSchema.bmNormalizedBrand: metadata.normalizedBrand,
        DbSchema.bmBrand: metadata.brand,
        DbSchema.bmIndustry: metadata.industry,
        DbSchema.bmCategory: metadata.category,
        DbSchema.bmSubcategory: metadata.subcategory,
        DbSchema.bmSource: metadata.source.code,
        DbSchema.bmLookedUpAt: metadata.lookedUpAt.millisecondsSinceEpoch,
        DbSchema.bmUserModified: metadata.userModified ? 1 : 0,
        DbSchema.bmFound: metadata.found ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    AppLogger.i('브랜드 메타데이터 저장: ${metadata.brand} '
        '${metadata.found ? '${metadata.industry} -> '
            '${metadata.category}/${metadata.subcategory}' : '(못 찾음)'} '
        '[${metadata.source.code}]');
    return metadata;
  }

  @override
  Future<void> markUserModified({
    required String brand,
    required String category,
    required String subcategory,
  }) async {
    final String key = TextNormalizer.normalize(brand);
    if (key.isEmpty) return;

    final BrandMetadata? existing = await find(brand);
    await save(
      BrandMetadata(
        brand: brand,
        normalizedBrand: key,
        // 사용자가 확정했으니 업종 문자열은 기존 값을 유지한다.
        industry: existing?.industry,
        category: category,
        subcategory: subcategory,
        source: BrandMetadataSource.user,
        lookedUpAt: DateTime.now(),
        userModified: true,
      ),
    );
  }

  @override
  Future<List<BrandMetadata>> findAll({int limit = 200}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      orderBy: '${DbSchema.bmLookedUpAt} DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> clearLookupCache() async {
    // 사용자 지정은 남긴다. 그것까지 지우면 학습이 사라진다.
    final int removed = await _db.delete(
      _table,
      where: '${DbSchema.bmUserModified} = 0',
    );
    AppLogger.i('브랜드 조회 캐시 $removed건 삭제 (사용자 지정은 유지)');
    return removed;
  }

  @override
  Future<int> count() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM $_table'),
        ) ??
        0;
  }

  static BrandMetadata _fromRow(Map<String, Object?> row) {
    return BrandMetadata(
      id: row[DbSchema.bmId] as int?,
      brand: (row[DbSchema.bmBrand] as String?) ?? '',
      normalizedBrand: (row[DbSchema.bmNormalizedBrand] as String?) ?? '',
      industry: row[DbSchema.bmIndustry] as String?,
      category: row[DbSchema.bmCategory] as String?,
      subcategory: row[DbSchema.bmSubcategory] as String?,
      source: BrandMetadataSource.fromCode(row[DbSchema.bmSource] as String?),
      lookedUpAt: DateTime.fromMillisecondsSinceEpoch(
        (row[DbSchema.bmLookedUpAt] as int?) ?? 0,
      ),
      userModified: ((row[DbSchema.bmUserModified] as int?) ?? 0) == 1,
      found: ((row[DbSchema.bmFound] as int?) ?? 1) == 1,
    );
  }
}
