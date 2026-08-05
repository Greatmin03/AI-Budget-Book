import '../../domain/entities/raw_notification.dart';

/// 네이티브(Kotlin) -> Dart 로 전달되는 Map 을 엔티티로 변환한다.
///
/// 네이티브가 보내는 키는 `NotificationBridge.kt` 와 1:1로 맞춰야 한다.
class RawNotificationDto {
  const RawNotificationDto({
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAt,
    this.subText,
    this.bigText,
  });

  factory RawNotificationDto.fromMap(Map<Object?, Object?> map) {
    return RawNotificationDto(
      packageName: _string(map['packageName']),
      title: _string(map['title']),
      text: _string(map['text']),
      subText: _nullableString(map['subText']),
      bigText: _nullableString(map['bigText']),
      postedAt: _int(map['postedAt']),
    );
  }

  final String packageName;
  final String title;
  final String text;
  final String? subText;
  final String? bigText;

  /// epoch millis
  final int postedAt;

  RawNotification toEntity() => RawNotification(
        packageName: packageName,
        title: title,
        text: text,
        subText: subText,
        bigText: bigText,
        postedAt: DateTime.fromMillisecondsSinceEpoch(
          postedAt > 0 ? postedAt : DateTime.now().millisecondsSinceEpoch,
        ),
      );

  static String _string(Object? value) => value is String ? value : '';

  static String? _nullableString(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
