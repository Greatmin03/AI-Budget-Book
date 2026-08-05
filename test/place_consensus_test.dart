import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/features/classification/data/datasources/place_api_datasource.dart';
import 'package:budget_book/features/classification/domain/entities/brand_metadata.dart';
import 'package:budget_book/features/classification/domain/repositories/brand_metadata_repository.dart';
import 'package:budget_book/features/classification/domain/services/place_category_mapper.dart';
import 'package:budget_book/features/classification/domain/usecases/lookup_brand_industry.dart';
import 'package:budget_book/features/settings/domain/entities/app_settings.dart';
import 'package:budget_book/features/settings/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 장소 검색 후보 다수결.
///
/// 후보를 5개 받아 업종이 일치하는지 본다. **API 호출은 여전히 1회**다.
///
/// 한 건만 보고 확정하면 이름이 흔한 가게(`본가`, `할머니집`)에서 엉뚱한
/// 분류가 그대로 굳는다. 자동 분류는 사용자에게 묻지 않고 확정되므로,
/// 애매하면 AI 대기열로 넘기는 편이 낫다.
class _FakeMetadataRepository implements BrandMetadataRepository {
  final Map<String, BrandMetadata> store = <String, BrandMetadata>{};

  @override
  Future<BrandMetadata?> find(String brand) async => store[_key(brand)];

  @override
  Future<BrandMetadata> save(BrandMetadata metadata) async {
    store[metadata.normalizedBrand] = metadata;
    return metadata;
  }

  @override
  Future<void> markUserModified({
    required String brand,
    required String category,
    required String subcategory,
  }) async {}

  @override
  Future<List<BrandMetadata>> findAll({int limit = 200}) async =>
      store.values.toList();

  @override
  Future<int> clearLookupCache() async => 0;

  @override
  Future<int> count() async => store.length;

  static String _key(String brand) =>
      brand.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);
  AppSettings _settings;

  @override
  AppSettings get current => _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

void main() {
  const PlaceCategoryMapper mapper = PlaceCategoryMapper();

  group('다수결 판단', () {
    test('후보 0개 — 판단 불가', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[]);
      expect(c.isConfident, isFalse);
      expect(c.total, 0);
    });

    test('후보 1개 — 그대로 자동 분류', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 한식 > 국수',
      ]);
      expect(c.isConfident, isTrue);
      expect(c.pair, const CategoryPair('식비', '한식'));
      expect(c.agreeing, 1);
    });

    test('모두 같은 업종 — 만장일치', () {
      // 세 문자열이 모두 식비/한식으로 매핑된다.
      // (`육류,고기` 는 더 구체적인 규칙이 있어 고기/구이로 가므로 쓰지 않는다)
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 한식 > 국수',
        '음식점 > 한식 > 샤브샤브',
        '음식점 > 한식',
      ]);
      expect(c.isConfident, isTrue);
      expect(c.pair, const CategoryPair('식비', '한식'));
      expect(c.isUnanimous, isTrue);
      expect(c.agreeing, 3);
    });

    test('요구사항 예시: 한식 한식 한식 중식 → 한식', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 한식',
        '음식점 > 한식 > 국수',
        '음식점 > 한식 > 샤브샤브',
        '음식점 > 중식 > 중국요리',
      ]);
      expect(c.isConfident, isTrue);
      expect(c.pair, const CategoryPair('식비', '한식'));
      expect(c.agreeing, 3);
      expect(c.isUnanimous, isFalse, reason: '중식 1건이 있어 만장일치는 아니다');
    });

    test('요구사항 예시: 카페 병원 약국 세탁소 → 판단 불가', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 카페 > 커피전문점',
        '의료,건강 > 병원',
        '의료,건강 > 약국',
        '가정,생활 > 세탁',
      ]);
      expect(c.isConfident, isFalse, reason: '전부 다르면 확정하면 안 된다');
      expect(c.total, 4);
    });

    test('2:2 동점 — 판단 불가', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 한식',
        '음식점 > 한식 > 국수',
        '음식점 > 중식',
        '음식점 > 중식 > 중국요리',
      ]);
      expect(c.isConfident, isFalse, reason: '동점은 다수가 아니다');
    });

    test('2:1:1 — 최다 득표로 결정', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 카페 > 커피전문점',
        '음식점 > 카페',
        '의료,건강 > 병원',
        '가정,생활 > 세탁',
      ]);
      expect(c.isConfident, isTrue);
      expect(c.pair, const CategoryPair('식비', '카페'));
      expect(c.agreeing, 2);
    });

    test('우리 체계로 옮길 수 없는 후보는 투표에서 빠진다', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '알수없음 > 이상한업종',
        '음식점 > 한식',
        '음식점 > 한식 > 국수',
      ]);
      expect(c.isConfident, isTrue);
      expect(c.pair, const CategoryPair('식비', '한식'));
      expect(c.mappable, 2, reason: '옮길 수 있었던 후보만 센다');
      expect(c.total, 3);
    });

    test('전부 옮길 수 없으면 판단 불가', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '알수없음 > 이상한업종',
        '모르는분류 > 다른것',
      ]);
      expect(c.isConfident, isFalse);
      // 업종 문자열은 남겨 두면 나중에 참고가 된다.
      expect(c.industry, isNotNull);
    });

    test('반환하는 분류는 항상 앱 체계 안에 있다', () {
      final PlaceConsensus c = mapper.resolveConsensus(<String>[
        '음식점 > 중식 > 중국요리',
        '음식점 > 중식',
      ]);
      expect(
        CategoryTaxonomy.isValidPair(c.pair!.category, c.pair!.subcategory),
        isTrue,
      );
    });
  });

  group('API 호출', () {
    /// 호출 횟수와 요청 파라미터를 기록하는 가짜 서버.
    ({PlaceApiDataSource api, List<Uri> requests}) build(String body) {
      final List<Uri> requests = <Uri>[];
      return (
        api: PlaceApiDataSource(
          client: MockClient((http.Request request) async {
            requests.add(request.url);
            return http.Response(
              body,
              200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }),
        ),
        requests: requests,
      );
    }

    test('후보를 5개 요청하지만 호출은 1회다', () async {
      final ({PlaceApiDataSource api, List<Uri> requests}) fake = build(
        '{"documents":['
        '{"place_name":"행복반점","category_name":"음식점 > 중식 > 중국요리"},'
        '{"place_name":"행복반점 2호점","category_name":"음식점 > 중식"}'
        ']}',
      );

      final PlaceLookupResult result = await fake.api.lookup(
        restApiKey: 'k',
        brand: '행복반점',
      );

      expect(fake.requests.length, 1, reason: '호출 횟수는 늘어나지 않는다');
      expect(fake.requests.single.queryParameters['size'], '5');
      expect(fake.requests.single.queryParameters['query'], '행복반점');
      expect(result.candidates.length, 2);
      expect(result.categoryNames, hasLength(2));
    });

    test('업종이 없는 문서는 후보에서 제외한다', () async {
      final ({PlaceApiDataSource api, List<Uri> requests}) fake = build(
        '{"documents":['
        '{"place_name":"이름만 있음"},'
        '{"place_name":"정상","category_name":"음식점 > 한식"}'
        ']}',
      );

      final PlaceLookupResult result = await fake.api.lookup(
        restApiKey: 'k',
        brand: '테스트',
      );

      expect(result.candidates.length, 1);
      expect(result.categoryName, '음식점 > 한식');
    });

    test('업종 있는 문서가 하나도 없으면 결과 없음', () async {
      final ({PlaceApiDataSource api, List<Uri> requests}) fake = build(
        '{"documents":[{"place_name":"이름만"}]}',
      );

      final PlaceLookupResult result = await fake.api.lookup(
        restApiKey: 'k',
        brand: '테스트',
      );

      expect(result.status, PlaceLookupStatus.notFound);
    });
  });

  group('조회 → 캐시 연동', () {
    LookupBrandIndustry build({
      required String body,
      required _FakeMetadataRepository metadata,
      List<Uri>? requests,
    }) {
      return LookupBrandIndustry(
        metadata: metadata,
        placeApi: PlaceApiDataSource(
          client: MockClient((http.Request request) async {
            requests?.add(request.url);
            return http.Response(
              body,
              200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }),
        ),
        settings: _FakeSettingsRepository(
          const AppSettings(placeApiKey: 'k'),
        ),
      );
    }

    test('다수결이 되면 자동 분류하고 캐시한다', () async {
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = build(
        metadata: metadata,
        body: '{"documents":['
            '{"place_name":"행복반점","category_name":"음식점 > 중식 > 중국요리"},'
            '{"place_name":"행복반점 2호점","category_name":"음식점 > 중식"},'
            '{"place_name":"행복반점 별관","category_name":"음식점 > 중식"}'
            ']}',
      );

      final BrandMetadata? result = await lookup('행복반점');

      expect(result, isNotNull);
      expect(result!.category, '식비');
      expect(result.subcategory, '중식');
      expect(result.found, isTrue);
    });

    test('업종이 갈리면 AI 대기열로 넘기고, 그 사실을 캐시한다', () async {
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final List<Uri> requests = <Uri>[];
      final LookupBrandIndustry lookup = build(
        metadata: metadata,
        requests: requests,
        body: '{"documents":['
            '{"place_name":"본가","category_name":"음식점 > 카페 > 커피전문점"},'
            '{"place_name":"본가","category_name":"의료,건강 > 병원"},'
            '{"place_name":"본가","category_name":"의료,건강 > 약국"},'
            '{"place_name":"본가","category_name":"가정,생활 > 세탁"}'
            ']}',
      );

      expect(await lookup('본가'), isNull, reason: '판단 못 했으므로 대기열로');

      // 두 번째 호출은 캐시에서 끝난다. 다시 물어도 같은 답이 오므로
      // 재조회는 할당량만 쓴다.
      expect(await lookup('본가'), isNull);
      expect(requests.length, 1, reason: '판단 실패도 캐시해 재조회를 막는다');

      final BrandMetadata cached = metadata.store.values.single;
      expect(cached.found, isFalse);
      expect(cached.isUsable, isFalse);
    });

    test('만장일치는 한 건짜리 결과보다 강한 신호다', () {
      // 문서화된 성질을 고정한다: agreeing/mappable 로 신뢰도를 알 수 있다.
      final PlaceConsensus single =
          mapper.resolveConsensus(<String>['음식점 > 한식']);
      final PlaceConsensus unanimous = mapper.resolveConsensus(<String>[
        '음식점 > 한식',
        '음식점 > 한식 > 국수',
        '음식점 > 한식 > 샤브샤브',
      ]);

      expect(single.isUnanimous, isFalse, reason: '비교할 대상이 없었다');
      expect(unanimous.isUnanimous, isTrue);
      expect(unanimous.agreeing, greaterThan(single.agreeing));
    });
  });
}
