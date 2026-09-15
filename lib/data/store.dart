import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'app_state_codec.dart';
import 'seed.dart';

/// 业务校验拒绝：在 _mutate 的 transform 内抛出，终止本次修改并向 UI 提示
class MutationRejected implements Exception {
  final String message;
  const MutationRejected(this.message);
}

/// 全局状态：食材库 / 组合餐 / 每日计划与记录。
///
/// 持久化设计（第 2/3 轮评审后）：
/// - 全部状态序列化为**单个** JSON key（[AppStateCodec]），一次写入即整体生效。
/// - 所有写命令经过串行队列（[_enqueue]），并且**在队列内部读取当前状态、计算
///   下一状态**（[_mutate]）——快速连续操作不会互相覆盖丢更新。
/// - 命令写盘成功后才替换内存并通知 UI；写失败/被校验拒绝时内存保持原样，
///   并通过 [lastWriteError] 提示。
/// - 初始化先在局部解析并校验，成功后一次性替换；v1 迁移只有在新键写盘成功后
///   才清理旧键，失败时旧数据完整保留并提示重试。
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
      final stateJson = _prefs.getString(_kState);
      final legacyFoods = _prefs.getString(_kFoods);
      final legacyMeals = _prefs.getString(_kMeals);
      final legacyDiary = _prefs.getString(_kDiary);
      final hasLegacy =
          legacyFoods != null || legacyMeals != null || legacyDiary != null;

      if (stateJson != null) {
        _apply(AppStateCodec.decode(stateJson));
      } else if (hasLegacy) {
        // 任一旧键存在都进入 v1 → v2 迁移
        final migrated = AppStateCodec.decodeLegacy(
          foodsJson: legacyFoods,
          mealsJson: legacyMeals,
          diaryJson: legacyDiary,
          legacyKcalTarget: _prefs.getDouble(_kLegacyTarget),
        );
        // 写盘成功才切换并清理旧键；失败时旧数据原样保留，可重试
        if (!await _writeState(migrated)) {
          loadError = '数据迁移失败：写入未完成，原数据已保留，请重试';
          notifyListeners();
          return;
        }
        _apply(migrated);
        await _prefs.remove(_kFoods);
        await _prefs.remove(_kMeals);
        await _prefs.remove(_kDiary);
        await _prefs.remove(_kLegacyTarget);
      } else {
        // 首次启动：只预置食材与组合餐，不伪造任何"已吃"记录
        _apply(
          AppStateData(
            targets: targets,
            foods: seedFoods(),
            meals: seedMeals(),
            diary: const [],
          ),
        );
        await _writeState(_snapshotState());
      }
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

  /// 当前状态的副本（写入队列外只读展示用；写命令一律在队列内重新读取）
  AppStateData _snapshotState() => AppStateData(
    targets: targets,
    foods: List.of(_foods),
    meals: List.of(_meals),
    diary: List.of(_diary),
  );

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

  /// 修改命令统一入口：**在队列内部**读取当前状态 → transform 计算下一状态
  /// → 写盘 → 成功才发布。transform 抛 [MutationRejected] 表示业务校验拒绝。
  Future<bool> _mutate(
    AppStateData Function(AppStateData current) transform, {
    String? failMessage,
  }) => _enqueue(() async {
    final current = _snapshotState();
    final AppStateData next;
    try {
      next = transform(current);
    } on MutationRejected catch (e) {
      lastWriteError = e.message;
      notifyListeners();
      return false;
    }
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

  static AppStateData _stateWith(
    AppStateData s, {
    NutritionTargets? targets,
    List<Food>? foods,
    List<MealTemplate>? meals,
    List<DiaryEntry>? diary,
  }) => AppStateData(
    targets: targets ?? s.targets,
    foods: foods ?? s.foods,
    meals: meals ?? s.meals,
    diary: diary ?? s.diary,
  );

  // ---------- 目标 ----------

  Future<bool> setTargets(NutritionTargets t) => _mutate((current) {
    final clamped = NutritionTargets(
      kcal: t.kcal.clamp(100, 10000),
      protein: t.protein.clamp(0, 1000),
      carbs: t.carbs.clamp(0, 2000),
      fat: t.fat.clamp(0, 1000),
    );
    return _stateWith(current, targets: clamped);
  }, failMessage: '目标保存失败');

  // ---------- 食材 ----------

  Future<bool> upsertFood(Food food) => _mutate((current) {
    final foods = [...current.foods];
    final i = foods.indexWhere((f) => f.id == food.id);
    if (i >= 0) {
      foods[i] = food;
    } else {
      foods.add(food);
    }
    return _stateWith(current, foods: foods);
  }, failMessage: '食材保存失败');

  /// 删除食材：从组合餐配方中移除引用（copyWith 替换，配方是不可变列表）；
  /// 历史记录是快照，不受影响。配方被清空的组合餐保留（可在编辑页补回食材）。
  Future<bool> removeFood(String id) => _mutate((current) {
    final foods = current.foods.where((f) => f.id != id).toList();
    final meals = current.meals
        .map(
          (m) => m.items.any((c) => c.foodId == id)
              ? m.copyWith(items: m.items.where((c) => c.foodId != id).toList())
              : m,
        )
        .toList();
    return _stateWith(current, foods: foods, meals: meals);
  }, failMessage: '食材删除失败');

  // ---------- 组合餐 ----------

  Future<bool> upsertMeal(MealTemplate meal) => _mutate((current) {
    if (meal.items.isEmpty) {
      throw const MutationRejected('组合餐至少要包含一种食材');
    }
    final next = [...current.meals];
    final i = next.indexWhere((m) => m.id == meal.id);
    if (i >= 0) {
      next[i] = meal;
    } else {
      next.add(meal);
    }
    return _stateWith(current, meals: next);
  }, failMessage: '组合餐保存失败');

  /// 删除组合餐：历史记录是快照，不受影响
  Future<bool> removeMeal(String id) => _mutate((current) {
    final meals = current.meals.where((m) => m.id != id).toList();
    return _stateWith(current, meals: meals);
  }, failMessage: '组合餐删除失败');

  // ---------- 饮食记录 ----------

  /// 按当前食材库定义，为一个引用构建带快照的条目（创建记录的唯一入口）。
  /// 仅用于构建对象，持久化请走 [addEntry] / [addEntries]。
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
    } else if (meal != null && meal.items.isNotEmpty) {
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

  Future<bool> addEntry(DiaryEntry entry) => _mutate((current) {
    if (!entry.grams.isFinite || entry.grams <= 0) {
      throw const MutationRejected('记录克数必须大于 0');
    }
    return _stateWith(current, diary: [...current.diary, entry]);
  }, failMessage: '记录保存失败');

  /// 批量添加（计划复制等场景一次落盘）
  Future<bool> addEntries(List<DiaryEntry> entries) => _mutate((current) {
    for (final e in entries) {
      if (!e.grams.isFinite || e.grams <= 0) {
        throw const MutationRejected('记录克数必须大于 0');
      }
    }
    if (entries.isEmpty) return current;
    return _stateWith(current, diary: [...current.diary, ...entries]);
  }, failMessage: '记录保存失败');

  Future<bool> setEntryStatus(String entryId, EntryStatus status) =>
      _mutate((current) {
        final i = current.diary.indexWhere((e) => e.id == entryId);
        if (i < 0) return current;
        final diary = [...current.diary];
        diary[i] = diary[i].copyWith(
          status: status,
          consumedAt: status == EntryStatus.consumed
              ? DateTime.now().toIso8601String()
              : null,
          clearConsumedAt: status != EntryStatus.consumed,
        );
        return _stateWith(current, diary: diary);
      }, failMessage: '状态修改失败');

  /// 调整克数：**始终按比例缩放原快照**（营养、明细名、状态、consumedAt 不变）。
  /// 来源被改被删都不影响历史；克数非法或原记录无克数时拒绝。
  Future<bool> setEntryGrams(String entryId, double grams) =>
      _mutate((current) {
        final i = current.diary.indexWhere((e) => e.id == entryId);
        if (i < 0) return current;
        final e = current.diary[i];
        if (!grams.isFinite || grams <= 0 || e.grams <= 0) {
          throw const MutationRejected('这条记录无法调整克数');
        }
        final ratio = grams / e.grams;
        final n = e.nutrition.times(ratio);
        final diary = [...current.diary];
        diary[i] = e.copyWith(
          grams: grams,
          protein: n.protein,
          carbs: n.carbs,
          fat: n.fat,
          items: e.items
              .map((it) => EntryItem(name: it.name, grams: it.grams * ratio))
              .toList(),
        );
        return _stateWith(current, diary: diary);
      }, failMessage: '克数修改失败');

  Future<bool> removeEntry(String entryId) => _mutate((current) {
    final diary = current.diary.where((e) => e.id != entryId).toList();
    return _stateWith(current, diary: diary);
  }, failMessage: '记录删除失败');

  /// 复制某一天的饮食到另一天（全部转为计划，跳过项不复制）。
  /// 来源仍完整时按当前定义生成新快照；来源已删/配方已空/原克数非法时
  /// 原样复制历史快照。[replaceExisting] 只清目标日已有计划（不动已吃/跳过）。
  /// 返回复制的条数；无可复制来源返回 0；被拒绝或写入失败返回 -1。
  Future<int> copyDay(
    String sourceKey,
    String targetKey, {
    bool replaceExisting = false,
  }) => _enqueue(() async {
    if (sourceKey == targetKey) {
      lastWriteError = '源日期与目标日期相同';
      notifyListeners();
      return -1;
    }
    if (!_isValidDateKey(sourceKey) || !_isValidDateKey(targetKey)) {
      lastWriteError = '日期格式不正确';
      notifyListeners();
      return -1;
    }
    // 在队列内部读取状态，保证与其他写命令串行一致
    final current = _snapshotState();
    final source = current.diary
        .where((e) => e.dateKey == sourceKey && e.status != EntryStatus.skipped)
        .toList();
    if (source.isEmpty) return 0;
    final kept = replaceExisting
        ? current.diary
              .where(
                (e) =>
                    !(e.dateKey == targetKey &&
                        e.status == EntryStatus.planned),
              )
              .toList()
        : [...current.diary];
    final copied = <DiaryEntry>[];
    for (final s in source) {
      final food = s.source == EntrySource.food ? foodById(s.refId) : null;
      final meal = s.source == EntrySource.meal ? mealById(s.refId) : null;
      final canRebuild =
          s.grams > 0 &&
          (food != null || (meal != null && meal.items.isNotEmpty));
      if (canRebuild) {
        copied.add(
          buildEntry(
            dateKey: targetKey,
            type: s.type,
            source: s.source,
            refId: s.refId,
            grams: s.grams,
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
    final next = _stateWith(current, diary: [...kept, ...copied]);
    final ok = await _writeState(next);
    if (ok) {
      lastWriteError = null;
      _apply(next);
    } else {
      lastWriteError = '复制失败，目标日期没有改动';
    }
    notifyListeners();
    return ok ? copied.length : -1;
  });

  static bool _isValidDateKey(String key) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return false;
    return DateTime.tryParse(key) != null;
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

  String exportJson() => AppStateCodec.encode(_snapshotState());

  /// 从备份恢复：先严格校验、写盘成功后才替换内存；失败返回 false 且不改动现有数据。
  /// 恢复成功会清除加载错误并标记为已加载（灾难恢复入口可用）。
  Future<bool> importJson(String raw) => _enqueue(() async {
    final AppStateData state;
    try {
      state = AppStateCodec.decode(raw);
    } on FormatException catch (e) {
      lastWriteError = '备份无法识别：${e.message}';
      notifyListeners();
      return false;
    } catch (_) {
      lastWriteError = '备份无法识别';
      notifyListeners();
      return false;
    }
    final ok = await _writeState(state);
    if (ok) {
      lastWriteError = null;
      _apply(state);
      loaded = true;
      loadError = null;
    } else {
      lastWriteError = '备份写入失败，当前数据没有改动';
    }
    notifyListeners();
    return ok;
  });
}
