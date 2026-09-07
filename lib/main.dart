import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 手机端锁定竖屏（桌面端为空实现）
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppStore()..init(),
      child: const ShijiApp(),
    ),
  );
}
