/// 네이티브 NotificationListenerService 가 수집한 알림 원본.
///
/// 이 단계에서는 아무것도 해석하지 않는다. 파싱은 parsing 피처의 책임이다.
class RawNotification {
  const RawNotification({
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAt,
    this.subText,
    this.bigText,
  });

  final String packageName;
  final String title;
  final String text;
  final DateTime postedAt;
  final String? subText;
  final String? bigText;

  /// 파싱 대상이 되는 전체 문자열.
  ///
  /// 카드사마다 가맹점/금액을 title 또는 text 또는 bigText 에 넣는다.
  /// 따라서 모두 이어붙여서 한 번에 훑는다.
  String get combinedText {
    final List<String> parts = <String>[
      title,
      text,
      if (subText != null && subText!.isNotEmpty) subText!,
      if (bigText != null && bigText!.isNotEmpty && bigText != text) bigText!,
    ].where((String e) => e.trim().isNotEmpty).toList();
    return parts.join('\n');
  }

  @override
  String toString() =>
      'RawNotification($packageName, "$title", "$text", $postedAt)';
}
