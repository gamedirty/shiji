import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'app_state_codec.dart';
import 'seed.dart';

/// 全局状态：食材库 / 组合餐 / 每日计划与记录。
///
/// 持久化设计（第 2 轮评审后）：
/// - 全部状态序列化为**单个** JSON key（[AppStateCodec]），一次写入即整体生效，
///   不再有"食材写成功、日记没写"的中间态。
/// - 所有写命令经过串行队列（[_enqueue]），快速连续操作不会乱序写盘。
/// - 命令先计算新状态 → 写盘成功 → 才替换内存并通知 UI；写失败时内存保持原样，
///   并通过 [lastWriteError] 暴露给 UI 提示。
/// - 初始化先在局部解析并校验，成功后一次性替换；失败可重试且不会重复追加。
class AppStore extends ChangeNotifier {
  static const _kState = 'shiji.state';
  // v1 遗留键（只读用于迁移，迁移成功后清除）
  static const _kFoods = 'shiji.foods';
  static const _kMeals = 'shiji.meals';
  static const _kDiary = 'shiji.diary';
  static const _kLegacyTarget = 'shiji.kcalTarget';

  final List<Food> _foods = [];
  final List<MealTemplate> _meals = [];
  final List<DiaryEntry> _diary = [];
  final Map<String, Food> _foodById = {};
  final Map<String, MealTemplate> _mealById = {};
  NutritionTargets targets = const NutritionTargets(
    kcal: 2000,
    protein: 150,
    carbs: 200,
    fat: 67,
  );

  bool loaded = false;
  String? loadError;
  String? lastWriteError;
  late SharedPreferences _prefs;
  Future<void> _writeQueue = Future.value();

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

  // ---------- 初始化 ----------

  Future<void> init() async {
    loadError = null;
    try {
      _prefs = await SharedPreferences.getInstance();
      final AppStateData state;
      final stateJson = _prefs.getString(_kState);
      if (stateJson != null) {
        state = AppStateCodec.decode(stateJson);
      } else if (_prefs.getString(_kFoods) != null) {
        // v1 → v2 迁移（codec 内部会按食材/组合餐定义换算旧份数并生成快照）
        state = AppStateCodec.decodeLegacy(
          foodsJson: _prefs.getString(_kFoods),
          mealsJson: _prefs.getString(_kMeals),
          diaryJson: _prefs.getString(_kDiary),
          legacyKcalTarget: _prefs.getDouble(_kLegacyTarget),
        );
      } else {
        // 首次启动：只预置食材与组合餐，不伪造任何"已吃"记录
        state = AppStateData(
          targets: targets,
          foods: seedFoods(),
          meals: seedMeals(),
          diary: const [],
        );
      }
      _apply(state);
      await _writeState(state);
      // v1 键已并入单一状态键，清理遗留
      await _prefs.remove(_kFoods);
      await _prefs.remove(_kMeals);
      await _prefs.remove(_kDiary);
      await _prefs.remove(_kLegacyTarget);
      loaded = true;
    } catch (e) {
      loadError = e.toString();
    }
    notifyListeners();
  }

  void _apply(AppStateData s) {
    targets = s.targets;
    _foods
      ..clear()
      ..addAll(s.foods);
    _meals
      ..clear()
      ..addAll(s.meals);
    _diary
      ..clear()
      ..addAll(s.diary);
    _rebuildIndex();
  }

  void _rebuildIndex() {
    _foodById
      ..clear()
      ..addEntries(_foods.map((f) => MapEntry(f.id, f)));
    _mealById
      ..clear()
      ..addEntries(_meals.map((m) => MapEntry(m.id, m)));
  }

  // ---------- 持久化内核 ----------

  /// 串行执行写命令；快速连续操作按提交顺序落盘
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e) {
        lastWriteError = e.toString();
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<bool> _writeState(AppStateData state) async {
    try {
      return await _prefs.setString(_kState, AppStateCodec.encode(state));
    } catch (_) {
      return false;
    }
  }

  /// 计算 next state → 写盘 → 成功才发布（替换内存并通知）
  Future<bool> _commit({
    NutritionTargets? nextTargets,
    List<Food>? nextFoods,
    List<MealTemplate>? nextMeals,
    List<DiaryEntry>? nextDiary,
    String? failMessage,
  }) => _enqueue(() async {
    // 包装为副本：_apply 会先 clear 再 addAll，若直接传内部列表实例会清空数据
    final next = AppStateData(
      targets: nextTargets ?? targets,
      foods: List.of(nextFoods ?? _foods),
      meals: List.of(nextMeals ?? _meals),
      diary: List.of(nextDiary ?? _diary),
    );
    final ok = await _writeState(next);
    if (ok) {
      lastWriteError = null;
      _apply(next);
    } else {
      lastWriteError = failMessage ?? '数据写入失败，本次修改没有保存';
    }
    notifyListeners();
    return ok;
  });

  // ---------- 目标 ----------

  Future<bool> setTargets(NutritionTargets t) {
    final clamped = NutritionTargets(
      kcal: t.kcal.clamp(100, 10000),
      protein: t.protein.clamp(0, 1000),
      carbs: t.carbs.clamp(0, 2000),
      fat: t.fat.clamp(0, 1000),
    );
    return _commit(nextTargets: clamped, failMessage: '目标保存失败');
  }

  // ---------- 食材 ----------

  Future<bool> upsertFood(Food food) {
    final next = [..._foods];
    final i = next.indexWhere((f) => f.id == food.id);
    if (i >= 0) {
      next[i] = food;
    } else {
      next.add(food);
    }
    return _commit(nextFoods: next, failMessage: '食材保存失败');
  }

  /// 删除食材：从组合餐配方中移除引用（copyWith 替换，配方是不可变列表）；
  /// 历史记录是快照，不受影响。
  Future<bool> removeFood(String id) {
    final nextFoods = _foods.where((f) => f.id != id).toList();
    final nextMeals = _meals
        .map(
          (m) => m.items.any((c) => c.foodId == id)
              ? m.copyWith(items: m.items.where((c) => c.foodId != id).toList())
              : m,
        )
        .toList();
    return _commit(
      nextFoods: nextFoods,
      nextMeals: nextMeals,
      failMessage: '食材删除失败',
    );
  }

  // ---------- 组合餐 ----------

  Future<bool> upsertMeal(MealTemplate meal) {
    final next = [..._meals];
    final i = next.indexWhere((m) => m.id == meal.id);
    if (i >= 0) {
      next[i] = meal;
    } else {
      next.add(meal);
    }
    return _commit(nextMeals: next, failMessage: '组合餐保存失败');
  }

  /// 删除组合餐：历史记录是快照，不受影响
  Future<bool> removeMeal(String id) {
    final next = _meals.where((m) => m.id != id).toList();
    return _commit(nextMeals: next, failMessage: '组合餐删除失败');
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

  Future<bool> addEntry(DiaryEntry entry) =>
      _commit(nextDiary: [..._diary, entry], failMessage: '记录保存失败');

  /// 批量添加（计划复制等场景一次落盘）
  Future<bool> addEntries(List<DiaryEntry> entries) {
    if (entries.isEmpty) return Future.value(true);
    return _commit(nextDiary: [..._diary, ...entries], failMessage: '记录保存失败');
  }

  Future<bool> setEntryStatus(String entryId, EntryStatus status) {
    final i = _diary.indexWhere((e) => e.id == entryId);
    if (i < 0) return Future.value(true);
    final next = [..._diary];
    next[i] = next[i].copyWith(
      status: status,
      consumedAt: status == EntryStatus.consumed
          ? DateTime.now().toIso8601String()
          : null,
      clearConsumedAt: status != EntryStatus.consumed,
    );
    return _commit(nextDiary: next, failMessage: '状态修改失败');
  }

  /// 调整克数：**始终按比例缩放原快照**（营养、明细名、状态、consumedAt 不变）。
  /// 来源被改被删都不影响历史；克数非法或原记录无克数时拒绝。
  Future<bool> setEntryGrams(String entryId, double grams) {
    final i = _diary.indexWhere((e) => e.id == entryId);
    if (i < 0) return Future.value(true);
    final e = _diary[i];
    if (!grams.isFinite || grams <= 0 || e.grams <= 0) {
      lastWriteError = '这条记录无法调整克数';
      notifyListeners();
      return Future.value(false);
    }
    final ratio = grams / e.grams;
    final n = e.nutrition.times(ratio);
    final next = [..._diary];
    next[i] = e.copyWith(
      grams: grams,
      protein: n.protein,
      carbs: n.carbs,
      fat: n.fat,
      items: e.items
          .map((it) => EntryItem(name: it.name, grams: it.grams * ratio))
          .toList(),
    );
    return _commit(nextDiary: next, failMessage: '克数修改失败');
  }

  Future<bool> removeEntry(String entryId) {
    final next = _diary.where((e) => e.id != entryId).toList();
    return _commit(nextDiary: next, failMessage: '记录删除失败');
  }

  /// 复制某一天的饮食到另一天（全部转为计划，跳过项不复制）。
  /// 来源还存在时按当前定义生成新快照；已删除时原样复制历史快照。
  /// [replaceExisting] 为 true 时先移除目标日已有的计划（不动已吃/跳过）。
  /// 返回复制的条数；目标日本来就无可复制来源返回 0；写入失败返回 -1。
  Future<int> copyDay(
    String sourceKey,
    String targetKey, {
    bool replaceExisting = false,
  }) => _enqueue(() async {
    final source = _diary
        .where((e) => e.dateKey == sourceKey && e.status != EntryStatus.skipped)
        .toList();
    if (source.isEmpty) return 0;
    final kept = replaceExisting
        ? _diary
              .where(
                (e) =>
                    !(e.dateKey == targetKey &&
                        e.status == EntryStatus.planned),
              )
              .toList()
        : [..._diary];
    final copied = <DiaryEntry>[];
    for (final s in source) {
      final food = s.source == EntrySource.food ? foodById(s.refId) : null;
      final meal = s.source == EntrySource.meal ? mealById(s.refId) : null;
      if (food != null || meal != null) {
        var grams = s.grams;
        if (grams <= 0) {
          grams = food?.servingGrams ?? mealGrams(meal!);
        }
        copied.add(
          buildEntry(
            dateKey: targetKey,
            type: s.type,
            source: s.source,
            refId: s.refId,
            grams: grams,
          ),
        );
      } else {
        copied.add(
          s.copyWith(
            id: genId(),
            dateKey: targetKey,
            status: EntryStatus.planned,
            clearConsumedAt: true,
          ),
        );
      }
    }
    final nextState = AppStateData(
      targets: targets,
      foods: List.of(_foods),
      meals: List.of(_meals),
      diary: [...kept, ...copied],
    );
    final ok = await _writeState(nextState);
    if (ok) {
      lastWriteError = null;
      _apply(nextState);
    } else {
      lastWriteError = '复制失败，目标日期没有改动';
    }
    notifyListeners();
    return ok ? copied.length : -1;
  });

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

  String exportJson() => AppStateCodec.encode(
    AppStateData(targets: targets, foods: _foods, meals: _meals, diary: _diary),
  );

  /// 从备份恢复：先严格校验、写盘成功后才替换内存；失败返回 false 且不改动现有数据
  Future<bool> importJson(String raw) => _enqueue(() async {
    final AppStateData state;
    try {
      state = AppStateCodec.decode(raw);
    } on FormatException catch (e) {
      lastWriteError = '备份无法识别：${e.message}';
      return false;
    }
    final ok = await _writeState(state);
    if (ok) {
      lastWriteError = null;
      _apply(state);
    } else {
      lastWriteError = '备份写入失败，当前数据没有改动';
    }
    notifyListeners();
    return ok;
  });
}
