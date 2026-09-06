import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_shell.dart';
import 'theme.dart';

class ShijiApp extends StatelessWidget {
  const ShijiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '食记',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}
