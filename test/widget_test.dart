import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiji/app.dart';
import 'package:shiji/data/store.dart';
import 'package:shiji/models.dart';

void main() {
  testWidgets('首次启动：加载示例数据并显示饮食计划首页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: const ShijiApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 底部导航两个 tab
    expect(find.text('饮食计划'), findsWidgets);
    expect(find.text('食材库'), findsWidgets);
    // 计划页核心元素
    expect(find.text('今天的安排'), findsOneWidget);
    expect(find.text('全天合计'), findsOneWidget);
    // 示例数据已写入
    expect(store.foods.length, greaterThanOrEqualTo(20));
    expect(store.meals.length, 3);
    expect(store.entriesFor(dateKeyOf(DateTime.now())).length, 4);
  });

  testWidgets('记录饮食弹层可打开并添加一条记录', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.init();
    final before = store.diary.length;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: const ShijiApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 打开 + 弹层
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('记录饮食'), findsOneWidget);

    // 选第一个食材并添加
    await tester.tap(find.text('鸡胸肉').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(store.diary.length, before + 1);
  });
}
