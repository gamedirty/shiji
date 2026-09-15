import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiji/app.dart';
import 'package:shiji/data/store.dart';
import 'package:shiji/models.dart';

void main() {
  testWidgets('首次启动：预置食材与组合餐，但不伪造任何饮食记录', (tester) async {
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
    // 示例食材与组合餐已写入；日记必须为空（演示数据不能伪装成用户事实）
    expect(store.foods.length, greaterThanOrEqualTo(20));
    expect(store.meals.length, 3);
    expect(store.diary, isEmpty);
  });

  testWidgets('添加饮食：选择食材后「记为已吃」，生成带快照的记录', (tester) async {
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

    // 打开 + 弹层
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('搜索食材'), findsOneWidget);

    // 选第一个食材并记为已吃
    await tester.tap(find.text('鸡胸肉').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记为已吃'));
    await tester.pumpAndSettle();

    expect(store.diary.length, 1);
    final e = store.diary.first;
    expect(e.status, EntryStatus.consumed);
    expect(e.title, '鸡胸肉');
    expect(e.grams, 100);
    expect(e.nutrition.calories, greaterThan(0));
    // 已摄入口径应包含这条记录
    final today = dateKeyOf(DateTime.now());
    expect(store.consumedTotalsFor(today).calories, greaterThan(0));
    expect(store.plannedTotalsFor(today).calories, 0);
  });
}
