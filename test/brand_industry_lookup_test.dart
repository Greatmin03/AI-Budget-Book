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

/// 메모리 캐시. 실제 구현과 같은 규칙(사용자 지정 보존)을 지킨다.
class _FakeMetadataRepository implements BrandMetadataRepository {
  final Map<String, BrandMetadata> store = <String, BrandMetadata>{};
  int saveCount = 0;

  @override
  Future<BrandMetadata?> find(String brand) async =>
      store[_key(brand)];

  @override
  Future<BrandMetadata> save(BrandMetadata metadata) async {
    saveCount++;
    final BrandMetadata? existing = store[metadata.normalizedBrand];
    if (existing != null &&
        existing.userModified &&
        metadata.source != BrandMetadataSource.user) {
      return existing;
    }
    store[metadata.normalizedBrand] = metadata;
    return metadata;
  }

  @override
  Future<void> markUserModified({
    required String brand,
    required String category,
    required String subcategory,
  }) async {
    await save(
      BrandMetadata(
        brand: brand,
        normalizedBrand: _key(brand),
        category: category,
        subcategory: subcategory,
        source: BrandMetadataSource.user,
        lookedUpAt: DateTime(2026),
        userModified: true,
      ),
    );
  }

  @override
  Future<List<BrandMetadata>> findAll({int limit = 200}) async =>
      store.values.toList();

  @override
  Future<int> clearLookupCache() async {
    final int before = store.length;
    store.removeWhere((_, BrandMetadata m) => !m.userModified);
    return before - store.length;
  }

  @override
  Future<int> count() async => store.length;

  /// TextNormalizer 와 같은 방향(소문자 + 공백 제거)만 흉내 내면 충분하다.
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

/// 호출 횟수를 세는 가짜 카카오 서버.
class _FakeServer {
  _FakeServer({required this.body, this.statusCode = 200});

  final String body;
  final int statusCode;
  int callCount = 0;

  PlaceApiDataSource build() {
    return PlaceApiDataSource(
      client: MockClient((http.Request request) async {
        callCount++;
        return http.Response(
          body,
          statusCode,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
  }
}

String _documents(String categoryName, {String placeName = '테스트'}) =>
    '{"documents":[{"place_name":"$placeName",'
    '"category_name":"$categoryName"}],"meta":{"total_count":1}}';

const AppSettings _withKey = AppSettings(placeApiKey: 'test-key');

void main() {
  group('PlaceCategoryMapper', () {
    const PlaceCategoryMapper mapper = PlaceCategoryMapper();

    test('가장 구체적인 단계부터 매칭한다', () {
      // 왼쪽부터 보면 "음식점 -> 식비/기타" 로 정보가 사라진다.
      expect(
        mapper.map('음식점 > 카페 > 커피전문점 > 스타벅스'),
        const CategoryPair('식비', '카페'),
      );
      expect(
        mapper.map('음식점 > 중식 > 중국요리'),
        const CategoryPair('식비', '중식'),
      );
    });

    test('편의점/마트를 생활로 옮긴다', () {
      expect(
        mapper.map('가정,생활 > 편의점 > GS25'),
        const CategoryPair('생활', '편의점'),
      );
    });

    test('구체적인 단계를 못 찾으면 상위 단계로 내려간다', () {
      // "듣도 보도 못한 업종" 은 규칙에 없으므로 상위 "음식점" 으로 맞춘다.
      expect(
        mapper.map('음식점 > 완전히새로운업종'),
        const CategoryPair('식비', '기타'),
      );
    });

    test('전혀 모르는 업종이면 null 을 반환한다', () {
      expect(mapper.map('알수없음 > 이상한것'), isNull);
    });

    test('빈 문자열/null 을 안전하게 처리한다', () {
      expect(mapper.map(null), isNull);
      expect(mapper.map('   '), isNull);
    });

    test('업종 이름은 가장 구체적인 단계를 쓴다', () {
      expect(
        PlaceCategoryMapper.primaryIndustry('음식점 > 중식 > 중국요리'),
        '중국요리',
      );
      expect(PlaceCategoryMapper.primaryIndustry(null), isNull);
    });

    test('반환하는 분류는 항상 앱의 체계 안에 있다', () {
      const List<String> samples = <String>[
        '음식점 > 카페 > 커피전문점',
        '가정,생활 > 편의점',
        '교통,수송 > 주차장',
        '의료,건강 > 병원',
        '문화,예술 > 영화관',
      ];
      for (final String sample in samples) {
        final CategoryPair? pair = mapper.map(sample);
        if (pair == null) continue;
        expect(
          CategoryTaxonomy.isValidPair(pair.category, pair.subcategory),
          isTrue,
          reason: '$sample -> $pair 가 체계에 없다',
        );
      }
    });
  });

  group('LookupBrandIndustry', () {
    test('처음 조회하면 API 를 부르고 결과를 저장한다', () async {
      final _FakeServer server =
          _FakeServer(body: _documents('음식점 > 카페 > 커피전문점'));
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      final BrandMetadata? result = await lookup('메가커피');

      expect(result, isNotNull);
      expect(result!.category, '식비');
      expect(result.subcategory, '카페');
      expect(result.industry, '커피전문점');
      expect(result.source, BrandMetadataSource.kakao);
      expect(server.callCount, 1);
    });

    test('두 번째 조회는 캐시로 끝난다 (API 재호출 없음)', () async {
      final _FakeServer server =
          _FakeServer(body: _documents('음식점 > 카페 > 커피전문점'));
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      await lookup('메가커피');
      await lookup('메가커피');
      await lookup('메가커피');

      expect(server.callCount, 1, reason: '브랜드당 최대 1회여야 한다');
    });

    test('못 찾은 결과도 캐시해 재조회하지 않는다', () async {
      final _FakeServer server = _FakeServer(
        body: '{"documents":[],"meta":{"total_count":0}}',
      );
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      expect(await lookup('존재하지않는가게'), isNull);
      expect(await lookup('존재하지않는가게'), isNull);

      expect(server.callCount, 1, reason: '음수 캐시가 없으면 할당량이 녹는다');
      expect(metadata.store.values.single.found, isFalse);
    });

    test('업종을 우리 체계로 옮기지 못해도 캐시한다', () async {
      final _FakeServer server =
          _FakeServer(body: _documents('알수없음 > 이상한업종'));
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      expect(await lookup('이상한가게'), isNull);
      expect(await lookup('이상한가게'), isNull);

      expect(server.callCount, 1);
      final BrandMetadata cached = metadata.store.values.single;
      expect(cached.found, isFalse);
      expect(cached.industry, '이상한업종', reason: '업종 문자열은 남겨 두면 참고가 된다');
    });

    test('키가 없으면 호출하지 않는다', () async {
      final _FakeServer server =
          _FakeServer(body: _documents('음식점 > 카페'));
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: _FakeMetadataRepository(),
        placeApi: server.build(),
        settings: _FakeSettingsRepository(const AppSettings()),
      );

      expect(await lookup('메가커피'), isNull);
      expect(server.callCount, 0);
    });

    test('기능을 끄면 호출하지 않는다', () async {
      final _FakeServer server =
          _FakeServer(body: _documents('음식점 > 카페'));
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: _FakeMetadataRepository(),
        placeApi: server.build(),
        settings: _FakeSettingsRepository(
          const AppSettings(placeApiKey: 'k', placeApiEnabled: false),
        ),
      );

      expect(await lookup('메가커피'), isNull);
      expect(server.callCount, 0);
    });

    test('429 를 받으면 API 사용을 자동으로 중단한다', () async {
      final _FakeServer server = _FakeServer(body: '{}', statusCode: 429);
      final _FakeSettingsRepository settings =
          _FakeSettingsRepository(_withKey);
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: _FakeMetadataRepository(),
        placeApi: server.build(),
        settings: settings,
      );

      expect(await lookup('브랜드A'), isNull);
      expect(settings.current.isPlaceApiThrottled, isTrue);
      expect(settings.current.canUsePlaceApi, isFalse);

      // 쉬는 동안에는 다른 브랜드도 조회하지 않는다.
      expect(await lookup('브랜드B'), isNull);
      expect(server.callCount, 1, reason: '한도 초과 후에는 호출을 멈춰야 한다');
    });

    test('한도 초과는 캐시하지 않는다 (일시적 상태)', () async {
      final _FakeServer server = _FakeServer(body: '{}', statusCode: 429);
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      await lookup('브랜드A');
      expect(metadata.store, isEmpty);
    });

    test('네트워크 실패는 캐시하지 않는다', () async {
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: PlaceApiDataSource(
          client: MockClient((http.Request request) async {
            throw http.ClientException('연결 실패');
          }),
        ),
        settings: _FakeSettingsRepository(_withKey),
      );

      expect(await lookup('브랜드A'), isNull);
      expect(metadata.store, isEmpty, reason: '일시적 실패는 다시 시도할 수 있어야 한다');
    });

    test('사용자가 지정한 분류를 조회 결과가 덮어쓰지 않는다', () async {
      final _FakeServer server =
          _FakeServer(body: _documents('음식점 > 카페 > 커피전문점'));
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      await metadata.markUserModified(
        brand: '메가커피',
        category: '식비',
        subcategory: '디저트',
      );

      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: metadata,
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      final BrandMetadata? result = await lookup('메가커피');

      expect(result!.subcategory, '디저트');
      expect(server.callCount, 0, reason: '사용자 지정이 있으면 조회할 이유가 없다');
    });

    test('빈 브랜드명은 조회하지 않는다', () async {
      final _FakeServer server = _FakeServer(body: _documents('음식점'));
      final LookupBrandIndustry lookup = LookupBrandIndustry(
        metadata: _FakeMetadataRepository(),
        placeApi: server.build(),
        settings: _FakeSettingsRepository(_withKey),
      );

      expect(await lookup('   '), isNull);
      expect(server.callCount, 0);
    });

    test('조회 캐시를 비워도 사용자 지정은 남는다', () async {
      final _FakeMetadataRepository metadata = _FakeMetadataRepository();
      await metadata.save(
        BrandMetadata(
          brand: '자동조회브랜드',
          normalizedBrand: '자동조회브랜드',
          category: '식비',
          subcategory: '카페',
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime(2026),
        ),
      );
      await metadata.markUserModified(
        brand: '사용자지정브랜드',
        category: '생활',
        subcategory: '편의점',
      );

      expect(await metadata.clearLookupCache(), 1);
      expect(metadata.store.keys.single, '사용자지정브랜드');
    });
  });

  group('AppSettings 장소 API 게이트', () {
    test('키가 있고 켜져 있으면 호출 가능', () {
      expect(const AppSettings(placeApiKey: 'k').canUsePlaceApi, isTrue);
    });

    test('공백만 있는 키는 없는 것으로 본다', () {
      expect(const AppSettings(placeApiKey: '   ').canUsePlaceApi, isFalse);
    });

    test('차단 시각이 지나면 다시 호출할 수 있다', () {
      final AppSettings past = AppSettings(
        placeApiKey: 'k',
        placeApiBlockedUntilMillis: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      expect(past.isPlaceApiThrottled, isFalse);
      expect(past.canUsePlaceApi, isTrue);
    });

    test('차단 시각 이전에는 호출하지 않는다', () {
      final AppSettings blocked = AppSettings(
        placeApiKey: 'k',
        placeApiBlockedUntilMillis:
            DateTime.now().add(const Duration(hours: 5)).millisecondsSinceEpoch,
      );
      expect(blocked.isPlaceApiThrottled, isTrue);
      expect(blocked.canUsePlaceApi, isFalse);
    });
  });
}
