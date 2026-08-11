import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../ui/home_shell.dart';
import 'app_controller.dart';
import 'app_theme.dart';

class TodoApp extends StatelessWidget {
  const TodoApp({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'todo',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: controller.themeMode,
        home: HomeShell(controller: controller),
      ),
    );
  }
}
