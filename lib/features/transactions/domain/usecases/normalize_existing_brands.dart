import '../../../../core/logging/app_logger.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/domain/repositories/merchant_repository.dart';
import '../repositories/transaction_repository.dart';

/// 바뀔 브랜드 하나.
class BrandRename {
  const BrandRename({
    required this.merchantRaw,
    required this.from,
    required this.to,
    required this.count,
  });

  /// 원본 거래명. 정규화의 근거이며 **바뀌지 않는다.**
  final String merchantRaw;

  final String from;
  final String to;

  /// 영향받는 거래 수.
  final int count;

  @override
  String toString() => '$from -> $to ($count건, $merchantRaw)';
}

/// 재정규화 결과.
class BrandNormalizationResult {
  const BrandNormalizationResult({
    required this.renames,
    required this.transactionsUpdated,
  });

  const BrandNormalizationResult.empty()
      : renames = const <BrandRename>[],
        transactionsUpdated = 0;

  final List<BrandRename> renames;
  final int transactionsUpdated;

  bool get isEmpty => renames.isEmpty;

  /// 바뀔(또는 바뀐) 브랜드 종류 수.
  int get brandCount => renames.length;

  @override
  String toString() => '브랜드 $brandCount종 / 거래 $transactionsUpdated건';
}

/// 이미 저장된 거래의 브랜드를 지금의 사전 기준으로 다시 맞춘다.
///
/// 왜 필요한가:
///  - 직접 추가는 한동안 입력값을 그대로 브랜드로 썼다(`씨유` vs `CU`).
///  - 사전에 브랜드가 추가되면, 그 전에 쌓인 거래는 옛 표기로 남는다.
///
/// 두 경우 모두 같은 가게가 통계에서 여러 줄로 갈라진다.
///
/// **`merchant_raw` 는 절대 바꾸지 않는다.** 원본을 남겨 두기 때문에 사전이
/// 또 바뀌면 다시 돌려도 되고, 결과가 마음에 들지 않아도 근거가 남는다.
///
/// 매칭은 [MerchantRepository.lookup] 하나만 쓴다. 알림 수집·직접 추가와
/// 같은 경로다. 사용자가 직접 고쳐서 학습된 가맹점이 있으면 그 값이 이긴다 —
/// 사용자가 가르친 것을 일괄 작업이 되돌리면 안 된다.
class NormalizeExistingBrands {
  const NormalizeExistingBrands({
    required TransactionRepository transactions,
    required MerchantRepository merchants,
  })  : _transactions = transactions,
        _merchants = merchants;

  final TransactionRepository _transactions;
  final MerchantRepository _merchants;

  /// 무엇이 바뀔지만 계산한다. **저장하지 않는다.**
  ///
  /// 실제 가계부를 건드리는 작업이므로 사용자가 먼저 보고 결정해야 한다.
  Future<BrandNormalizationResult> preview() async {
    final List<BrandRename> renames = await _plan();
    return BrandNormalizationResult(
      renames: renames,
      transactionsUpdated: renames.fold(
        0,
        (int sum, BrandRename r) => sum + r.count,
      ),
    );
  }

  /// 계산하고 실제로 반영한다.
  Future<BrandNormalizationResult> call() async {
    final List<BrandRename> renames = await _plan();
    if (renames.isEmpty) {
      AppLogger.i('브랜드 재정규화: 바꿀 것이 없습니다.');
      return const BrandNormalizationResult.empty();
    }

    int updated = 0;
    final List<BrandRename> applied = <BrandRename>[];
    for (final BrandRename rename in renames) {
      // 하나가 실패해도 나머지는 계속한다. 부분 반영이 전부 실패보다 낫다.
      try {
        final int n = await _transactions.renameBrand(
          merchantRaw: rename.merchantRaw,
          from: rename.from,
          to: rename.to,
        );
        if (n > 0) {
          updated += n;
          applied.add(rename);
        }
      } on Object catch (e, stack) {
        AppLogger.e('브랜드 재정규화 실패: $rename', e, stack);
      }
    }

    AppLogger.i('브랜드 재정규화: 브랜드 ${applied.length}종 / 거래 $updated건');
    return BrandNormalizationResult(
      renames: applied,
      transactionsUpdated: updated,
    );
  }

  /// 바뀔 목록을 계산한다.
  Future<List<BrandRename>> _plan() async {
    final List<BrandSource> sources =
        await _transactions.distinctBrandSources();

    // 같은 원본 거래명은 결과가 같다. 사전 조회를 조합당 한 번으로 줄인다.
    final Map<String, String?> resolved = <String, String?>{};
    final List<BrandRename> renames = <BrandRename>[];

    for (final BrandSource source in sources) {
      if (!resolved.containsKey(source.merchantRaw)) {
        resolved[source.merchantRaw] = await _canonical(source.merchantRaw);
      }
      final String? canonical = resolved[source.merchantRaw];

      // 사전이 모르는 이름은 억지로 바꾸지 않는다.
      if (canonical == null || canonical == source.brand) continue;

      renames.add(
        BrandRename(
          merchantRaw: source.merchantRaw,
          from: source.brand,
          to: canonical,
          count: source.count,
        ),
      );
    }
    return renames;
  }

  /// 원본 거래명의 대표 브랜드. 모르면 null.
  Future<String?> _canonical(String merchantRaw) async {
    try {
      final MerchantLookup lookup = await _merchants.lookup(merchantRaw);
      return switch (lookup) {
        MerchantExactHit(:final Merchant merchant) => merchant.brand,
        MerchantBrandHit(:final BrandRule rule) => rule.brand,
        MerchantMiss() => null,
      };
    } on Object catch (e, stack) {
      AppLogger.e('브랜드 조회 실패: $merchantRaw', e, stack);
      return null;
    }
  }
}
