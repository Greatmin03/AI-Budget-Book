/// 파싱 실패 알림 보관함.
///
/// 파서 규칙을 개선하기 위한 자료다. 외부로 전송되지 않고 로컬에만 남는다.
abstract interface class IngestFailureRepository {
  Future<void> record({
    required String? packageName,
    required String? title,
    required String? text,
    required DateTime? postedAt,
    required String reason,
  });

  Future<List<IngestFailureRecord>> recent({int limit = 50});

  Future<int> clear();
}

class IngestFailureRecord {
  const IngestFailureRecord({
    required this.reason,
    required this.createdAt,
    this.packageName,
    this.title,
    this.text,
    this.postedAt,
  });

  final String reason;
  final DateTime createdAt;
  final String? packageName;
  final String? title;
  final String? text;
  final DateTime? postedAt;

  String get preview {
    final String body = <String?>[title, text]
        .where((String? e) => e != null && e.trim().isNotEmpty)
        .join(' / ');
    return body.isEmpty ? '(내용 없음)' : body;
  }
}
