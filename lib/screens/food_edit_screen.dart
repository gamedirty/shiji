import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// 新建 / 编辑食材：名字、图标、每份克数（默认 100g，可自定义如 360g 整包）、
/// 三大营养素（每 100g），热量按 4/4/9 自动估算
class FoodEditScreen extends StatefulWidget {
  final Food? food;

  const FoodEditScreen({super.key, this.food});

  @override
  State<FoodEditScreen> createState() => _FoodEditScreenState();
}

class _FoodEditScreenState extends State<FoodEditScreen> {
  static const _emojis = [
    '🥗', '🍗', '🥚', '🥩', '🐟', '🦐', '🥦', '🥑', '🍚', '🍜', '🍞', '🥛',
    '🍶', '🧀', '🥜', '🍌', '🍎', '🫐', '🍠', '🌽', '🍫', '💪', '🍳', '🍱',
  ];

  late final TextEditingController _name;
  late final TextEditingController _grams;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late String _emoji;

  bool get _isNew => widget.food == null;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _name = TextEditingController(text: f?.name ?? '');
    _grams = TextEditingController(text: fmtNum(f?.servingGrams ?? 100));
    _protein = TextEditingController(text: fmtNum(f?.protein ?? 0));
    _carbs = TextEditingController(text: fmtNum(f?.carbs ?? 0));
    _fat = TextEditingController(text: fmtNum(f?.fat ?? 0));
    _emoji = f?.emoji ?? '🥗';
    for (final c in [_grams, _protein, _carbs, _fat]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _grams.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final n100 = Nutrition(
      protein: _parse(_protein),
      carbs: _parse(_carbs),
      fat: _parse(_fat),
    );
    final grams = _parse(_grams) <= 0 ? 100.0 : _parse(_grams);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: EditorHeader(
                title: _isNew ? '新建食材' : '编辑食材',
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
                  Center(child: EmojiBadge(_emoji, size: 76, color: Colors.white)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _emojis
                        .map((e) => _emojiChip(e))
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  const FieldLabel('名称'),
                  const SizedBox(height: 8),
                  RoundedTextField(controller: _name, hint: '食材名称，如：鸡胸肉'),
                  const SizedBox(height: 22),
                  const FieldLabel('每份重量（克）'),
                  const SizedBox(height: 8),
                  RoundedTextField(
                      controller: _grams,
                      numeric: true,
                      suffix: 'g',
                      hint: '标准 100g；整包商品可设为一份，如 360'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [50.0, 100.0, 250.0, 360.0].map((g) {
                      final label = g == 100 ? '100 · 标准' : fmtNum(g);
                      final selected = _parse(_grams) == g;
                      return PressableScale(
                        onTap: () => setState(() => _grams.text = fmtNum(g)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.accentSoft : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: selected ? AppColors.accent : AppColors.divider),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? AppColors.accent : AppColors.subtext)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  const FieldLabel('三大营养素（每 100 克）'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: RoundedTextField(
                              controller: _protein, numeric: true, suffix: 'g', hint: '蛋白质')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: RoundedTextField(
                              controller: _carbs, numeric: true, suffix: 'g', hint: '碳水')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: RoundedTextField(
                              controller: _fat, numeric: true, suffix: 'g', hint: '脂肪')),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('每 100g',
                                    style:
                                        TextStyle(fontSize: 11, color: AppColors.subtext)),
                                Text('${n100.calories.round()} 千卡',
                                    style: const TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.w800)),
                              ],
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('每 ${fmtNum(grams)}g（一份）',
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.subtext)),
                                Text('${n100.times(grams / 100).calories.round()} 千卡',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.accent)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        MacroRow(n: n100),
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
              color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(e, style: const TextStyle(fontSize: 22)),
      ),
    );
  }

  Widget _deleteButton(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18))),
      child: ListTile(
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18)),
        title: const Center(
          child: Text('删除食材',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
        onTap: () async {
          final food = widget.food!;
          final ok = await confirmDelete(
              context, '删除食材', '「${food.name}」会同时从组合餐与饮食记录中移除，确定删除吗？');
          if (!ok || !context.mounted) return;
          context.read<AppStore>().removeFood(food.id);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('给食材起个名字吧'), duration: Duration(milliseconds: 900)));
      return;
    }
    final grams = _parse(_grams);
    final store = context.read<AppStore>();
    store.upsertFood(Food(
      id: widget.food?.id ?? genId(),
      name: name,
      emoji: _emoji,
      protein: _parse(_protein),
      carbs: _parse(_carbs),
      fat: _parse(_fat),
      servingGrams: grams > 0 ? grams : 100,
    ));
    Navigator.of(context).pop();
  }
}
