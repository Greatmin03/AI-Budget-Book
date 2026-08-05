import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/di/injector.dart';
import 'core/logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ko_KR 날짜 포맷을 쓰려면 로케일 데이터를 먼저 등록해야 한다.
  // (등록하지 않으면 DateFormat('...', 'ko_KR') 이 런타임 예외를 던진다)
  initializeDateFormatting('ko_KR');
  Intl.defaultLocale = 'ko_KR';

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.e('Flutter 오류', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  await Injector.instance.init();

  // 알림 접근 권한이 이미 있으면 곧바로 수집을 시작한다.
  final bool granted =
      await Injector.instance.notifications.isPermissionGranted();
  if (granted) {
    await Injector.instance.ingestService.start();
  } else {
    AppLogger.w('알림 접근 권한이 없어 수집을 시작하지 않았습니다.');
  }

  // AI 분석 대기열 확인은 **기다리지 않는다.**
  // Ollama 헬스체크가 수 초 걸릴 수 있는데, 그걸 기다리면 첫 화면이 늦게 뜬다.
  // 배너는 결과가 오는 대로 나타난다.
  Injector.instance.aiQueue.initialize();

  runApp(const BudgetBookApp());
}
