import 'dart:convert';

import '../models.dart';

/// 一次完整的可持久化应用状态（目标 + 食材 + 组合餐 + 饮食记录）
class AppStateData {
  final NutritionTargets targets;
  final List<Food> foods;
  final List<MealTemplate> meals;
  final List<DiaryEntry> diary;

  const AppStateData({
    required this.targets,
    required this.foods,
    required this.meals,
    required this.diary,
  });
}

/// 状态编解码 + 校验：
/// - v2：单键完整状态 JSON（原子读写，不再有分键写入的中间态）。
/// - v1：旧的三键 + 热量目标，读入时迁移（servings → 克数、done → 状态、生成快照）。
/// decode 用于读盘与导入，一律严格校验；非法数据抛 FormatException，绝不静默吞掉。
class AppStateCodec {
  static const appTag = 'shiji';
  static const schemaVersion = 2;

  static String encode(AppStateData s) => jsonEncode({
    'app': appTag,
    'schemaVersion': schemaVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'targets': s.targets.toJson(),
    'foods': s.foods.map((f) => f.toJson()).toList(),
    'meals': s.meals.map((m) => m.toJson()).toList(),
    'diary': s.diary.map((e) => e.toJson()).toList(),
  });

  /// 解析并校验 v2 状态/备份。任何结构问题都会抛 FormatException。
  static AppStateData decode(String raw) {
    final dynamic root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('不是有效的 JSON 文本');
    }
    if (root is! Map) throw const FormatException('备份根节点不是对象');
    final map = Map<String, dynamic>.from(root);
    if (map['app'] != appTag) throw const FormatException('不是食记的备份文件');
    final v = map['schemaVersion'];
    if (v is! int || v < 1 || v > schemaVersion) {
      throw const FormatException('不支持的备份版本');
    }

    final targets = map['targets'] is Map
        ? NutritionTargets.fromJson(
            Map<String, dynamic>.from(map['targets'] as Map),
          )
        : const NutritionTargets();

    final foods = _mapList(map, 'foods').map(Food.fromJson).toList();
    double servingOf(String id) => foods
        .firstWhere(
          (f) => f.id == id,
          orElse: () => const Food(id: '', name: ''),
        )
        .servingGrams;
    final meals = _mapList(
      map,
      'meals',
    ).map((j) => MealTemplate.fromJson(j, legacyServingOf: servingOf)).toList();
    Food? foodOf(String id) {
      for (final f in foods) {
        if (f.id == id) return f;
      }
      return null;
    }

    MealTemplate? mealOf(String id) {
      for (final m in meals) {
        if (m.id == id) return m;
      }
      return null;
    }

    final diary = _mapList(map, 'diary')
        .map((j) => DiaryEntry.fromJson(j, foodOf: foodOf, mealOf: mealOf))
        .toList();

    _validate(targets, foods, meals, diary, checkReferences: true);
    return AppStateData(
      targets: targets,
      foods: foods,
      meals: meals,
      diary: diary,
    );
  }

  /// 迁移 v1 旧存储（三个分键 + 热量目标）。旧数据只做宽松校验：
  /// 数值合法且 id 非空即可，缺引用的快照退化为空快照。
  static AppStateData decodeLegacy({
    required String? foodsJson,
    required String? mealsJson,
    required String? diaryJson,
    double? legacyKcalTarget,
  }) {
    final foods = _decodeList(foodsJson).map(Food.fromJson).toList();
    Food? foodOf(String id) {
      for (final f in foods) {
        if (f.id == id) return f;
      }
      return null;
    }

    double servingOf(String id) => foodOf(id)?.servingGrams ?? 100;
    final meals = _decodeList(mealsJson)
        .map((j) => MealTemplate.fromJson(j, legacyServingOf: servingOf))
        .toList();
    MealTemplate? mealOf(String id) {
      for (final m in meals) {
        if (m.id == id) return m;
      }
      return null;
    }

    final diary = _decodeList(diaryJson)
        .map((j) => DiaryEntry.fromJson(j, foodOf: foodOf, mealOf: mealOf))
        .toList();
    final targets = NutritionTargets(
      kcal: (legacyKcalTarget ?? 2000).clamp(100, 10000),
    );
    _validate(targets, foods, meals, diary, checkReferences: false);
    return AppStateData(
      targets: targets,
      foods: foods,
      meals: meals,
      diary: diary,
    );
  }

  // ---------- 内部：解析与校验 ----------

  static List<Map<String, dynamic>> _mapList(
    Map<String, dynamic> map,
    String key,
  ) {
    final v = map[key];
    if (v == null) throw FormatException('备份缺少 "$key"');
    if (v is! List) throw FormatException('"$key" 不是列表');
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static List<Map<String, dynamic>> _decodeList(String? s) => (s == null)
      ? []
      : (jsonDecode(s) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

  static void _validate(
    NutritionTargets targets,
    List<Food> foods,
    List<MealTemplate> meals,
    List<DiaryEntry> diary, {
    required bool checkReferences,
  }) {
    _checkUniqueIds(foods.map((f) => f.id), '食材');
    _checkUniqueIds(meals.map((m) => m.id), '组合餐');
    _checkUniqueIds(diary.map((e) => e.id), '饮食记录');

    if (!_finite(targets.kcal) || targets.kcal <= 0) {
      throw const FormatException('热量目标非法');
    }
    for (final t in [targets.protein, targets.carbs, targets.fat]) {
      if (!_finite(t) || t < 0) {
        throw const FormatException('目标数值非法');
      }
    }
    for (final f in foods) {
      if (!_finite(f.protein) ||
          !_finite(f.carbs) ||
          !_finite(f.fat) ||
          f.protein < 0 ||
          f.carbs < 0 ||
          f.fat < 0) {
        throw FormatException('食材「${f.name}」的营养数值非法');
      }
      if (!_finite(f.servingGrams) || f.servingGrams <= 0) {
        throw FormatException('食材「${f.name}」的一份克数非法');
      }
    }
    final foodIds = foods.map((f) => f.id).toSet();
    for (final m in meals) {
      for (final c in m.items) {
        if (!_finite(c.grams) || c.grams <= 0) {
          throw FormatException('组合餐「${m.name}」的用量非法');
        }
        if (checkReferences && !foodIds.contains(c.foodId)) {
          throw FormatException('组合餐「${m.name}」引用了不存在的食材');
        }
      }
    }
    for (final e in diary) {
      if (!_finite(e.grams) || e.grams < 0) {
        throw FormatException('记录「${e.title}」的克数非法');
      }
      final n = e.nutrition;
      if (!_finite(n.protein) ||
          !_finite(n.carbs) ||
          !_finite(n.fat) ||
          n.protein < 0 ||
          n.carbs < 0 ||
          n.fat < 0) {
        throw FormatException('记录「${e.title}」的营养数值非法');
      }
      if (e.dateKey.isEmpty) throw const FormatException('记录缺少日期');
    }
  }

  static void _checkUniqueIds(Iterable<String> ids, String what) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty) throw FormatException('$what缺少 ID');
      if (!seen.add(id)) throw FormatException('$what存在重复 ID：$id');
    }
  }

  static bool _finite(double v) => v.isFinite;
}
