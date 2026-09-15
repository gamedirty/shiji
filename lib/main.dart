import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 手机端锁定竖屏（桌面端为空实现）
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // 数据加载完成（或失败被记录）后再进入 UI，避免页面停留在未知状态
  final store = AppStore();
  await store.init();
  runApp(ChangeNotifierProvider.value(value: store, child: const ShijiApp()));
}
