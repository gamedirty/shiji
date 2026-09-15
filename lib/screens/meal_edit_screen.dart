import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// 新建 / 编辑组合餐：一餐 = 多个食材按克数组合（「份」只是输入时的快捷换算）
class MealEditScreen extends StatefulWidget {
  final MealTemplate? meal;

  const MealEditScreen({super.key, this.meal});

  @override
  State<MealEditScreen> createState() => _MealEditScreenState();
}

class _MealEditScreenState extends State<MealEditScreen> {
  static const _emojis = [
    '🍱',
    '🥗',
    '🍲',
    '🥪',
    '🍚',
    '🍜',
    '🥣',
    '🥑',
    '🍗',
    '🐟',
    '🥦',
    '🍳',
  ];

  late final TextEditingController _name;
  late final TextEditingController _prep;
  late String _emoji;
  late final List<MealComponent> _items;

  bool get _isNew => widget.meal == null;

  @override
  void initState() {
    super.initState();
    final m = widget.meal;
    _name = TextEditingController(text: m?.name ?? '');
    _prep = TextEditingController(
      text: (m == null || m.prepMinutes == 0) ? '' : '${m.prepMinutes}',
    );
    _emoji = m?.emoji ?? '🍱';
    _items = m == null ? [] : m.items.map((c) => c.copyWith()).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _prep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    // 计算统一走 Store，不在 UI 里重复营养公式
    final draft = MealTemplate(id: '', name: _name.text, items: _items);
    final n = store.mealNutrition(draft);
    final grams = store.mealGrams(draft);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: EditorHeader(
                title: _isNew ? '新建组合餐' : '编辑组合餐',
                onCancel: () => Navigator.of(context).pop(),
                onSave: _save,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  const FieldLabel('图标'),
                  const SizedBox(height: 10),
                  Center(
                    child: EmojiBadge(_emoji, size: 76, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _emojis.map(_emojiChip).toList(),
                  ),
                  const SizedBox(height: 22),
                  const FieldLabel('名称'),
                  const SizedBox(height: 8),
                  RoundedTextField(controller: _name, hint: '组合餐名称，如：鸡胸肉能量碗'),
                  const SizedBox(height: 14),
                  RoundedTextField(
                    controller: _prep,
                    numeric: true,
                    suffix: '分钟',
                    hint: '准备时长（可选）',
                  ),
                  const SizedBox(height: 22),
                  const FieldLabel('包含食材（按克数组合）'),
                  const SizedBox(height: 8),
                  if (_items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Column(
                        children: _items.asMap().entries.map((entry) {
                          final i = entry.key;
                          final c = entry.value;
                          final f = store.foodById(c.foodId);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: EmojiBadge(f?.emoji ?? '❓', size: 40),
                            title: Text(
                              f?.name ?? '（食材已删除）',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '每 ${fmtNum(c.grams)} g'
                              '${f == null ? '' : ' · ${f.forGrams(c.grams).calories.round()} 千卡'}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.subtext,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                    color: AppColors.accent,
                                  ),
                                  tooltip: '调整克数',
                                  onPressed: () => _adjustGrams(store, i),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: AppColors.subtext,
                                  ),
                                  tooltip: '移除',
                                  onPressed: () =>
                                      setState(() => _items.removeAt(i)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  PressableScale(
                    onTap: () => _pickFood(store),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x330E9F6E)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 20,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '添加食材',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text(
                              '整餐合计',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.subtext,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${n.calories.round()}',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '千卡',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.subtext,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '总重约 ${fmtNum(grams)} g · ${_items.length} 种食材',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.subtext,
                          ),
                        ),
                        const SizedBox(height: 12),
                        MacroRow(n: n),
                      ],
                    ),
                  ),
                  if (!_isNew) ...[
                    const SizedBox(height: 28),
                    _deleteButton(context),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiChip(String e) {
    final selected = _emoji == e;
    return PressableScale(
      onTap: () => setState(() => _emoji = e),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(e, style: const TextStyle(fontSize: 22)),
      ),
    );
  }

  Future<void> _adjustGrams(AppStore store, int index) async {
    final c = _items[index];
    final f = store.foodById(c.foodId);
    final serving = f?.servingGrams ?? 100;
    final q = await GramDialog.show(
      context,
      title: '「${f?.name ?? '食材'}」的克数',
      subtitle: f == null ? null : '一份 = ${fmtNum(serving)} g',
      initial: c.grams,
      quickGrams: [serving * 0.5, serving, serving * 1.5, serving * 2],
    );
    if (q != null) setState(() => _items[index] = c.copyWith(grams: q));
  }

  Future<void> _pickFood(AppStore store) async {
    final food = await showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FoodPickerSheet(),
    );
    if (food == null || !mounted) return;
    final grams = await GramDialog.show(
      context,
      title: '「${food.name}」的克数',
      subtitle: '一份 = ${fmtNum(food.servingGrams)} g',
      initial: food.servingGrams,
      quickGrams: [
        food.servingGrams * 0.5,
        food.servingGrams,
        food.servingGrams * 1.5,
        food.servingGrams * 2,
      ],
    );
    if (grams == null) return;
    setState(() => _items.add(MealComponent(foodId: food.id, grams: grams)));
  }

  Widget _deleteButton(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: ListTile(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Center(
          child: Text(
            '删除组合餐',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () async {
          final meal = widget.meal!;
          final ok = await confirmDelete(
            context,
            '删除组合餐',
            '「${meal.name}」会被移除；已有的饮食记录不受影响。',
          );
          if (!ok || !context.mounted) return;
          final store = context.read<AppStore>();
          final done = await store.removeMeal(meal.id);
          if (!done && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(store.lastWriteError ?? '删除失败'),
                duration: const Duration(milliseconds: 1200),
              ),
            );
            return;
          }
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('给这餐起个名字吧'),
          duration: Duration(milliseconds: 900),
        ),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('至少添加一种食材'),
          duration: Duration(milliseconds: 900),
        ),
      );
      return;
    }
    // 同一食材重复添加时合并克数（配方不允许重复项）
    final merged = <String, MealComponent>{};
    for (final c in _items) {
      final prev = merged[c.foodId];
      merged[c.foodId] = prev == null
          ? c
          : prev.copyWith(grams: prev.grams + c.grams);
    }
    final store = context.read<AppStore>();
    final ok = await store.upsertMeal(
      MealTemplate(
        id: widget.meal?.id ?? genId(),
        name: name,
        emoji: _emoji,
        prepMinutes: int.tryParse(_prep.text.trim()) ?? 0,
        items: merged.values.toList(),
      ),
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(store.lastWriteError ?? '保存失败'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }
}

/// 从食材库挑选一个食材
class _FoodPickerSheet extends StatefulWidget {
  const _FoodPickerSheet();

  @override
  State<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends State<_FoodPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final q = _query.trim().toLowerCase();
    final foods = store.foods
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD8DAE0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Text(
                    '选择食材',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: AppColors.subtext,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.subtext,
                  ),
                  hintText: '搜索食材',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.subtext,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: foods.length,
                itemBuilder: (context, i) {
                  final f = foods[i];
                  return PressableScale(
                    onTap: () => Navigator.of(context).pop(f),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          EmojiBadge(f.emoji, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '每份 ${fmtNum(f.servingGrams)}g · ${f.kcalPer100.round()} 千卡/100g',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.subtext,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.add_circle_rounded,
                            size: 24,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
