import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiji/data/store.dart';
import 'package:shiji/models.dart';

void main() {
  Future<AppStore> freshStore(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final store = AppStore();
    await store.init();
    return store;
  }

  AppStore storeWith() {
    final store = AppStore();
    return store;
  }

  test('Nutrition 热量按 4/4/9 估算', () {
    const n = Nutrition(protein: 10, carbs: 20, fat: 5);
    expect(n.calories, 10 * 4 + 20 * 4 + 5 * 9);
  });

  test('guessByTime：凌晨属于加餐而不是早餐', () {
    expect(MealTypeX.guessByTime(DateTime(2026, 9, 15, 2)), MealType.snack);
    expect(MealTypeX.guessByTime(DateTime(2026, 9, 15, 5, 59)), MealType.snack);
    expect(MealTypeX.guessByTime(DateTime(2026, 9, 15, 6)), MealType.breakfast);
    expect(MealTypeX.guessByTime(DateTime(2026, 9, 15, 12)), MealType.lunch);
    expect(MealTypeX.guessByTime(DateTime(2026, 9, 15, 18)), MealType.dinner);
    expect(MealTypeX.guessByTime(DateTime(2026, 9, 15, 21)), MealType.snack);
  });

  test('记录是快照：修改食材营养不回写历史', () async {
    final store = await freshStore({});
    final food = const Food(
      id: 'f1',
      name: '鸡胸肉',
      protein: 24,
      carbs: 0.6,
      fat: 3.4,
    );
    await store.upsertFood(food);
    final entry = store.buildEntry(
      dateKey: '2026-09-15',
      type: MealType.lunch,
      source: EntrySource.food,
      refId: 'f1',
      grams: 200,
      status: EntryStatus.consumed,
    );
    await store.addEntry(entry);
    final before = entry.nutrition;

    // 之后修改食材：历史快照必须保持不变
    await store.upsertFood(food.copyWith(protein: 99, fat: 50));
    final loaded = store.diary.first;
    expect(loaded.nutrition.protein, closeTo(before.protein, 1e-9));
    expect(loaded.nutrition.calories, closeTo(before.calories, 1e-9));
    // 新记录才使用新定义
    final fresh = store.buildEntry(
      dateKey: '2026-09-16',
      type: MealType.lunch,
      source: EntrySource.food,
      refId: 'f1',
      grams: 200,
    );
    expect(fresh.nutrition.protein, greaterThan(before.protein));
  });

  test('删除食材或组合餐，不删除历史记录', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(id: 'f1', name: '米饭（熟）', carbs: 28.2, servingGrams: 200),
    );
    await store.upsertMeal(
      MealTemplate(
        id: 'm1',
        name: '能量碗',
        items: [MealComponent(foodId: 'f1', grams: 200)],
      ),
    );
    await store.addEntry(
      store.buildEntry(
        dateKey: '2026-09-15',
        type: MealType.lunch,
        source: EntrySource.meal,
        refId: 'm1',
        grams: 200,
        status: EntryStatus.consumed,
      ),
    );
    expect(store.diary.length, 1);

    await store.removeMeal('m1');
    expect(store.diary.length, 1);
    expect(store.diary.first.title, '能量碗');
    expect(store.diary.first.nutrition.calories, greaterThan(0));

    await store.removeFood('f1');
    expect(store.diary.length, 1);
  });

  test('组合餐持久化克数：调整食材的"一份"克数不改变配方与营养', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(id: 'f1', name: '米饭（熟）', carbs: 28.2, servingGrams: 200),
    );
    await store.upsertMeal(
      MealTemplate(
        id: 'm1',
        name: '一碗饭',
        items: [MealComponent(foodId: 'f1', grams: 200)],
      ),
    );
    MealTemplate mealOf() => store.meals.firstWhere((m) => m.id == 'm1');
    final before = store.mealNutrition(mealOf());

    // "一份"克数改为 100：配方仍是 200g，营养不变
    await store.upsertFood(
      const Food(id: 'f1', name: '米饭（熟）', carbs: 28.2, servingGrams: 100),
    );
    expect(mealOf().items.first.grams, 200);
    expect(store.mealNutrition(mealOf()).carbs, closeTo(before.carbs, 1e-9));
  });

  test('v1 旧数据迁移：servings/done 换算为克数、状态与快照', () async {
    final legacy = {
      'shiji.foods': jsonEncode([
        {
          'id': 'f1',
          'name': '鸡胸肉',
          'protein': 24,
          'carbs': 0.6,
          'fat': 3.4,
          'servingGrams': 100,
        },
      ]),
      'shiji.meals': jsonEncode([
        {
          'id': 'm1',
          'name': '旧组合餐',
          'items': [
            {'foodId': 'f1', 'servings': 2},
          ],
        },
      ]),
      'shiji.diary': jsonEncode([
        {
          'id': 'd1',
          'dateKey': '2026-09-01',
          'type': 'lunch',
          'source': 'food',
          'refId': 'f1',
          'servings': 1.5,
          'done': true,
        },
      ]),
      'shiji.kcalTarget': 2400.0,
    };
    final store = await freshStore(legacy);

    // 食材组件：2 份 × 100g → 200g
    expect(store.meals.firstWhere((m) => m.id == 'm1').items.first.grams, 200);
    // 日记：1.5 份 × 100g → 150g，done → consumed，营养已固化
    final e = store.diary.first;
    expect(e.grams, 150);
    expect(e.status, EntryStatus.consumed);
    expect(e.title, '鸡胸肉');
    expect(e.nutrition.protein, closeTo(24 * 1.5, 1e-9));
    // 旧热量目标迁移
    expect(store.targets.kcal, 2400);
  });

  test('导出再导入，数据完整还原', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(id: 'f1', name: '燕麦', protein: 13.5, carbs: 58, fat: 6.5),
    );
    await store.addEntry(
      store.buildEntry(
        dateKey: '2026-09-15',
        type: MealType.breakfast,
        source: EntrySource.food,
        refId: 'f1',
        grams: 80,
        status: EntryStatus.consumed,
      ),
    );
    await store.setTargets(
      const NutritionTargets(kcal: 2200, protein: 160, carbs: 220, fat: 70),
    );

    final backup = store.exportJson();
    final restored = storeWith();
    await restored.init();
    final ok = await restored.importJson(backup);
    expect(ok, isTrue);
    expect(restored.foods.length, store.foods.length);
    expect(restored.meals.length, store.meals.length);
    expect(restored.diary.length, store.diary.length);
    expect(restored.diary.first.title, '燕麦');
    expect(
      restored.diary.first.nutrition.calories,
      closeTo(store.diary.first.nutrition.calories, 1e-9),
    );
    expect(restored.targets.kcal, 2200);
  });

  test('非法备份内容被拒绝且不改动现有数据', () async {
    final store = await freshStore({});
    final foodsBefore = store.foods.length;
    expect(await store.importJson('这不是 JSON'), isFalse);
    expect(store.foods.length, foodsBefore);
  });

  test('计划与已摄入分开统计', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(
        id: 'f1',
        name: '鸡蛋',
        protein: 13.3,
        carbs: 1.5,
        fat: 10,
        servingGrams: 50,
      ),
    );
    await store.addEntry(
      store.buildEntry(
        dateKey: '2026-09-15',
        type: MealType.breakfast,
        source: EntrySource.food,
        refId: 'f1',
        grams: 50,
        status: EntryStatus.consumed,
      ),
    );
    await store.addEntry(
      store.buildEntry(
        dateKey: '2026-09-15',
        type: MealType.dinner,
        source: EntrySource.food,
        refId: 'f1',
        grams: 100,
        status: EntryStatus.planned,
      ),
    );
    // 50g × 13.3g/100g = 6.65；100g → 13.3
    final consumed = store.consumedTotalsFor('2026-09-15');
    final planned = store.plannedTotalsFor('2026-09-15');
    expect(consumed.protein, closeTo(6.65, 1e-9));
    expect(planned.protein, closeTo(13.3, 1e-9));

    // 计划完成 → 进入已摄入口径
    final plannedEntry = store.diary.firstWhere(
      (e) => e.status == EntryStatus.planned,
    );
    await store.setEntryStatus(plannedEntry.id, EntryStatus.consumed);
    expect(store.consumedTotalsFor('2026-09-15').protein, closeTo(19.95, 1e-9));
    expect(store.plannedTotalsFor('2026-09-15').protein, 0);
  });
  // ---------- 第 2 轮评审回归 ----------

  test('调整克数：按原快照等比缩放，不受来源修改影响', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(id: 'f1', name: '鸡胸肉', protein: 24, carbs: 0.6, fat: 3.4),
    );
    final e = store.buildEntry(
      dateKey: '2026-09-15',
      type: MealType.lunch,
      source: EntrySource.food,
      refId: 'f1',
      grams: 100,
      status: EntryStatus.consumed,
    );
    await store.addEntry(e);
    // 之后来源被改成完全不同的定义
    await store.upsertFood(
      const Food(id: 'f1', name: '鸡胸肉（改）', protein: 99, servingGrams: 200),
    );
    final ok = await store.setEntryGrams(e.id, 200);
    expect(ok, isTrue);
    final updated = store.diary.first;
    expect(updated.title, '鸡胸肉'); // 快照名不被污染
    expect(updated.grams, 200);
    expect(updated.protein, closeTo(48, 1e-9)); // 24 × 2，而非 99 × 2
  });

  test('调整克数：零克数的异常快照被拒绝且数据不变', () async {
    // 现在的 addEntry 会拒绝零克数；零克记录只能来自旧数据迁移（来源已删）
    final store = await freshStore({
      'shiji.foods': jsonEncode([]),
      'shiji.meals': jsonEncode([]),
      'shiji.diary': jsonEncode([
        {
          'id': 'd0',
          'dateKey': '2026-09-15',
          'type': 'lunch',
          'source': 'food',
          'refId': 'gone',
          'servings': 0,
        },
      ]),
    });
    expect(store.diary.first.grams, 0);
    final ok = await store.setEntryGrams('d0', 100);
    expect(ok, isFalse);
    expect(store.diary.first.grams, 0);
    // 新记录被拒绝零克数
    expect(await store.addEntry(store.diary.first), isFalse);
  });

  test('并发提交不丢失更新（写队列内读状态）', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(
        id: 'f1',
        name: '鸡蛋',
        protein: 13.3,
        carbs: 1.5,
        fat: 10,
        servingGrams: 50,
      ),
    );
    final a = store.buildEntry(
      dateKey: '2026-09-15',
      type: MealType.breakfast,
      source: EntrySource.food,
      refId: 'f1',
      grams: 50,
    );
    final b = store.buildEntry(
      dateKey: '2026-09-15',
      type: MealType.lunch,
      source: EntrySource.food,
      refId: 'f1',
      grams: 100,
    );
    await Future.wait([store.addEntry(a), store.addEntry(b)]);
    expect(store.diary.length, 2);
  });

  test('copyDay：源日期等于目标日期被拒绝', () async {
    final store = await freshStore({});
    final n = await store.copyDay('2026-09-15', '2026-09-15');
    expect(n, -1);
  });

  test('copyDay：配方被清空的组合餐按历史快照复制', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(id: 'f1', name: '米饭（熟）', carbs: 28.2, servingGrams: 200),
    );
    await store.upsertMeal(
      MealTemplate(
        id: 'm1',
        name: '一碗饭',
        items: [MealComponent(foodId: 'f1', grams: 200)],
      ),
    );
    final e = store.buildEntry(
      dateKey: '2026-09-14',
      type: MealType.lunch,
      source: EntrySource.meal,
      refId: 'm1',
      grams: 200,
    );
    await store.addEntry(e);
    // 食材被删 → 组合餐配方清空，但历史快照完好
    await store.removeFood('f1');

    final n = await store.copyDay('2026-09-14', '2026-09-15');
    expect(n, 1);
    final copied = store.entriesFor('2026-09-15').first;
    expect(copied.title, '一碗饭');
    expect(copied.grams, 200);
    expect(copied.nutrition.calories, closeTo(e.nutrition.calories, 1e-9));
  });

  test('导入：数组混入非对象、未知枚举、缺 targets 都被拒绝', () async {
    final store = await freshStore({});
    final foodsBefore = store.foods.length;
    final cases = [
      // foods 数组混入字符串
      jsonEncode({
        'app': 'shiji',
        'schemaVersion': 2,
        'targets': {'kcal': 2000, 'protein': 150, 'carbs': 200, 'fat': 67},
        'foods': ['x'],
        'meals': [],
        'diary': [],
      }),
      // 未知枚举值
      jsonEncode({
        'app': 'shiji',
        'schemaVersion': 2,
        'targets': {'kcal': 2000, 'protein': 150, 'carbs': 200, 'fat': 67},
        'foods': [
          {
            'id': 'f1',
            'name': '鸡蛋',
            'emoji': '🥚',
            'protein': 0,
            'carbs': 0,
            'fat': 0,
            'servingGrams': 50,
          },
        ],
        'meals': [],
        'diary': [
          {
            'id': 'd1',
            'dateKey': '2026-09-15',
            'type': 'lunch',
            'source': 'food',
            'refId': 'f1',
            'status': 'weird',
            'grams': 50,
            'title': '鸡蛋',
            'emoji': '🥚',
            'protein': 0,
            'carbs': 0,
            'fat': 0,
            'items': [],
          },
        ],
      }),
      // 缺 targets
      jsonEncode({
        'app': 'shiji',
        'schemaVersion': 2,
        'foods': [],
        'meals': [],
        'diary': [],
      }),
    ];
    for (final bad in cases) {
      expect(await store.importJson(bad), isFalse, reason: bad);
      expect(store.foods.length, foodsBefore, reason: bad);
    }
  });

  test('导入成功会清除加载错误并标记已加载（灾难恢复）', () async {
    final source = await freshStore({});
    final backup = source.exportJson();

    final store = await freshStore({});
    store.loadError = '模拟加载失败';
    store.loaded = false;
    final ok = await store.importJson(backup);
    expect(ok, isTrue);
    expect(store.loaded, isTrue);
    expect(store.loadError, isNull);
    expect(store.foods.length, source.foods.length);
  });

  test('删除食材后 meals 列表与 mealById 索引一致', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(id: 'f1', name: '米饭（熟）', carbs: 28.2, servingGrams: 200),
    );
    await store.upsertMeal(
      MealTemplate(
        id: 'm1',
        name: '一碗饭',
        items: [MealComponent(foodId: 'f1', grams: 200)],
      ),
    );
    await store.removeFood('f1');
    final fromList = store.meals.firstWhere((m) => m.id == 'm1');
    final fromIndex = store.mealById('m1')!;
    expect(identical(fromList, fromIndex), isTrue);
    expect(fromIndex.items, isEmpty);
    // 配方清空后组合餐营养为 0，但历史记录不受影响
    expect(store.mealNutrition(fromIndex).calories, 0);
  });

  test('init 重复调用（重试）不会重复预置数据', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.init();
    await store.init();
    expect(store.foods.length, greaterThanOrEqualTo(20));
    expect(store.meals.length, 3);
    expect(store.diary, isEmpty);
  });

  test('copyDay：复制为计划、跳过项不复制、替换只清目标日计划', () async {
    final store = await freshStore({});
    await store.upsertFood(
      const Food(
        id: 'f1',
        name: '鸡蛋',
        protein: 13.3,
        carbs: 1.5,
        fat: 10,
        servingGrams: 50,
      ),
    );
    await store.addEntry(
      store.buildEntry(
        dateKey: '2026-09-14',
        type: MealType.breakfast,
        source: EntrySource.food,
        refId: 'f1',
        grams: 50,
        status: EntryStatus.consumed,
      ),
    );
    await store.addEntry(
      store.buildEntry(
        dateKey: '2026-09-14',
        type: MealType.lunch,
        source: EntrySource.food,
        refId: 'f1',
        grams: 100,
      ),
    );
    final skip = store.buildEntry(
      dateKey: '2026-09-14',
      type: MealType.snack,
      source: EntrySource.food,
      refId: 'f1',
      grams: 25,
    );
    await store.addEntry(skip);
    await store.setEntryStatus(skip.id, EntryStatus.skipped);

    final n = await store.copyDay('2026-09-14', '2026-09-15');
    expect(n, 2); // 跳过项不复制
    final copied = store.entriesFor('2026-09-15');
    expect(copied.length, 2);
    expect(copied.every((e) => e.status == EntryStatus.planned), isTrue);
    expect(copied.first.title, '鸡蛋');

    // 目标日已有计划 → replaceExisting 只清计划，且再复制 2 条
    final n2 = await store.copyDay(
      '2026-09-14',
      '2026-09-15',
      replaceExisting: true,
    );
    expect(n2, 2);
    expect(store.entriesFor('2026-09-15').length, 2);
    // 源日的数据原封不动
    expect(store.entriesFor('2026-09-14').length, 3);
  });

  test('导入：空对象、错误应用、未来版本都被拒绝且不改动数据', () async {
    final store = await freshStore({});
    final before = store.foods.length;
    final cases = [
      '{}',
      jsonEncode({
        'app': 'other',
        'schemaVersion': 2,
        'foods': [],
        'meals': [],
        'diary': [],
      }),
      jsonEncode({
        'app': 'shiji',
        'schemaVersion': 99,
        'foods': [],
        'meals': [],
        'diary': [],
      }),
    ];
    // 结构完整的空备份是合法的（用户明确恢复为空），只拒绝缺字段/错应用/未来版本
    for (final bad in cases) {
      expect(await store.importJson(bad), isFalse, reason: bad);
      expect(store.foods.length, before, reason: bad);
    }
  });

  test('导入：引用不存在食材的组合餐被拒绝', () async {
    final store = await freshStore({});
    final bad = jsonEncode({
      'app': 'shiji',
      'schemaVersion': 2,
      'targets': {'kcal': 2000, 'protein': 150, 'carbs': 200, 'fat': 67},
      'foods': [],
      'meals': [
        {
          'id': 'm1',
          'name': '坏配方',
          'items': [
            {'foodId': 'ghost', 'grams': 100},
          ],
        },
      ],
      'diary': [],
    });
    expect(await store.importJson(bad), isFalse);
    expect(store.meals, isNotEmpty); // 原有种子数据仍在
  });
}
