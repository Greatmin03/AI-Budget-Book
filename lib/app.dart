import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'presentation/home_shell.dart';

class BudgetBookApp extends StatelessWidget {
  const BudgetBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 가계부',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),

      // 날짜 선택기 등 Material 기본 위젯을 한국어로 보여주기 위해 필요하다.
      locale: const Locale('ko'),
      supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const HomeShell(),
    );
  }
}
