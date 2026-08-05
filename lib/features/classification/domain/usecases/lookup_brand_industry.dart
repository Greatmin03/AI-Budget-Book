import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/text_normalizer.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../../data/datasources/place_api_datasource.dart';
import '../entities/brand_metadata.dart';
import '../repositories/brand_metadata_repository.dart';
import '../services/place_category_mapper.dart';

/// 장소 API 로 브랜드 업종을 조회한다. **브랜드당 최대 1회.**
///
/// ## 호출 최소화가 이 클래스의 존재 이유다
/// 1. 캐시에 있으면 즉시 반환 (성공/실패 모두 캐시된다)
/// 2. 키가 없거나 한도 초과 상태면 호출하지 않는다
/// 3. 조회 결과는 성공이든 실패든 항상 저장한다
///
/// 3번이 없으면 업종을 못 찾는 브랜드를 결제마다 다시 조회해서
/// 무료 할당량이 순식간에 사라진다.
///
/// ## 비용 안전장치
/// 429(한도 초과)를 받으면 [_throttleDuration] 동안 API 를 자동으로 쉬게 한다.
/// 그 동안에도 앱은 정상 동작한다(LLM 또는 사용자 선택으로 넘어간다).
class LookupBrandIndustry {
  const LookupBrandIndustry({
    required BrandMetadataRepository metadata,
    required PlaceApiDataSource placeApi,
    required SettingsRepository settings,
    PlaceCategoryMapper mapper = const PlaceCategoryMapper(),
  })  : _metadata = metadata,
        _placeApi = placeApi,
        _settings = settings,
        _mapper = mapper;

  final BrandMetadataRepository _metadata;
  final PlaceApiDataSource _placeApi;
  final SettingsRepository _settings;
  final PlaceCategoryMapper _mapper;

  /// 한도 초과 시 쉬는 시간. 하루면 다음 날 할당량이 복구된다.
  static const Duration _throttleDuration = Duration(hours: 24);

  /// 브랜드의 업종을 알아낸다.
  ///
  /// 절대 예외를 던지지 않는다. 실패하면 null 을 반환하고
  /// 호출자는 다음 단계(LLM / 사용자 선택)로 넘어간다.
  Future<BrandMetadata?> call(String brand) async {
    final String trimmed = brand.trim();
    if (trimmed.isEmpty) return null;

    // 1) 캐시 우선. 못 찾았던 기록도 캐시이므로 여기서 끝난다.
    final BrandMetadata? cached = await _metadata.find(trimmed);
    if (cached != null) {
      AppLogger.d('브랜드 메타데이터 캐시 히트: $trimmed '
          '(${cached.found ? '${cached.category}/${cached.subcategory}' : '못 찾음'})');
      return cached.isUsable ? cached : null;
    }

    // 2) 호출 가능 상태인지 확인
    final AppSettings settings = _settings.current;
    if (!settings.canUsePlaceApi) {
      if (settings.isPlaceApiThrottled) {
        AppLogger.d('장소 API 휴식 중 (한도 초과) → 조회 생략: $trimmed');
      }
      return null;
    }

    // 3) 조회
    final PlaceLookupResult result = await _placeApi.lookup(
      restApiKey: settings.placeApiKey,
      brand: trimmed,
    );

    // 한도 초과 → 자동으로 API 사용 중단. 캐시에는 아무것도 남기지 않는다
    // (일시적 상태이므로 나중에 다시 조회할 수 있어야 한다).
    if (result.isQuotaExceeded) {
      await _throttle();
      return null;
    }

    // 일시적 실패(네트워크 등)도 캐시하지 않는다.
    if (result.status == PlaceLookupStatus.failed) {
      AppLogger.w('장소 조회 실패($trimmed): ${result.message}');
      return null;
    }

    final String normalized = TextNormalizer.normalize(trimmed);

    // 결과가 없음 → **못 찾았다는 사실을 캐시한다.** 재조회 방지.
    if (!result.isSuccess) {
      await _metadata.save(
        BrandMetadata.notFound(
          brand: trimmed,
          normalizedBrand: normalized,
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime.now(),
        ),
      );
      return null;
    }

    // 후보들의 업종을 비교해 다수결로 정한다.
    //
    // 한 건만 보고 확정하면 이름이 흔한 가게에서 엉뚱한 분류가 그대로
    // 굳는다. 자동 분류는 사용자에게 묻지 않으므로 애매하면 넘기는 편이 낫다.
    final PlaceConsensus consensus =
        _mapper.resolveConsensus(result.categoryNames);

    // 판단하지 못한 경우도 캐시한다.
    //
    // 다시 조회해도 같은 후보가 오므로 재조회는 할당량만 쓴다.
    // 캐시에 남으면 이후 이 브랜드는 AI 대기열(또는 사용자 선택)로 간다.
    if (!consensus.isConfident) {
      AppLogger.i('장소 후보로 판단하지 못함: $trimmed — $consensus');
      await _metadata.save(
        BrandMetadata(
          brand: trimmed,
          normalizedBrand: normalized,
          industry: consensus.industry,
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime.now(),
          found: false,
        ),
      );
      return null;
    }

    AppLogger.i('장소 후보 다수결: $trimmed — $consensus');

    return _metadata.save(
      BrandMetadata(
        brand: trimmed,
        normalizedBrand: normalized,
        industry: consensus.industry,
        category: consensus.pair!.category,
        subcategory: consensus.pair!.subcategory,
        source: BrandMetadataSource.kakao,
        lookedUpAt: DateTime.now(),
      ),
    );
  }

  /// 한도 초과 상태를 저장해 이후 호출을 멈춘다.
  Future<void> _throttle() async {
    final DateTime until = DateTime.now().add(_throttleDuration);
    await _settings.save(
      _settings.current.copyWith(
        placeApiBlockedUntilMillis: until.millisecondsSinceEpoch,
      ),
    );
    AppLogger.w('장소 API 호출 한도 초과. '
        '${until.toIso8601String()} 까지 자동 중단합니다. '
        '(앱은 계속 정상 동작합니다)');
  }

  /// 사용자가 설정에서 키를 확인할 때 쓴다.
  Future<PlaceLookupResult> testKey(String key) => _placeApi.testKey(key);
}
