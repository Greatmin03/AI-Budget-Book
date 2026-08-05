import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  LogEntry(this.level, this.message, this.time);

  final LogLevel level;
  final String message;
  final DateTime time;
}

/// 아주 얇은 로거.
///
/// 외부 서버로 아무것도 보내지 않는다(설계 원칙: 개인정보 외부 전송 금지).
/// 최근 로그를 메모리에 유지해 설정 화면의 "동작 로그" 에 노출한다.
class AppLogger {
  const AppLogger._();

  static const int _maxEntries = 300;
  static final Queue<LogEntry> _buffer = Queue<LogEntry>();

  /// 설정 화면이 구독하는 리스너블. 로그가 추가되면 알림이 간다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<LogEntry> get entries => _buffer.toList(growable: false).reversed.toList();

  static void d(String message) => _log(LogLevel.debug, message);
  static void i(String message) => _log(LogLevel.info, message);
  static void w(String message) => _log(LogLevel.warn, message);
  static void e(String message, [Object? error, StackTrace? stack]) {
    _log(LogLevel.error, error == null ? message : '$message: $error');
    if (stack != null && kDebugMode) {
      debugPrint(stack.toString());
    }
  }

  static void _log(LogLevel level, String message) {
    _buffer.addLast(LogEntry(level, message, DateTime.now()));
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
    if (kDebugMode) {
      debugPrint('[${level.name.toUpperCase()}] $message');
    }
    revision.value++;
  }

  static void clear() {
    _buffer.clear();
    revision.value++;
  }
}
