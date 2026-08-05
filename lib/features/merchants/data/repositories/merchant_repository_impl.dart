import '../../../../core/constants/classification_source.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../domain/entities/merchant.dart';
import '../../domain/repositories/merchant_repository.dart';
import '../datasources/merchant_local_datasource.dart';
import '../models/merchant_dto.dart';

class MerchantRepositoryImpl implements MerchantRepository {
  MerchantRepositoryImpl(this._local);

  final MerchantLocalDataSource _local;

  /// 브랜드 규칙 캐시. 패턴 길이 내림차순으로 정렬해 두어
  /// 항상 "가장 구체적인 패턴" 이 먼저 매칭된다.
  /// (`메가mgc커피` 가 `커피` 보다 먼저 검사되도록)
  List<BrandRule>? _brandCache;

  @override
  Future<MerchantLookup> lookup(String merchantRaw) async {
    final NormalizedText normalized =
        TextNormalizer.normalizeWithIndex(merchantRaw);
    if (normalized.value.isEmpty) {
      return MerchantMiss(merchantRaw);
    }

    // 1) 학습된 가맹점 완전일치 — 가장 빠르고 가장 정확하다.
    final Map<String, Object?>? exact =
        await _local.findByNormalizedName(normalized.value);
    if (exact != null) {
      return MerchantExactHit(MerchantDto.fromRow(exact));
    }

    // 2) 지점 접미사를 뗀 형태로 재조회 (`스타벅스강남점` -> `스타벅스강남`)
    final String stripped = TextNormalizer.stripBranchSuffix(normalized.value);
    if (stripped != normalized.value) {
      final Map<String, Object?>? row =
          await _local.findByNormalizedName(stripped);
      if (row != null) {
        return MerchantExactHit(MerchantDto.fromRow(row));
      }
    }

    // 3) 브랜드 사전 부분일치
    final BrandMatch? match = await _matchBrand(normalized);
    if (match != null) {
      return MerchantBrandHit(match.rule, branch: match.branch);
    }

    // 4) 처음 보는 가맹점 → LLM 대상
    return MerchantMiss(merchantRaw);
  }

  /// 정규화된 가맹점명 안에서 브랜드 패턴을 찾는다.
  Future<BrandMatch?> _matchBrand(NormalizedText normalized) async {
    final List<BrandRule> rules = await _loadBrandRules();

    for (final BrandRule rule in rules) {
      if (rule.pattern.isEmpty) continue;

      // `cu`, `kt` 처럼 짧은 패턴은 완전일치만 허용(오탐 방지).
      if (rule.requiresExactMatch) {
        if (normalized.value == rule.pattern) {
          return BrandMatch(rule, null);
        }
        continue;
      }

      final int index = normalized.value.indexOf(rule.pattern);
      if (index < 0) continue;

      final int end = index + rule.pattern.length;
      final String branch = normalized.rawTailFrom(end);
      return BrandMatch(rule, branch.isEmpty ? null : branch);
    }
    return null;
  }

  Future<List<BrandRule>> _loadBrandRules() async {
    final List<BrandRule>? cached = _brandCache;
    if (cached != null) return cached;

    final List<BrandRule> rules = (await _local.allBrandRules())
        .map(BrandRuleDto.fromRow)
        .toList();

    // 우선순위 내림차순 -> 패턴 길이 내림차순
    rules.sort((BrandRule a, BrandRule b) {
      final int byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return b.pattern.length.compareTo(a.pattern.length);
    });

    _brandCache = rules;
    return rules;
  }

  @override
  Future<Merchant> save(Merchant merchant) async {
    final DateTime now = DateTime.now();
    final Map<String, Object?>? existingRow =
        await _local.findByNormalizedName(merchant.normalizedName);

    if (existingRow == null) {
      final int id = await _local.insert(
        MerchantDto.toRow(merchant, now: now),
      );
      AppLogger.i('가맹점 학습: ${merchant.brand} '
          '(${merchant.category}/${merchant.subcategory}, ${merchant.source.code})');
      return merchant.copyWith(id: id);
    }

    final Merchant existing = MerchantDto.fromRow(existingRow);

    // 더 약한 출처가 강한 출처를 덮어쓰지 못하게 한다.
    // (LLM 결과가 사용자 수정을 되돌리는 사고 방지)
    if (!merchant.source.canOverride(existing.source)) {
      AppLogger.d('가맹점 갱신 생략: ${existing.brand} '
          '(${existing.source.code} > ${merchant.source.code})');
      return existing;
    }

    final Merchant merged = merchant.copyWith(
      id: existing.id,
      hitCount: existing.hitCount,
    );
    await _local.update(
      existing.id!,
      MerchantDto.toRow(merged, now: now, includeCreatedAt: false),
    );
    AppLogger.i('가맹점 갱신: ${merged.brand} '
        '-> ${merged.category}/${merged.subcategory} (${merged.source.code})');
    return merged;
  }

  @override
  Future<void> registerHit(int merchantId) => _local.incrementHitCount(merchantId);

  @override
  Future<Merchant?> findById(int id) async {
    final Map<String, Object?>? row = await _local.findById(id);
    return row == null ? null : MerchantDto.fromRow(row);
  }

  @override
  Future<List<Merchant>> findByBrand(String brand) async {
    final List<Map<String, Object?>> rows = await _local.findByBrand(brand);
    return rows.map(MerchantDto.fromRow).toList();
  }

  @override
  Future<int> updateClassificationForBrand({
    required String brand,
    required String category,
    required String subcategory,
    required ClassificationSource source,
  }) async {
    final int updated = await _local.updateClassificationForBrand(
      brand: brand,
      category: category,
      subcategory: subcategory,
      sourceCode: source.code,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      // 사용자가 직접 지정한 것이면 기존 user 지정도 함께 갱신한다.
      preserveUserOverrides: !source.isUserDefined,
    );
    AppLogger.i('브랜드 "$brand" 분류 $updated건 갱신 -> $category/$subcategory');
    return updated;
  }

  @override
  Future<void> upsertBrandRule(BrandRule rule) async {
    await _local.upsertBrandRule(BrandRuleDto.toRow(rule));
    await invalidateCache();
  }

  @override
  Future<List<BrandRule>> allBrandRules() => _loadBrandRules();

  @override
  Future<int> learnedCount() => _local.count();

  @override
  Future<void> invalidateCache() async {
    _brandCache = null;
  }
}

/// 브랜드 부분일치 결과(내부용).
class BrandMatch {
  const BrandMatch(this.rule, this.branch);

  final BrandRule rule;
  final String? branch;
}
