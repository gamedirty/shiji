import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// 中间 + 号：添加饮食 —— 选日期、餐段，从食材库或组合餐里挑、按克数调整，
/// 再明确选择「加入计划」或「记为已吃」（意图与事实不靠日期猜测）
class AddEntrySheet extends StatefulWidget {
  final DateTime initialDate;
  final MealType? initialType;

  const AddEntrySheet({super.key, required this.initialDate, this.initialType});

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  late DateTime _date = widget.initialDate;
  late MealType _type =
      widget.initialType ?? MealTypeX.guessByTime(DateTime.now());
  int _seg = 0; // 0=食材 1=组合餐
  String _query = '';

  EntrySource? _selSource;
  String _selId = '';
  double _selGrams = 100;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final q = _query.trim().toLowerCase();
    final foods = store.foods
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    // 空配方组合餐（食材全被删除）不可添加，避免生成无法调整的零克记录
    final meals = store.meals
        .where(
          (m) =>
              (q.isEmpty || m.name.toLowerCase().contains(q)) &&
              m.items.isNotEmpty,
        )
        .toList();
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92 - insets,
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8DAE0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  const Text(
                    '添加饮食',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 24,
                      color: AppColors.subtext,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _dateBar(),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: MealType.values
                    .map((t) => Expanded(child: _typeChip(t)))
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 36,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _seg,
                  thumbColor: Colors.white,
                  backgroundColor: const Color(0xFFE4E6EC),
                  onValueChanged: (v) => setState(() {
                    _seg = v ?? 0;
                    _clearSelection();
                  }),
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('食材', style: TextStyle(fontSize: 13.5)),
                    ),
                    1: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('组合餐', style: TextStyle(fontSize: 13.5)),
                    ),
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  hintText: '搜索${_seg == 0 ? '食材' : '组合餐'}',
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
            const SizedBox(height: 8),
            Expanded(
              child: _seg == 0 ? _buildFoodList(foods) : _buildMealList(meals),
            ),
            if (_selSource != null) _selectionBar(store),
          ],
        ),
      ),
    );
  }

  Widget _dateBar() {
    final isToday = isSameDay(_date, DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _circleButton(
            Icons.chevron_left_rounded,
            () =>
                setState(() => _date = _date.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: PressableScale(
              onTap: () => setState(() => _date = DateTime.now()),
              child: Text.rich(
                TextSpan(
                  text: '${_date.month}月${_date.day}日 ',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(
                      text: isToday
                          ? '今天 · ${weekdayLabel(_date)}'
                          : weekdayLabel(_date),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.subtext,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          _circleButton(
            Icons.chevron_right_rounded,
            () => setState(() => _date = _date.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: AppColors.text),
      ),
    );
  }

  Widget _typeChip(MealType t) {
    final selected = _type == t;
    return PressableScale(
      onTap: () => setState(() => _type = t),
      child: Container(
        margin: EdgeInsets.only(right: t == MealType.snack ? 0 : 8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: ShapeDecoration(
          color: selected ? null : Colors.white,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(t.accent, Colors.white, 0.18)!, t.accent],
                )
              : null,
          shadows: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              t.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.text,
              ),
            ),
            Text(
              t.timeRange,
              style: TextStyle(
                fontSize: 9,
                height: 1.4,
                color: selected ? const Color(0xCCFFFFFF) : AppColors.subtext,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodList(List<Food> foods) {
    if (foods.isEmpty) {
      return const Center(
        child: Text(
          '没有找到食材，先去「食材库」添加',
          style: TextStyle(fontSize: 13, color: AppColors.subtext),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: foods.length,
      itemBuilder: (context, i) {
        final f = foods[i];
        final selected = _selSource == EntrySource.food && _selId == f.id;
        return _row(
          selected: selected,
          onTap: () => setState(() {
            if (selected) {
              _clearSelection();
            } else {
              _selSource = EntrySource.food;
              _selId = f.id;
              _selGrams = f.servingGrams;
            }
          }),
          emoji: f.emoji,
          title: f.name,
          subtitle:
              '一份 ${fmtNum(f.servingGrams)}g · ${f.kcalPer100.round()} 千卡/100g',
        );
      },
    );
  }

  Widget _buildMealList(List<MealTemplate> meals) {
    if (meals.isEmpty) {
      return const Center(
        child: Text(
          '还没有组合餐，先去「食材库 → 组合餐」创建',
          style: TextStyle(fontSize: 13, color: AppColors.subtext),
        ),
      );
    }
    final store = context.read<AppStore>();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: meals.length,
      itemBuilder: (context, i) {
        final m = meals[i];
        final selected = _selSource == EntrySource.meal && _selId == m.id;
        final n = store.mealNutrition(m);
        final grams = store.mealGrams(m);
        return _row(
          selected: selected,
          onTap: () => setState(() {
            if (selected) {
              _clearSelection();
            } else {
              _selSource = EntrySource.meal;
              _selId = m.id;
              _selGrams = grams;
            }
          }),
          emoji: m.emoji,
          title: m.name,
          subtitle:
              '${m.items.length} 种食材 · 整餐 ${n.calories.round()} 千卡 / ${fmtNum(grams)}g',
        );
      },
    );
  }

  Widget _row({
    required bool selected,
    required VoidCallback onTap,
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            EmojiBadge(emoji, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.subtext,
                    ),
                  ),
                ],
              ),
            ),
            selected
                ? Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 24,
                    color: Color(0xFFC6C9CF),
                  ),
          ],
        ),
      ),
    );
  }

  /// 步进粒度：半份（食材按其一份克数，组合餐按整餐克数）
  double _stepGrams(AppStore store) {
    final f = _selSource == EntrySource.food ? store.foodById(_selId) : null;
    if (f != null) return f.servingGrams / 2;
    final m = _selSource == EntrySource.meal ? store.mealById(_selId) : null;
    if (m != null) return store.mealGrams(m) / 2;
    return 50;
  }

  Widget _selectionBar(AppStore store) {
    final title = store.titleOfRef(_selSource!, _selId);
    final step = _stepGrams(store);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0FFFFFF), Color(0xDCFFFFFF)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: Color(0x99FFFFFF), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${_type.label} · ${fmtNum(_selGrams)} g',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.subtext,
                        ),
                      ),
                    ],
                  ),
                ),
                _stepper(step),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      side: const BorderSide(color: AppColors.accent),
                    ),
                    onPressed: () => _add(EntryStatus.planned),
                    icon: const Icon(
                      Icons.event_note_rounded,
                      size: 17,
                      color: AppColors.accent,
                    ),
                    label: const Text(
                      '加入计划',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                    ),
                    onPressed: () => _add(EntryStatus.consumed),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text(
                      '记为已吃',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper(double step) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PressableScale(
            onTap: _selGrams > step
                ? () => setState(() => _selGrams -= step)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                Icons.remove_rounded,
                size: 18,
                color: _selGrams > step
                    ? AppColors.text
                    : const Color(0xFFC6C9CF),
              ),
            ),
          ),
          PressableScale(
            semanticLabel: '输入克数',
            onTap: () => _inputGrams(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${fmtNum(_selGrams)} g',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          PressableScale(
            onTap: () => setState(() => _selGrams += step),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.add_rounded, size: 18, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  void _clearSelection() {
    _selSource = null;
    _selId = '';
    _selGrams = 100;
  }

  /// 点克数直接输入任意值；快捷项按"半份/一份/1.5份/两份"给出
  Future<void> _inputGrams() async {
    final store = context.read<AppStore>();
    final step = _stepGrams(store);
    final g = await GramDialog.show(
      context,
      title: '输入克数',
      initial: _selGrams,
      quickGrams: [step, step * 2, step * 3, step * 4],
    );
    if (g != null) setState(() => _selGrams = g);
  }

  Future<void> _add(EntryStatus status) async {
    final store = context.read<AppStore>();
    final source = _selSource!;
    final entry = store.buildEntry(
      dateKey: dateKeyOf(_date),
      type: _type,
      source: source,
      refId: _selId,
      grams: _selGrams,
      status: status,
    );
    final ok = await store.addEntry(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${status == EntryStatus.consumed ? "已记录" : "已加入计划"}「${entry.title}」到 ${_date.month}月${_date.day}日 · ${_type.label}'
                : (store.lastWriteError ?? '保存失败，请重试'),
          ),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    if (ok) setState(_clearSelection);
  }
}
