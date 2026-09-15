import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'seed.dart';

/// 全局状态：食材库 / 组合餐 / 每日计划与记录，持久化到 SharedPreferences（JSON）。
/// 所有写入都 await 落盘结果；初始化失败时暴露 [loadError]，由 UI 呈现重试入口。
class AppStore extends ChangeNotifier {
  static const _kFoods = 'shiji.foods';
  static const _kMeals = 'shiji.meals';
  static const _kDiary = 'shiji.diary';
  static const _kTargets = 'shiji.targets';
  static const _kLegacyTarget = 'shiji.kcalTarget';
  static const schemaVersion = 2;

  NutritionTargets targets = const NutritionTargets(
    kcal: 2000,
    protein: 150,
    carbs: 200,
    fat: 67,
  );

  final List<Food> _foods = [];
  final List<MealTemplate> _meals = [];
  final List<DiaryEntry> _diary = [];
  final Map<String, Food> _foodById = {};
  final Map<String, MealTemplate> _mealById = {};

  bool loaded = false;
  String? loadError;
  late SharedPreferences _prefs;
  bool _initializing = false;

  List<Food> get foods => List.unmodifiable(_foods);
  List<MealTemplate> get meals => List.unmodifiable(_meals);
  List<DiaryEntry> get diary => List.unmodifiable(_diary);

  Food? foodById(String id) => _foodById[id];
  MealTemplate? mealById(String id) => _mealById[id];

  /// 来源当前的显示名（仅用于选择/展示，不代表历史快照）
  String titleOfRef(EntrySource source, String refId) {
    if (source == EntrySource.food) {
      return _foodById[refId]?.name ?? '（已删除的食材）';
    }
    return _mealById[refId]?.name ?? '（已删除的组合餐）';
  }

  Future<void> init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      final foodsJson = _prefs.getString(_kFoods);
      double servingOf(String id) => _foods
          .firstWhere(
            (f) => f.id == id,
            orElse: () => const Food(id: '', name: ''),
          )
          .servingGrams;
      if (foodsJson == null) {
        // 首次启动：只预置食材与组合餐，不伪造任何"已吃"记录
        _foods.addAll(seedFoods());
        _meals.addAll(seedMeals());
      } else {
        _foods.addAll(_decode(foodsJson).map(Food.fromJson));
        _meals.addAll(
          _decode(_prefs.getString(_kMeals))
              .map((j) => MealTemplate.fromJson(j, legacyServingOf: servingOf)),
        );
      }
      _rebuildIndex(); // 日记旧数据迁移需要按 id 查找来源
      _diary
        ..clear()
        ..addAll(
          _decode(_prefs.getString(_kDiary)).map(
            (j) => DiaryEntry.fromJson(j, foodOf: foodById, mealOf: mealById),
          ),
        );

      // 目标迁移：旧版只有热量目标，宏量营养素按默认比例补齐
      final targetsJson = _prefs.getString(_kTargets);
      if (targetsJson != null) {
        targets = NutritionTargets.fromJson(
          Map<String, dynamic>.from(_decodeMap(targetsJson)),
        );
      } else {
        final legacyKcal = _prefs.getDouble(_kLegacyTarget);
        if (legacyKcal != null) {
          targets = targets.copyWith(kcal: legacyKcal.clamp(500, 10000));
        }
      }

      _rebuildIndex();
      await _persistAll();
      loaded = true;
      loadError = null;
    } catch (e) {
      loadError = e.toString();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  static List<Map<String, dynamic>> _decode(String? s) => (s == null)
      ? []
      : (jsonDecode(s) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

  static Map<String, dynamic> _decodeMap(String s) =>
      Map<String, dynamic>.from(jsonDecode(s) as Map);

  void _rebuildIndex() {
    _foodById
      ..clear()
      ..addEntries(_foods.map((f) => MapEntry(f.id, f)));
    _mealById
      ..clear()
      ..addEntries(_meals.map((m) => MapEntry(m.id, m)));
  }

  Future<void> _persistAll() async {
    await _prefs.setString(
      _kFoods,
      jsonEncode(_foods.map((f) => f.toJson()).toList()),
    );
    await _prefs.setString(
      _kMeals,
      jsonEncode(_meals.map((m) => m.toJson()).toList()),
    );
    await _prefs.setString(
      _kDiary,
      jsonEncode(_diary.map((e) => e.toJson()).toList()),
    );
    await _prefs.setString(_kTargets, jsonEncode(targets.toJson()));
    await _prefs.remove(_kLegacyTarget);
  }

  Future<void> _persistFoods() => _prefs.setString(
    _kFoods,
    jsonEncode(_foods.map((f) => f.toJson()).toList()),
  );

  Future<void> _persistMeals() => _prefs.setString(
    _kMeals,
    jsonEncode(_meals.map((m) => m.toJson()).toList()),
  );

  Future<void> _persistDiary() => _prefs.setString(
    _kDiary,
    jsonEncode(_diary.map((e) => e.toJson()).toList()),
  );

  // ---------- 目标 ----------

  Future<void> setTargets(NutritionTargets t) async {
    targets = NutritionTargets(
      kcal: t.kcal.clamp(100, 10000),
      protein: t.protein.clamp(0, 1000),
      carbs: t.carbs.clamp(0, 2000),
      fat: t.fat.clamp(0, 1000),
    );
    await _prefs.setString(_kTargets, jsonEncode(targets.toJson()));
    notifyListeners();
  }

  // ---------- 食材 ----------

  Future<void> upsertFood(Food food) async {
    final i = _foods.indexWhere((f) => f.id == food.id);
    if (i >= 0) {
      _foods[i] = food;
    } else {
      _foods.add(food);
    }
    _foodById[food.id] = food;
    await _persistFoods();
    notifyListeners();
  }

  /// 删除食材：从组合餐配方中移除引用（copyWith 替换，配方可能是不可变列表）；历史记录是快照，不受影响
  Future<void> removeFood(String id) async {
    _foods.removeWhere((f) => f.id == id);
    _foodById.remove(id);
    var mealsChanged = false;
    for (var i = 0; i < _meals.length; i++) {
      final m = _meals[i];
      if (m.items.any((c) => c.foodId == id)) {
        _meals[i] = m.copyWith(
          items: m.items.where((c) => c.foodId != id).toList(),
        );
        mealsChanged = true;
      }
    }
    await _persistFoods();
    if (mealsChanged) {
      await _persistMeals();
    }
    notifyListeners();
  }

  // ---------- 组合餐 ----------

  Future<void> upsertMeal(MealTemplate meal) async {
    final i = _meals.indexWhere((m) => m.id == meal.id);
    if (i >= 0) {
      _meals[i] = meal;
    } else {
      _meals.add(meal);
    }
    _mealById[meal.id] = meal;
    await _persistMeals();
    notifyListeners();
  }

  /// 删除组合餐：历史记录是快照，不受影响
  Future<void> removeMeal(String id) async {
    _meals.removeWhere((m) => m.id == id);
    _mealById.remove(id);
    await _persistMeals();
    notifyListeners();
  }

  // ---------- 饮食记录 ----------

  /// 按当前食材库定义，为一个引用构建带快照的条目（创建记录的唯一入口）
  DiaryEntry buildEntry({
    required String dateKey,
    required MealType type,
    required EntrySource source,
    required String refId,
    required double grams,
    EntryStatus status = EntryStatus.planned,
  }) {
    final food = source == EntrySource.food ? foodById(refId) : null;
    final meal = source == EntrySource.meal ? mealById(refId) : null;
    final title = food?.name ?? meal?.name ?? '';
    final emoji = food?.emoji ?? meal?.emoji ?? '🍽️';
    var n = const Nutrition();
    final items = <EntryItem>[];
    if (food != null) {
      n = food.forGrams(grams);
      items.add(EntryItem(name: food.name, grams: grams));
    } else if (meal != null) {
      final full = mealGrams(meal);
      final ratio = full > 0 ? grams / full : 0.0;
      n = mealNutrition(meal).times(ratio);
      for (final c in meal.items) {
        final f = foodById(c.foodId);
        if (f != null) {
          items.add(EntryItem(name: f.name, grams: c.grams * ratio));
        }
      }
    }
    return DiaryEntry(
      id: genId(),
      dateKey: dateKey,
      type: type,
      source: source,
      refId: refId,
      status: status,
      grams: grams,
      title: title,
      emoji: emoji,
      protein: n.protein,
      carbs: n.carbs,
      fat: n.fat,
      items: items,
      consumedAt: status == EntryStatus.consumed
          ? DateTime.now().toIso8601String()
          : null,
    );
  }

  Future<void> addEntry(DiaryEntry entry) async {
    _diary.add(entry);
    await _persistDiary();
    notifyListeners();
  }

  Future<void> setEntryStatus(String entryId, EntryStatus status) async {
    final i = _diary.indexWhere((e) => e.id == entryId);
    if (i < 0) return;
    _diary[i] = _diary[i].copyWith(
      status: status,
      consumedAt: status == EntryStatus.consumed
          ? DateTime.now().toIso8601String()
          : null,
      clearConsumedAt: status != EntryStatus.consumed,
    );
    await _persistDiary();
    notifyListeners();
  }

  /// 调整克数：来源还在就按当前定义重算营养；来源已删则按比例缩放快照
  Future<void> setEntryGrams(String entryId, double grams) async {
    if (grams <= 0) return;
    final i = _diary.indexWhere((e) => e.id == entryId);
    if (i < 0) return;
    final e = _diary[i];
    final food = e.source == EntrySource.food ? foodById(e.refId) : null;
    final meal = e.source == EntrySource.meal ? mealById(e.refId) : null;
    if (food != null || meal != null) {
      _diary[i] = buildEntry(
        dateKey: e.dateKey,
        type: e.type,
        source: e.source,
        refId: e.refId,
        grams: grams,
        status: e.status,
      ).copyWith(id: e.id, consumedAt: e.consumedAt);
    } else {
      final ratio = e.grams > 0 ? grams / e.grams : 1.0;
      final n = e.nutrition.times(ratio);
      _diary[i] = e.copyWith(
        grams: grams,
        protein: n.protein,
        carbs: n.carbs,
        fat: n.fat,
        items: e.items
            .map((it) => EntryItem(name: it.name, grams: it.grams * ratio))
            .toList(),
      );
    }
    await _persistDiary();
    notifyListeners();
  }

  Future<void> removeEntry(String entryId) async {
    _diary.removeWhere((e) => e.id == entryId);
    await _persistDiary();
    notifyListeners();
  }

  // ---------- 查询 / 计算 ----------

  List<DiaryEntry> entriesFor(String dateKey, [MealType? type]) {
    final list = _diary
        .where((e) => e.dateKey == dateKey && (type == null || e.type == type))
        .toList();
    list.sort((a, b) {
      final c = a.type.index.compareTo(b.type.index);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return List.unmodifiable(list);
  }

  Nutrition _sumWhere(String dateKey, bool Function(EntryStatus) pred) {
    var n = const Nutrition();
    for (final e in _diary.where(
      (e) => e.dateKey == dateKey && pred(e.status),
    )) {
      n += e.nutrition;
    }
    return n;
  }

  /// 已摄入（事实口径）
  Nutrition consumedTotalsFor(String dateKey) =>
      _sumWhere(dateKey, (s) => s == EntryStatus.consumed);

  /// 尚未吃的计划（意图口径）
  Nutrition plannedTotalsFor(String dateKey) =>
      _sumWhere(dateKey, (s) => s == EntryStatus.planned);

  /// 组合餐一整份的营养与克数（模板按当前配方计算）
  Nutrition mealNutrition(MealTemplate m) {
    var n = const Nutrition();
    for (final c in m.items) {
      final f = _foodById[c.foodId];
      if (f != null) n += f.forGrams(c.grams);
    }
    return n;
  }

  double mealGrams(MealTemplate m) {
    var g = 0.0;
    for (final c in m.items) {
      g += c.grams;
    }
    return g;
  }

  // ---------- 备份 / 恢复 ----------

  String exportJson() => jsonEncode({
    'app': 'shiji',
    'schemaVersion': schemaVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'targets': targets.toJson(),
    'foods': _foods.map((f) => f.toJson()).toList(),
    'meals': _meals.map((m) => m.toJson()).toList(),
    'diary': _diary.map((e) => e.toJson()).toList(),
  });

  /// 从备份 JSON 恢复；成功返回 true，数据非法返回 false（不改动现有数据）
  Future<bool> importJson(String raw) async {
    try {
      final root = jsonDecode(raw);
      if (root is! Map) return false;
      final map = Map<String, dynamic>.from(root);
      final foods = _decode(jsonEncode(map['foods'] ?? []))
          .map(Food.fromJson)
          .toList();
      double servingOf(String id) => foods
          .firstWhere(
            (f) => f.id == id,
            orElse: () => const Food(id: '', name: ''),
          )
          .servingGrams;
      final meals = _decode(jsonEncode(map['meals'] ?? []))
          .map((j) => MealTemplate.fromJson(j, legacyServingOf: servingOf))
          .toList();

      Food? foodIn(String id) {
        for (final f in foods) {
          if (f.id == id) return f;
        }
        return null;
      }

      MealTemplate? mealIn(String id) {
        for (final m in meals) {
          if (m.id == id) return m;
        }
        return null;
      }

      final diary = _decode(jsonEncode(map['diary'] ?? []))
          .map((j) => DiaryEntry.fromJson(j, foodOf: foodIn, mealOf: mealIn))
          .toList();
      final t = map['targets'];
      final newTargets = t is Map
          ? NutritionTargets.fromJson(Map<String, dynamic>.from(t))
          : targets;

      _foods
        ..clear()
        ..addAll(foods);
      _meals
        ..clear()
        ..addAll(meals);
      _diary
        ..clear()
        ..addAll(diary);
      targets = newTargets;
      _rebuildIndex();
      await _persistAll();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
