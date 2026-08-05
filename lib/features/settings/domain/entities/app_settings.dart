/// 앱 설정값.
///
/// 모두 로컬 SQLite `settings` 테이블에 저장된다(외부 전송 없음).
class AppSettings {
  const AppSettings({
    this.llmEnabled = false,
    this.ollamaBaseUrl = defaultOllamaBaseUrl,
    this.ollamaModel = defaultOllamaModel,
    this.requestTimeoutSeconds = 25,
    this.autoLearnBrandRule = true,
    this.minConfidenceToLearn = 0.5,
    this.placeApiKey = '',
    this.placeApiEnabled = true,
    this.placeApiBlockedUntilMillis = 0,
  });

  /// Android 에뮬레이터에서 호스트 PC 를 가리키는 주소.
  /// 실제 기기에서는 PC 의 LAN IP(예: `http://192.168.0.10:11434`)로 바꿔야 한다.
  static const String defaultOllamaBaseUrl = 'http://10.0.2.2:11434';
  /// 기본 모델.
  ///
  /// 이 작업은 "가맹점 이름 -> 업종 분류" 라는 좁은 분류 문제다.
  /// 큰 모델이 필요하지 않고, 4B 급이면 노트북 CPU 로도 수 초 안에 답한다.
  ///
  /// 설정에서 바꿀 수 있다. 추론(thinking) 모델을 넣으면
  /// `OllamaRemoteDataSource` 가 요청 형태를 자동으로 맞춘다.
  static const String defaultOllamaModel = 'gemma3:4b';

  /// LLM 분류 사용 여부.
  ///
  /// **기본값은 꺼짐이다.** 초기 버전에서 LLM 은 필수 요소가 아니다.
  /// 꺼져 있으면 처음 보는 브랜드는 "분류 필요" 상태로 저장되고
  /// 사용자가 한 번 카테고리를 고르면 이후 자동 분류된다.
  /// 켜면 그 한 번의 선택마저 LLM 이 대신한다.
  final bool llmEnabled;

  final String ollamaBaseUrl;
  final String ollamaModel;
  final int requestTimeoutSeconds;

  /// LLM 이 분류한 결과를 브랜드 규칙으로도 승격시킬지.
  /// (켜면 같은 브랜드의 다른 지점도 즉시 자동 분류된다)
  final bool autoLearnBrandRule;

  /// 이 확신도 미만이면 학습하지 않고 `기타/미분류` 로 남긴다.
  final double minConfidenceToLearn;

  /// 카카오 로컬 API REST 키. **사용자가 직접 발급해 넣는다.**
  ///
  /// 앱에 개발자 키를 심지 않는 이유:
  ///  - 클라이언트에 넣은 키는 추출되어 오용된다
  ///  - 할당량이 모든 사용자에게 공유된다
  /// 본인 키를 쓰면 무료 할당량도 본인 것이므로 비용이 발생하지 않는다.
  final String placeApiKey;

  /// 장소 API 사용 여부. 키가 없으면 어차피 동작하지 않는다.
  final bool placeApiEnabled;

  /// 호출 한도 초과로 API 를 쉬게 할 시각(epoch millis). 0이면 정상.
  ///
  /// 429 를 받으면 이 값을 미래로 설정해 **자동으로 호출을 멈춘다.**
  final int placeApiBlockedUntilMillis;

  /// 지금 장소 API 를 호출해도 되는지.
  bool get canUsePlaceApi {
    if (!placeApiEnabled) return false;
    if (placeApiKey.trim().isEmpty) return false;
    if (placeApiBlockedUntilMillis <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch >= placeApiBlockedUntilMillis;
  }

  /// 한도 초과로 쉬고 있는 중인지.
  bool get isPlaceApiThrottled =>
      placeApiBlockedUntilMillis > 0 &&
      DateTime.now().millisecondsSinceEpoch < placeApiBlockedUntilMillis;

  DateTime? get placeApiBlockedUntil => placeApiBlockedUntilMillis > 0
      ? DateTime.fromMillisecondsSinceEpoch(placeApiBlockedUntilMillis)
      : null;

  AppSettings copyWith({
    bool? llmEnabled,
    String? ollamaBaseUrl,
    String? ollamaModel,
    int? requestTimeoutSeconds,
    bool? autoLearnBrandRule,
    double? minConfidenceToLearn,
    String? placeApiKey,
    bool? placeApiEnabled,
    int? placeApiBlockedUntilMillis,
  }) {
    return AppSettings(
      llmEnabled: llmEnabled ?? this.llmEnabled,
      ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
      ollamaModel: ollamaModel ?? this.ollamaModel,
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      autoLearnBrandRule: autoLearnBrandRule ?? this.autoLearnBrandRule,
      minConfidenceToLearn:
          minConfidenceToLearn ?? this.minConfidenceToLearn,
      placeApiKey: placeApiKey ?? this.placeApiKey,
      placeApiEnabled: placeApiEnabled ?? this.placeApiEnabled,
      placeApiBlockedUntilMillis:
          placeApiBlockedUntilMillis ?? this.placeApiBlockedUntilMillis,
    );
  }
}

/// `settings` 테이블 키 목록.
class SettingsKeys {
  const SettingsKeys._();

  static const String llmEnabled = 'llm_enabled';
  static const String ollamaBaseUrl = 'ollama_base_url';
  static const String ollamaModel = 'ollama_model';
  static const String requestTimeoutSeconds = 'request_timeout_seconds';
  static const String autoLearnBrandRule = 'auto_learn_brand_rule';
  static const String minConfidenceToLearn = 'min_confidence_to_learn';
  static const String placeApiKey = 'place_api_key';
  static const String placeApiEnabled = 'place_api_enabled';
  static const String placeApiBlockedUntil = 'place_api_blocked_until';
}
