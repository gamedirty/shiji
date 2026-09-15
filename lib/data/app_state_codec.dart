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
///   [decode] 是**严格**解析：逐元素检查类型、必填字段不默认补齐、枚举必须命中、
///   校验真实日期与数值范围；任何结构问题都抛 FormatException，绝不静默吞掉。
/// - v1：旧的三键 + 热量目标，[decodeLegacy] 读入时迁移
///   （servings → 克数、done → 状态、生成快照），旧数据只做宽松校验。
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

  /// 解析并校验 v2 状态/备份。
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
    if (v is! int || v != schemaVersion) {
      throw const FormatException('不支持的备份版本');
    }

    final targets = _targetsFrom(map);
    final rawFoods = _reqList(map, 'foods');
    final foods = <Food>[];
    for (var i = 0; i < rawFoods.length; i++) {
      foods.add(_foodFrom(_reqMapAt(rawFoods, i, 'foods')));
    }
    final foodIds = _checkUnique(foods.map((f) => f.id), '食材');

    final rawMeals = _reqList(map, 'meals');
    final meals = <MealTemplate>[];
    for (var i = 0; i < rawMeals.length; i++) {
      meals.add(_mealFrom(_reqMapAt(rawMeals, i, 'meals'), foodIds));
    }
    _checkUnique(meals.map((m) => m.id), '组合餐');

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

    final rawDiary = _reqList(map, 'diary');
    final diary = <DiaryEntry>[];
    for (var i = 0; i < rawDiary.length; i++) {
      diary.add(_entryFrom(_reqMapAt(rawDiary, i, 'diary'), foodOf, mealOf));
    }
    _checkUnique(diary.map((e) => e.id), '饮食记录');

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
    return AppStateData(
      targets: targets,
      foods: foods,
      meals: meals,
      diary: diary,
    );
  }

  // ---------- v2 严格解析 ----------

  static NutritionTargets _targetsFrom(Map<String, dynamic> map) {
    final t = map['targets'];
    if (t is! Map) throw const FormatException('备份缺少 targets');
    final j = Map<String, dynamic>.from(t);
    return NutritionTargets(
      kcal: _num(j, 'kcal', '目标', positive: true),
      protein: _num(j, 'protein', '目标'),
      carbs: _num(j, 'carbs', '目标'),
      fat: _num(j, 'fat', '目标'),
    );
  }

  static Food _foodFrom(Map<String, dynamic> j) {
    final id = _id(j, '食材');
    final name = _str(j, 'name', '食材 $id');
    if (name.isEmpty) throw FormatException('食材 $id 缺少名称');
    return Food(
      id: id,
      name: name,
      emoji: _str(j, 'emoji', '食材 $id'),
      protein: _num(j, 'protein', '食材 $id'),
      carbs: _num(j, 'carbs', '食材 $id'),
      fat: _num(j, 'fat', '食材 $id'),
      servingGrams: _num(j, 'servingGrams', '食材 $id', positive: true),
    );
  }

  static MealTemplate _mealFrom(Map<String, dynamic> j, Set<String> foodIds) {
    final id = _id(j, '组合餐');
    final name = _str(j, 'name', '组合餐 $id');
    if (name.isEmpty) throw FormatException('组合餐 $id 缺少名称');
    final prep = j['prepMinutes'];
    if (prep is! int || prep < 0) {
      throw FormatException('组合餐 $id 的 prepMinutes 非法');
    }
    final rawItems = j['items'];
    if (rawItems is! List) throw FormatException('组合餐 $id 缺少 items');
    final items = <MealComponent>[];
    for (var i = 0; i < rawItems.length; i++) {
      final c = _reqMapAt(rawItems, i, '组合餐 $id 的 items');
      final foodId = c['foodId'];
      if (foodId is! String || foodId.isEmpty) {
        throw FormatException('组合餐 $id 的食材项缺少 foodId');
      }
      if (!foodIds.contains(foodId)) {
        throw FormatException('组合餐 $id 引用了不存在的食材 $foodId');
      }
      items.add(
        MealComponent(
          foodId: foodId,
          grams: _num(c, 'grams', '组合餐 $id 的食材项', positive: true),
        ),
      );
    }
    return MealTemplate(
      id: id,
      name: name,
      emoji: _str(j, 'emoji', '组合餐 $id'),
      prepMinutes: prep,
      items: items,
    );
  }

  static DiaryEntry _entryFrom(
    Map<String, dynamic> j,
    Food? Function(String) foodOf,
    MealTemplate? Function(String) mealOf,
  ) {
    final id = _id(j, '记录');
    final where = '记录 $id';
    final dateKey = _str(j, 'dateKey', where);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateKey) ||
        DateTime.tryParse(dateKey) == null) {
      throw FormatException('$where 的日期非法');
    }
    final type = _enum(j, 'type', where, {
      for (final t in MealType.values) t.name: t,
    });
    final source = _enum(j, 'source', where, {
      for (final s in EntrySource.values) s.name: s,
    });
    final status = _enum(j, 'status', where, {
      for (final s in EntryStatus.values) s.name: s,
    });
    final consumedAtRaw = j['consumedAt'];
    if (consumedAtRaw != null &&
        (consumedAtRaw is! String ||
            DateTime.tryParse(consumedAtRaw) == null)) {
      throw FormatException('$where 的 consumedAt 不是有效时间');
    }
    final rawItems = j['items'];
    if (rawItems is! List) throw FormatException('$where 缺少 items');
    final items = <EntryItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      final it = _reqMapAt(rawItems, i, '$where 的 items');
      final name = _str(it, 'name', '$where 明细 $i');
      if (name.isEmpty) throw FormatException('$where 明细缺少名称');
      items.add(
        EntryItem(name: name, grams: _num(it, 'grams', '$where 明细 $i')),
      );
    }
    return DiaryEntry(
      id: id,
      dateKey: dateKey,
      type: type,
      source: source,
      refId: _str(j, 'refId', where),
      status: status,
      grams: _num(j, 'grams', where),
      title: _str(j, 'title', where),
      emoji: _str(j, 'emoji', where),
      protein: _num(j, 'protein', where),
      carbs: _num(j, 'carbs', where),
      fat: _num(j, 'fat', where),
      items: items,
      consumedAt: consumedAtRaw as String?,
    );
  }

  // ---------- 类型工具：不满足即抛 FormatException ----------

  static List _reqList(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is! List) throw FormatException('备份缺少列表 "$key"');
    return v;
  }

  static Map<String, dynamic> _reqMapAt(List list, int i, String where) {
    final e = list[i];
    if (e is! Map) throw FormatException('$where 第 $i 项不是对象');
    return Map<String, dynamic>.from(e);
  }

  static String _id(Map<String, dynamic> j, String what) {
    final v = j['id'];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('$what缺少有效 ID');
  }

  static String _str(Map<String, dynamic> j, String key, String where) {
    final v = j[key];
    if (v is String) return v;
    throw FormatException('$where 缺少字符串 "$key"');
  }

  static double _num(
    Map<String, dynamic> j,
    String key,
    String where, {
    bool positive = false,
  }) {
    final v = j[key];
    if (v is! num) throw FormatException('$where 缺少数值 "$key"');
    final d = v.toDouble();
    if (!d.isFinite || d < 0 || (positive && d <= 0)) {
      throw FormatException('$where 的 "$key" 数值非法');
    }
    return d;
  }

  static T _enum<T>(
    Map<String, dynamic> j,
    String key,
    String where,
    Map<String, T> values,
  ) {
    final v = j[key];
    if (v is String) {
      final match = values[v];
      if (match != null) return match;
    }
    throw FormatException('$where 的 "$key" 取值非法');
  }

  static Set<String> _checkUnique(Iterable<String> ids, String what) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty) throw FormatException('$what缺少 ID');
      if (!seen.add(id)) throw FormatException('$what存在重复 ID：$id');
    }
    return seen;
  }

  static List<Map<String, dynamic>> _decodeList(String? s) => (s == null)
      ? []
      : (jsonDecode(s) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
}
