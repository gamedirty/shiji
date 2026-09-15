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
      const MealTemplate(
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
      const MealTemplate(
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
}
