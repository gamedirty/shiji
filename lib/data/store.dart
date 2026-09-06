import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'seed.dart';

/// 全局状态：食材库 / 组合餐 / 每日记录，持久化到 SharedPreferences（JSON）
class AppStore extends ChangeNotifier {
  static const _kFoods = 'shiji.foods';
  static const _kMeals = 'shiji.meals';
  static const _kDiary = 'shiji.diary';

  final List<Food> _foods = [];
  final List<MealTemplate> _meals = [];
  final List<DiaryEntry> _diary = [];
  final Map<String, Food> _foodById = {};
  final Map<String, MealTemplate> _mealById = {};

  bool loaded = false;
  late SharedPreferences _prefs;

  List<Food> get foods => List.unmodifiable(_foods);
  List<MealTemplate> get meals => List.unmodifiable(_meals);
  List<DiaryEntry> get diary => List.unmodifiable(_diary);

  Food? foodById(String id) => _foodById[id];
  MealTemplate? mealById(String id) => _mealById[id];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final foodsJson = _prefs.getString(_kFoods);
    if (foodsJson == null) {
      _foods.addAll(seedFoods());
      _meals.addAll(seedMeals());
      _diary.addAll(seedDiary());
      _persistAll();
    } else {
      _foods.addAll(_decode(foodsJson).map(Food.fromJson));
      _meals.addAll(
          _decode(_prefs.getString(_kMeals)).map(MealTemplate.fromJson));
      _diary.addAll(
          _decode(_prefs.getString(_kDiary)).map(DiaryEntry.fromJson));
    }
    _rebuildIndex();
    loaded = true;
    notifyListeners();
  }

  static List<Map<String, dynamic>> _decode(String? s) => (s == null)
      ? []
      : (jsonDecode(s) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  void _rebuildIndex() {
    _foodById
      ..clear()
      ..addEntries(_foods.map((f) => MapEntry(f.id, f)));
    _mealById
      ..clear()
      ..addEntries(_meals.map((m) => MapEntry(m.id, m)));
  }

  void _persistAll() {
    _prefs.setString(_kFoods, jsonEncode(_foods.map((f) => f.toJson()).toList()));
    _prefs.setString(_kMeals, jsonEncode(_meals.map((m) => m.toJson()).toList()));
    _prefs.setString(_kDiary, jsonEncode(_diary.map((e) => e.toJson()).toList()));
  }

  void _persistFoods() =>
      _prefs.setString(_kFoods, jsonEncode(_foods.map((f) => f.toJson()).toList()));

  void _persistMeals() =>
      _prefs.setString(_kMeals, jsonEncode(_meals.map((m) => m.toJson()).toList()));

  void _persistDiary() =>
      _prefs.setString(_kDiary, jsonEncode(_diary.map((e) => e.toJson()).toList()));

  // ---------- 食材 ----------

  void upsertFood(Food food) {
    final i = _foods.indexWhere((f) => f.id == food.id);
    if (i >= 0) {
      _foods[i] = food;
    } else {
      _foods.add(food);
    }
    _foodById[food.id] = food;
    _persistFoods();
    notifyListeners();
  }

  /// 删除食材时同步清理组合餐与饮食记录里的引用
  void removeFood(String id) {
    _foods.removeWhere((f) => f.id == id);
    _foodById.remove(id);
    for (final m in _meals) {
      m.items.removeWhere((c) => c.foodId == id);
    }
    _diary.removeWhere((e) => e.source == EntrySource.food && e.refId == id);
    _persistAll();
    notifyListeners();
  }

  // ---------- 组合餐 ----------

  void upsertMeal(MealTemplate meal) {
    final i = _meals.indexWhere((m) => m.id == meal.id);
    if (i >= 0) {
      _meals[i] = meal;
    } else {
      _meals.add(meal);
    }
    _mealById[meal.id] = meal;
    _persistMeals();
    notifyListeners();
  }

  void removeMeal(String id) {
    _meals.removeWhere((m) => m.id == id);
    _mealById.remove(id);
    _diary.removeWhere((e) => e.source == EntrySource.meal && e.refId == id);
    _persistAll();
    notifyListeners();
  }

  // ---------- 饮食记录 ----------

  void addEntry(DiaryEntry entry) {
    _diary.add(entry);
    _persistDiary();
    notifyListeners();
  }

  void setServings(String entryId, double servings) {
    final e = _diary.where((e) => e.id == entryId).firstOrNull;
    if (e == null) return;
    e.servings = servings;
    _persistDiary();
    notifyListeners();
  }

  void setDone(String entryId, bool done) {
    final e = _diary.where((e) => e.id == entryId).firstOrNull;
    if (e == null) return;
    e.done = done;
    _persistDiary();
    notifyListeners();
  }

  void removeEntry(String entryId) {
    _diary.removeWhere((e) => e.id == entryId);
    _persistDiary();
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

  Nutrition totalsFor(String dateKey) {
    var n = const Nutrition();
    for (final e in _diary.where((e) => e.dateKey == dateKey)) {
      n += nutritionOf(e);
    }
    return n;
  }

  /// 一条记录的营养（按记录的份数）
  Nutrition nutritionOf(DiaryEntry e) {
    if (e.source == EntrySource.food) {
      final f = _foodById[e.refId];
      if (f == null) return const Nutrition();
      return f.forGrams(e.servings * f.servingGrams);
    }
    final m = _mealById[e.refId];
    if (m == null) return const Nutrition();
    return mealNutrition(m).times(e.servings);
  }

  /// 一条记录的总克数
  double gramsOf(DiaryEntry e) {
    if (e.source == EntrySource.food) {
      final f = _foodById[e.refId];
      return f == null ? 0 : e.servings * f.servingGrams;
    }
    final m = _mealById[e.refId];
    if (m == null) return 0;
    return e.servings * mealGrams(m);
  }

  String titleOf(DiaryEntry e) => titleOfRef(e.source, e.refId);

  String titleOfRef(EntrySource source, String refId) {
    if (source == EntrySource.food) return _foodById[refId]?.name ?? '（已删除的食材）';
    return _mealById[refId]?.name ?? '（已删除的组合餐）';
  }

  String emojiOf(DiaryEntry e) {
    if (e.source == EntrySource.food) return _foodById[e.refId]?.emoji ?? '❓';
    return _mealById[e.refId]?.emoji ?? '❓';
  }

  String subtitleOf(DiaryEntry e) {
    if (e.source == EntrySource.food) {
      final f = _foodById[e.refId];
      if (f == null) return '';
      return '${fmtNum(e.servings)} 份 · ${fmtNum(gramsOf(e))} g';
    }
    final m = _mealById[e.refId];
    if (m == null) return '';
    final names = m.items
        .map((c) => _foodById[c.foodId]?.name)
        .whereType<String>()
        .join(' · ');
    return '组合餐 · $names · ${fmtNum(e.servings)} 份';
  }

  /// 组合餐一整份（每种食材 ×1 份）的营养与克数
  Nutrition mealNutrition(MealTemplate m) {
    var n = const Nutrition();
    for (final c in m.items) {
      final f = _foodById[c.foodId];
      if (f != null) n += f.forGrams(c.servings * f.servingGrams);
    }
    return n;
  }

  double mealGrams(MealTemplate m) {
    var g = 0.0;
    for (final c in m.items) {
      final f = _foodById[c.foodId];
      if (f != null) g += c.servings * f.servingGrams;
    }
    return g;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
