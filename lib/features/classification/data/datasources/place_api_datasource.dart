import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/logging/app_logger.dart';

/// 장소 검색 결과.
class PlaceLookupResult {
  const PlaceLookupResult({
    required this.status,
    this.placeName,
    this.categoryName,
    this.message,
  });

  const PlaceLookupResult.notFound()
      : status = PlaceLookupStatus.notFound,
        placeName = null,
        categoryName = null,
        message = null;

  const PlaceLookupResult.quotaExceeded(this.message)
      : status = PlaceLookupStatus.quotaExceeded,
        placeName = null,
        categoryName = null;

  const PlaceLookupResult.failed(this.message)
      : status = PlaceLookupStatus.failed,
        placeName = null,
        categoryName = null;

  final PlaceLookupStatus status;

  /// API 가 찾은 장소 이름.
  final String? placeName;

  /// 업종 계층 문자열. 예: `음식점 > 중식 > 중국요리`
  final String? categoryName;

  final String? message;

  bool get isSuccess => status == PlaceLookupStatus.success;

  /// 할당량이 소진되었는가. 이 경우 이후 호출을 멈춘다.
  bool get isQuotaExceeded => status == PlaceLookupStatus.quotaExceeded;
}

enum PlaceLookupStatus {
  success,

  /// 정상 응답이지만 결과가 없다. (재조회해도 없으므로 캐시한다)
  notFound,

  /// 호출 제한 초과. API 사용을 중단해야 한다.
  quotaExceeded,

  /// 네트워크/서버 오류. 일시적일 수 있다.
  failed,
}

/// 카카오 로컬 API 로 브랜드 업종을 조회한다.
///
/// ## 비용
/// 카카오 로컬 API 는 **무료**이고 카드 등록이 필요 없다.
/// 키는 **사용자가 직접 발급해 설정에 넣는다.** 앱에 개발자 키를 심으면
/// 추출되어 오용되고, 할당량이 모든 사용자에게 공유된다.
/// 사용자 본인의 키를 쓰면 사용자 비용은 0원이고 할당량도 본인 것이다.
///
/// ## 호출 최소화
/// 이 클래스는 캐시를 모른다. 호출 여부는 상위 계층
/// (`BrandMetadataRepository`)이 결정한다. 브랜드당 1회만 호출되고,
/// "못 찾음" 결과도 캐시되어 재호출되지 않는다.
class PlaceApiDataSource {
  PlaceApiDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _host = 'dapi.kakao.com';
  static const String _path = '/v2/local/search/keyword.json';

  /// 브랜드명으로 장소를 검색한다.
  ///
  /// GPS 를 쓰지 않는다. 결제 알림에 이미 브랜드명이 있고,
  /// 백화점·푸드코트·역사에서는 좌표 기반 판정이 오히려 틀린다.
  Future<PlaceLookupResult> lookup({
    required String restApiKey,
    required String brand,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final String query = brand.trim();
    if (query.isEmpty) return const PlaceLookupResult.notFound();
    if (restApiKey.trim().isEmpty) {
      return const PlaceLookupResult.failed('API 키가 설정되지 않았습니다.');
    }

    final Uri uri = Uri.https(_host, _path, <String, String>{
      'query': query,
      // 가장 관련도 높은 1건만 받는다. 호출량과 파싱 비용을 줄인다.
      'size': '1',
    });

    try {
      final http.Response response = await _client
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'KakaoAK ${restApiKey.trim()}',
            },
          )
          .timeout(timeout);

      // 429 는 호출 제한. 카카오는 한도 초과 시 429 를 준다.
      if (response.statusCode == 429) {
        return const PlaceLookupResult.quotaExceeded('호출 한도를 초과했습니다.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return PlaceLookupResult.failed(
          'API 키가 올바르지 않습니다 (HTTP ${response.statusCode}).',
        );
      }
      if (response.statusCode != 200) {
        return PlaceLookupResult.failed('HTTP ${response.statusCode}');
      }

      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        return const PlaceLookupResult.failed('응답 형식이 예상과 다릅니다.');
      }

      final Object? documents = decoded['documents'];
      if (documents is! List<Object?> || documents.isEmpty) {
        return const PlaceLookupResult.notFound();
      }

      final Object? first = documents.first;
      if (first is! Map<String, Object?>) {
        return const PlaceLookupResult.notFound();
      }

      final String? categoryName = _string(first['category_name']);
      if (categoryName == null) {
        return const PlaceLookupResult.notFound();
      }

      return PlaceLookupResult(
        status: PlaceLookupStatus.success,
        placeName: _string(first['place_name']),
        categoryName: categoryName,
      );
    } on Object catch (e) {
      final String raw = e.toString();
      if (raw.contains('TimeoutException')) {
        return const PlaceLookupResult.failed('응답 시간 초과');
      }
      AppLogger.w('장소 조회 실패: $raw');
      return PlaceLookupResult.failed(raw);
    }
  }

  /// 설정 화면의 "연결 테스트".
  Future<PlaceLookupResult> testKey(String restApiKey) =>
      lookup(restApiKey: restApiKey, brand: '스타벅스');

  static String? _string(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void dispose() => _client.close();
}
