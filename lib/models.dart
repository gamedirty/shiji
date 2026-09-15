/// 数据模型 —— 三个维度从基础到上层：
/// 食材 Food（基础单位）→ 组合餐 MealTemplate（由多个食材按克数组成）→ 饮食记录 DiaryEntry（某天某一餐的一条计划/记录）
///
/// 两条第一性原则：
/// 1. 计划是意图、摄入是事实：DiaryEntry.status 区分 planned/consumed/skipped，统计口径分开。
/// 2. 历史是快照：记录在创建时固化名称、克数与营养，之后修改/删除食材或组合餐都不回写历史。
///    持久化的基础量是克数，「一份」只是 UI 上的快捷输入（Food.servingGrams 不参与历史回算）。
library;

import 'dart:math';

/// 一天中的餐段
enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeX on MealType {
  String get label => switch (this) {
    MealType.breakfast => '早餐',
    MealType.lunch => '午餐',
    MealType.dinner => '晚餐',
    MealType.snack => '加餐',
  };

  String get emoji => switch (this) {
    MealType.breakfast => '🌅',
    MealType.lunch => '☀️',
    MealType.dinner => '🌙',
    MealType.snack => '🍎',
  };

  String get timeRange => switch (this) {
    MealType.breakfast => '06:00–11:00',
    MealType.lunch => '11:00–16:00',
    MealType.dinner => '16:00–21:00',
    MealType.snack => '21:00–06:00',
  };

  static MealType fromName(String? name) => MealType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => MealType.breakfast,
  );

  /// 按当前时间猜一个默认餐段（21:00–06:00 属于加餐，凌晨不再是早餐）
  static MealType guessByTime(DateTime now) {
    final h = now.hour;
    if (h >= 21 || h < 6) return MealType.snack;
    if (h < 11) return MealType.breakfast;
    if (h < 16) return MealType.lunch;
    return MealType.dinner;
  }
}

/// 三大营养素（克），热量按 4/4/9 千卡估算（估算值，标签热量后续可另存）
class Nutrition {
  final double protein;
  final double carbs;
  final double fat;

  const Nutrition({this.protein = 0, this.carbs = 0, this.fat = 0});

  double get calories => protein * 4 + carbs * 4 + fat * 9;

  Nutrition operator +(Nutrition o) => Nutrition(
    protein: protein + o.protein,
    carbs: carbs + o.carbs,
    fat: fat + o.fat,
  );

  Nutrition times(double f) =>
      Nutrition(protein: protein * f, carbs: carbs * f, fat: fat * f);
}

/// 每日营养目标：热量 + 三大营养素，健身用户四项都要看
class NutritionTargets {
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  const NutritionTargets({
    this.kcal = 2000,
    this.protein = 150,
    this.carbs = 200,
    this.fat = 67,
  });

  Nutrition get asNutrition =>
      Nutrition(protein: protein, carbs: carbs, fat: fat);

  Map<String, dynamic> toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
  };

  factory NutritionTargets.fromJson(Map<String, dynamic> j) => NutritionTargets(
    kcal: (j['kcal'] as num?)?.toDouble() ?? 2000,
    protein: (j['protein'] as num?)?.toDouble() ?? 150,
    carbs: (j['carbs'] as num?)?.toDouble() ?? 200,
    fat: (j['fat'] as num?)?.toDouble() ?? 67,
  );

  NutritionTargets copyWith({
    double? kcal,
    double? protein,
    double? carbs,
    double? fat,
  }) => NutritionTargets(
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    carbs: carbs ?? this.carbs,
    fat: fat ?? this.fat,
  );
}

/// 食材：营养按每 100g 记录；[servingGrams] 只是"一份"的快捷输入克数。
/// 标准食材默认 100g；固定包装的商品可以把整包设为一份（例如 360g/盒）。
class Food {
  final String id;
  final String name;
  final String emoji;
  final double protein; // g / 100g
  final double carbs; // g / 100g
  final double fat; // g / 100g
  final double servingGrams; // 一份的快捷克数（仅用于输入，不参与历史回算）

  const Food({
    required this.id,
    required this.name,
    this.emoji = '🥗',
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.servingGrams = 100,
  });

  Nutrition get per100 => Nutrition(protein: protein, carbs: carbs, fat: fat);

  Nutrition forGrams(double grams) => per100.times(grams / 100);

  double get kcalPer100 => per100.calories;

  Food copyWith({
    String? id,
    String? name,
    String? emoji,
    double? protein,
    double? carbs,
    double? fat,
    double? servingGrams,
  }) => Food(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    protein: protein ?? this.protein,
    carbs: carbs ?? this.carbs,
    fat: fat ?? this.fat,
    servingGrams: servingGrams ?? this.servingGrams,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'servingGrams': servingGrams,
  };

  factory Food.fromJson(Map<String, dynamic> j) => Food(
    id: (j['id'] as String?) ?? genId(),
    name: (j['name'] as String?) ?? '',
    emoji: (j['emoji'] as String?) ?? '🥗',
    protein: (j['protein'] as num?)?.toDouble() ?? 0,
    carbs: (j['carbs'] as num?)?.toDouble() ?? 0,
    fat: (j['fat'] as num?)?.toDouble() ?? 0,
    servingGrams: (j['servingGrams'] as num?)?.toDouble() ?? 100,
  );
}

/// 组合餐里一个食材的用量：持久化绝对克数（改食材的"一份"克数不会改变配方）
class MealComponent {
  final String foodId;
  final double grams;

  const MealComponent({required this.foodId, this.grams = 100});

  MealComponent copyWith({String? foodId, double? grams}) =>
      MealComponent(foodId: foodId ?? this.foodId, grams: grams ?? this.grams);

  Map<String, dynamic> toJson() => {'foodId': foodId, 'grams': grams};

  /// 兼容 v1 旧数据：没有 grams 时按"份数 × 该食材一份克数"换算
  factory MealComponent.fromJson(
    Map<String, dynamic> j, {
    double Function(String foodId)? legacyServingOf,
  }) {
    final foodId = (j['foodId'] as String?) ?? '';
    final grams = (j['grams'] as num?)?.toDouble();
    if (grams != null) return MealComponent(foodId: foodId, grams: grams);
    final servings = (j['servings'] as num?)?.toDouble() ?? 1;
    final serving = legacyServingOf?.call(foodId) ?? 100;
    return MealComponent(foodId: foodId, grams: servings * serving);
  }
}

/// 组合餐：由多个食材按克数组成的一餐模板
class MealTemplate {
  final String id;
  final String name;
  final String emoji;
  final int prepMinutes;
  final List<MealComponent> items;

  const MealTemplate({
    required this.id,
    required this.name,
    this.emoji = '🍱',
    this.prepMinutes = 0,
    this.items = const [],
  });

  MealTemplate copyWith({
    String? id,
    String? name,
    String? emoji,
    int? prepMinutes,
    List<MealComponent>? items,
  }) => MealTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    items: items ?? this.items,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'prepMinutes': prepMinutes,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory MealTemplate.fromJson(
    Map<String, dynamic> j, {
    double Function(String foodId)? legacyServingOf,
  }) => MealTemplate(
    id: (j['id'] as String?) ?? genId(),
    name: (j['name'] as String?) ?? '',
    emoji: (j['emoji'] as String?) ?? '🍱',
    prepMinutes: (j['prepMinutes'] as num?)?.toInt() ?? 0,
    items: ((j['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (e) => MealComponent.fromJson(
            Map<String, dynamic>.from(e),
            legacyServingOf: legacyServingOf,
          ),
        )
        .toList(),
  );
}

/// 记录引用的来源：单个食材，或一个组合餐
enum EntrySource { food, meal }

extension EntrySourceX on EntrySource {
  static EntrySource fromName(String? name) => EntrySource.values.firstWhere(
    (s) => s.name == name,
    orElse: () => EntrySource.food,
  );
}

/// 条目状态：计划是意图、已吃是事实、跳过是明确决定
enum EntryStatus { planned, consumed, skipped }

extension EntryStatusX on EntryStatus {
  String get label => switch (this) {
    EntryStatus.planned => '计划',
    EntryStatus.consumed => '已吃',
    EntryStatus.skipped => '跳过',
  };

  static EntryStatus fromName(String? name, {bool legacyDone = false}) =>
      switch (name) {
        'consumed' => EntryStatus.consumed,
        'skipped' => EntryStatus.skipped,
        'planned' => EntryStatus.planned,
        _ => legacyDone ? EntryStatus.consumed : EntryStatus.planned,
      };
}

/// 快照里的一个组成项：记录生成时的食材名与克数
class EntryItem {
  final String name;
  final double grams;

  const EntryItem({required this.name, required this.grams});

  Map<String, dynamic> toJson() => {'name': name, 'grams': grams};

  factory EntryItem.fromJson(Map<String, dynamic> j) => EntryItem(
    name: (j['name'] as String?) ?? '',
    grams: (j['grams'] as num?)?.toDouble() ?? 0,
  );
}

/// 饮食记录/计划：某一天、某个餐段的一条条目。
/// 创建时固化 [title] [emoji] [grams] 与营养快照；[refId] 仅作来源追踪，删除来源不影响历史。
class DiaryEntry {
  final String id;
  final String dateKey; // yyyy-MM-dd
  final MealType type;
  final EntrySource source;
  final String refId; // 来源 foodId / mealId（仅追踪，可失效）
  final EntryStatus status;
  final double grams; // 实际克数
  final String title; // 快照名
  final String emoji; // 快照图标
  final double protein; // 快照营养（整条，克）
  final double carbs;
  final double fat;
  final List<EntryItem> items; // 组合餐明细快照
  final String? consumedAt; // 标记已吃的时间（ISO8601）

  const DiaryEntry({
    required this.id,
    required this.dateKey,
    required this.type,
    required this.source,
    required this.refId,
    this.status = EntryStatus.planned,
    this.grams = 0,
    this.title = '',
    this.emoji = '🍽️',
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.items = const [],
    this.consumedAt,
  });

  Nutrition get nutrition =>
      Nutrition(protein: protein, carbs: carbs, fat: fat);

  DiaryEntry copyWith({
    String? id,
    String? dateKey,
    MealType? type,
    EntrySource? source,
    String? refId,
    EntryStatus? status,
    double? grams,
    String? title,
    String? emoji,
    double? protein,
    double? carbs,
    double? fat,
    List<EntryItem>? items,
    String? consumedAt,
    bool clearConsumedAt = false,
  }) => DiaryEntry(
    id: id ?? this.id,
    dateKey: dateKey ?? this.dateKey,
    type: type ?? this.type,
    source: source ?? this.source,
    refId: refId ?? this.refId,
    status: status ?? this.status,
    grams: grams ?? this.grams,
    title: title ?? this.title,
    emoji: emoji ?? this.emoji,
    protein: protein ?? this.protein,
    carbs: carbs ?? this.carbs,
    fat: fat ?? this.fat,
    items: items ?? this.items,
    consumedAt: clearConsumedAt ? null : (consumedAt ?? this.consumedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'dateKey': dateKey,
    'type': type.name,
    'source': source.name,
    'refId': refId,
    'status': status.name,
    'grams': grams,
    'title': title,
    'emoji': emoji,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'items': items.map((e) => e.toJson()).toList(),
    if (consumedAt != null) 'consumedAt': consumedAt,
  };

  /// 兼容 v1 旧数据：只存 source/refId/servings/done 时，用当前食材库换算出快照。
  /// 来源已被删除时退化为空快照（历史无法恢复，但不崩溃）。
  factory DiaryEntry.fromJson(
    Map<String, dynamic> j, {
    Food? Function(String foodId)? foodOf,
    MealTemplate? Function(String mealId)? mealOf,
  }) {
    final id = (j['id'] as String?) ?? genId();
    final dateKey = (j['dateKey'] as String?) ?? '';
    final type = MealTypeX.fromName(j['type'] as String?);
    final source = EntrySourceX.fromName(j['source'] as String?);
    final refId = (j['refId'] as String?) ?? '';
    final status = EntryStatusX.fromName(
      j['status'] as String?,
      legacyDone: (j['done'] as bool?) ?? false,
    );

    double? grams = (j['grams'] as num?)?.toDouble();
    double? protein = (j['protein'] as num?)?.toDouble();
    double? carbs = (j['carbs'] as num?)?.toDouble();
    double? fat = (j['fat'] as num?)?.toDouble();
    final hasSnapshot = grams != null && protein != null;
    if (hasSnapshot) {
      return DiaryEntry(
        id: id,
        dateKey: dateKey,
        type: type,
        source: source,
        refId: refId,
        status: status,
        grams: grams,
        title: (j['title'] as String?) ?? '',
        emoji: (j['emoji'] as String?) ?? '🍽️',
        protein: protein,
        carbs: carbs ?? 0,
        fat: fat ?? 0,
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EntryItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        consumedAt: j['consumedAt'] as String?,
      );
    }

    // v1 迁移：份 × 一份克数 → 克数，并按当前定义算一次营养快照
    final servings = (j['servings'] as num?)?.toDouble() ?? 1;
    final food = foodOf?.call(refId);
    final meal = mealOf?.call(refId);
    final title = food?.name ?? meal?.name ?? '';
    final emoji = food?.emoji ?? meal?.emoji ?? '🍽️';
    var n = const Nutrition();
    final items = <EntryItem>[];
    if (food != null) {
      grams = servings * food.servingGrams;
      n = food.forGrams(grams);
      items.add(EntryItem(name: food.name, grams: grams));
    } else if (meal != null) {
      var full = 0.0;
      var calc = const Nutrition();
      for (final c in meal.items) {
        final f = foodOf?.call(c.foodId);
        if (f == null) continue;
        full += c.grams;
        calc += f.forGrams(c.grams);
        items.add(EntryItem(name: f.name, grams: c.grams * servings));
      }
      grams = full * servings;
      n = calc.times(servings);
    } else {
      grams = 0;
    }
    return DiaryEntry(
      id: id,
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
      consumedAt: j['consumedAt'] as String?,
    );
  }
}

String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String genId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    (Random().nextInt(0x10000)).toRadixString(36).padLeft(4, '0');

/// 数字显示：整数不带小数点，其余保留 1 位
String fmtNum(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

const kWeekdayShort = ['一', '二', '三', '四', '五', '六', '日']; // 周一起始

String weekdayLabel(DateTime d) =>
    '周${kWeekdayShort[d.weekday - 1]}'; // DateTime.weekday: 周一=1
