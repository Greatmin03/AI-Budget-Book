import '../entities/brand_metadata.dart';

abstract interface class BrandMetadataRepository {
  /// 캐시에서 찾는다. 없으면 null(= 아직 조회한 적 없음).
  ///
  /// `found = false` 로 저장된 것도 반환한다. 호출자는 그것을
  /// "이미 조회했지만 못 찾았다" 로 해석해 재조회하지 않아야 한다.
  Future<BrandMetadata?> find(String brand);

  Future<BrandMetadata> save(BrandMetadata metadata);

  /// 사용자가 분류를 바꿨을 때 메타데이터도 사용자 지정으로 고정한다.
  Future<void> markUserModified({
    required String brand,
    required String category,
    required String subcategory,
  });

  /// 저장된 메타데이터 전체(설정 화면 확인용).
  Future<List<BrandMetadata>> findAll({int limit = 200});

  /// 조회 캐시를 비운다. 다음부터 다시 조회한다.
  ///
  /// 사용자 지정 항목은 남긴다.
  Future<int> clearLookupCache();

  Future<int> count();
}
