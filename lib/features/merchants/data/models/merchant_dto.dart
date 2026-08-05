import '../../../../core/constants/classification_source.dart';
import '../../../../core/database/db_schema.dart';
import '../../domain/entities/merchant.dart';

/// `merchants` 테이블 행 <-> [Merchant] 변환.
class MerchantDto {
  const MerchantDto._();

  static Merchant fromRow(Map<String, Object?> row) {
    return Merchant(
      id: row[DbSchema.mId] as int?,
      brand: (row[DbSchema.mBrand] as String?) ?? '',
      merchantName: (row[DbSchema.mMerchantName] as String?) ?? '',
      normalizedName: (row[DbSchema.mNormalizedName] as String?) ?? '',
      branch: row[DbSchema.mBranch] as String?,
      category: (row[DbSchema.mCategory] as String?) ?? '기타',
      subcategory: (row[DbSchema.mSubcategory] as String?) ?? '기타',
      source: ClassificationSource.fromCode(row[DbSchema.mSource] as String?),
      confidence: _toDouble(row[DbSchema.mConfidence]),
      hitCount: (row[DbSchema.mHitCount] as int?) ?? 0,
      createdAt: _toDate(row[DbSchema.mCreatedAt]),
      updatedAt: _toDate(row[DbSchema.mUpdatedAt]),
    );
  }

  /// insert/update 용 행. id 는 포함하지 않는다.
  static Map<String, Object?> toRow(
    Merchant merchant, {
    required DateTime now,
    bool includeCreatedAt = true,
  }) {
    return <String, Object?>{
      DbSchema.mBrand: merchant.brand,
      DbSchema.mMerchantName: merchant.merchantName,
      DbSchema.mNormalizedName: merchant.normalizedName,
      DbSchema.mBranch: merchant.branch,
      DbSchema.mCategory: merchant.category,
      DbSchema.mSubcategory: merchant.subcategory,
      DbSchema.mSource: merchant.source.code,
      DbSchema.mConfidence: merchant.confidence,
      DbSchema.mHitCount: merchant.hitCount,
      if (includeCreatedAt)
        DbSchema.mCreatedAt:
            (merchant.createdAt ?? now).millisecondsSinceEpoch,
      DbSchema.mUpdatedAt: now.millisecondsSinceEpoch,
    };
  }

  static double _toDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return 0;
  }

  static DateTime? _toDate(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}

/// `brand_rules` 테이블 행 <-> [BrandRule] 변환.
class BrandRuleDto {
  const BrandRuleDto._();

  static BrandRule fromRow(Map<String, Object?> row) {
    return BrandRule(
      id: row[DbSchema.brId] as int?,
      pattern: (row[DbSchema.brPattern] as String?) ?? '',
      brand: (row[DbSchema.brBrand] as String?) ?? '',
      category: (row[DbSchema.brCategory] as String?) ?? '기타',
      subcategory: (row[DbSchema.brSubcategory] as String?) ?? '기타',
      priority: (row[DbSchema.brPriority] as int?) ?? 0,
      source: ClassificationSource.fromCode(row[DbSchema.brSource] as String?),
    );
  }

  static Map<String, Object?> toRow(BrandRule rule) => <String, Object?>{
        DbSchema.brPattern: rule.pattern,
        DbSchema.brBrand: rule.brand,
        DbSchema.brCategory: rule.category,
        DbSchema.brSubcategory: rule.subcategory,
        DbSchema.brPriority: rule.priority,
        DbSchema.brSource: rule.source.code,
      };
}
