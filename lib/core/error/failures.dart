/// 도메인 계층이 인식하는 실패 유형.
sealed class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 알림 문자열에서 결제 정보를 추출하지 못했다.
class ParsingFailure extends Failure {
  const ParsingFailure(super.message, {this.rawText});

  final String? rawText;
}

/// Ollama 호출 실패(서버 미실행, 타임아웃, 모델 없음 등).
class LlmFailure extends Failure {
  const LlmFailure(super.message, {this.statusCode});

  final int? statusCode;
}

/// LLM 이 규격에 맞지 않는 응답을 돌려주었다.
class LlmContractFailure extends Failure {
  const LlmContractFailure(super.message, {this.rawResponse});

  final String? rawResponse;
}

/// 로컬 DB 오류.
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

/// 네이티브 채널(Notification Listener) 오류.
class PlatformFailure extends Failure {
  const PlatformFailure(super.message);
}
