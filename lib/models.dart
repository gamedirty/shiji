/// 数据模型 —— 三个维度从基础到上层：
/// 食材 Food（基础单位）→ 组合餐 MealTemplate（由多个食材组成）→ 饮食记录 DiaryEntry（某天某一餐的一条记录/计划）
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

  static MealType fromName(String? name) => MealType.values
      .firstWhere((t) => t.name == name, orElse: () => MealType.breakfast);

  /// 按当前时间猜一个默认餐段
  static MealType guessByTime(DateTime now) {
    final h = now.hour;
    if (h < 11) return MealType.breakfast;
    if (h < 16) return MealType.lunch;
    if (h < 21) return MealType.dinner;
    return MealType.snack;
  }
}

/// 三大营养素（克），热量按 4/4/9 千卡估算
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

/// 食材：营养按每 100g 记录；[servingGrams] 定义"一份"的克数。
/// 标准食材默认 100g；固定包装的商品可以把整包设为一份（例如 360g/盒）。
class Food {
  final String id;
  String name;
  String emoji;
  double protein; // g / 100g
  double carbs; // g / 100g
  double fat; // g / 100g
  double servingGrams; // 一份的克数

  Food({
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
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        emoji: (j['emoji'] as String?) ?? '🥗',
        protein: (j['protein'] as num?)?.toDouble() ?? 0,
        carbs: (j['carbs'] as num?)?.toDouble() ?? 0,
        fat: (j['fat'] as num?)?.toDouble() ?? 0,
        servingGrams: (j['servingGrams'] as num?)?.toDouble() ?? 100,
      );
}

/// 组合餐里一个食材的用量（按"份"计，一份 = food.servingGrams 克）
class MealComponent {
  final String foodId;
  double servings;

  MealComponent({required this.foodId, this.servings = 1});

  Map<String, dynamic> toJson() => {'foodId': foodId, 'servings': servings};

  factory MealComponent.fromJson(Map<String, dynamic> j) => MealComponent(
        foodId: j['foodId'] as String,
        servings: (j['servings'] as num?)?.toDouble() ?? 1,
      );
}

/// 组合餐：由多个食材组成的一餐模板
class MealTemplate {
  final String id;
  String name;
  String emoji;
  int prepMinutes;
  List<MealComponent> items;

  MealTemplate({
    required this.id,
    required this.name,
    this.emoji = '🍱',
    this.prepMinutes = 0,
    List<MealComponent>? items,
  }) : items = items ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'prepMinutes': prepMinutes,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory MealTemplate.fromJson(Map<String, dynamic> j) => MealTemplate(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        emoji: (j['emoji'] as String?) ?? '🍱',
        prepMinutes: (j['prepMinutes'] as num?)?.toInt() ?? 0,
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MealComponent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// 记录引用的来源：单个食材，或一个组合餐
enum EntrySource { food, meal }

extension EntrySourceX on EntrySource {
  static EntrySource fromName(String? name) => EntrySource.values
      .firstWhere((s) => s.name == name, orElse: () => EntrySource.food);
}

/// 饮食记录/计划：某一天、某个餐段的一条条目。
/// 未来日期的条目就是"计划"，勾选"已吃"即完成记录。
class DiaryEntry {
  final String id;
  final String dateKey; // yyyy-MM-dd
  final MealType type;
  final EntrySource source;
  final String refId; // foodId 或 mealId
  double servings; // 份数
  bool done; // 已吃

  DiaryEntry({
    required this.id,
    required this.dateKey,
    required this.type,
    required this.source,
    required this.refId,
    this.servings = 1,
    this.done = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateKey': dateKey,
        'type': type.name,
        'source': source.name,
        'refId': refId,
        'servings': servings,
        'done': done,
      };

  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
        id: j['id'] as String,
        dateKey: (j['dateKey'] as String?) ?? '',
        type: MealTypeX.fromName(j['type'] as String?),
        source: EntrySourceX.fromName(j['source'] as String?),
        refId: (j['refId'] as String?) ?? '',
        servings: (j['servings'] as num?)?.toDouble() ?? 1,
        done: (j['done'] as bool?) ?? false,
      );
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
