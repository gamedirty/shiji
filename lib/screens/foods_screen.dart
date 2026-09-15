import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'food_edit_screen.dart';
import 'meal_edit_screen.dart';

/// Tab 3 —— 食材库：常用食材（基础维度）与组合餐（一餐由多个食材组成）分开管理
class FoodsScreen extends StatefulWidget {
  const FoodsScreen({super.key});

  @override
  State<FoodsScreen> createState() => _FoodsScreenState();
}

class _FoodsScreenState extends State<FoodsScreen> {
  int _seg = 0; // 0=食材 1=组合餐
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (store.loadError != null) {
      return StoreErrorView(message: store.loadError!, onRetry: store.init);
    }
    if (!store.loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    final q = _query.trim().toLowerCase();
    final foods = store.foods
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    final meals = store.meals
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Text(
                  _seg == 0 ? '食材库' : '组合餐',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _backupDialog,
                  icon: const Icon(
                    Icons.settings_backup_restore_rounded,
                    size: 24,
                    color: AppColors.subtext,
                  ),
                  tooltip: '备份 / 恢复',
                ),
                IconButton(
                  onPressed: _openEditor,
                  icon: const Icon(
                    Icons.add_circle_rounded,
                    size: 28,
                    color: AppColors.accent,
                  ),
                  tooltip: _seg == 0 ? '新建食材' : '新建组合餐',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 38,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _seg,
                thumbColor: Colors.white,
                backgroundColor: const Color(0xFFE4E6EC),
                onValueChanged: (v) => setState(() => _seg = v ?? 0),
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('食材', style: TextStyle(fontSize: 14)),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('组合餐', style: TextStyle(fontSize: 14)),
                  ),
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '食材按每 100g 记录营养，可自定义“一份”的重量（整包商品可设为一份）；组合餐由多个食材组成。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.subtext,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 15),
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
            child: _seg == 0
                ? _FoodsList(foods: foods)
                : _MealsList(meals: meals),
          ),
        ],
      ),
    );
  }

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _seg == 0 ? const FoodEditScreen() : const MealEditScreen(),
      ),
    );
  }

  /// 备份 / 恢复：数据是用户长期积累的资产，提供纯文本 JSON 的导出与恢复
  Future<void> _backupDialog() async {
    final store = context.read<AppStore>();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备份 / 恢复'),
        content: const Text(
          '导出会把全部数据（目标、食材、组合餐、饮食记录）复制为 JSON 文本；'
          '恢复会用剪贴板里的备份覆盖当前所有数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppColors.subtext)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'import'),
            child: const Text('从剪贴板恢复'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'export'),
            child: const Text(
              '导出到剪贴板',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'export') {
      await Clipboard.setData(ClipboardData(text: store.exportJson()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板，粘贴到备忘录等处保存即可'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }
    // 恢复：先确认再读取剪贴板
    final ok = await confirmReplace(context);
    if (!ok || !mounted) return;
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剪贴板里没有内容'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }
    final success = await store.importJson(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '已从备份恢复' : '备份内容无法识别，未做任何改动'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  Future<bool> confirmReplace(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('覆盖当前数据'),
        content: const Text('当前的目标、食材、组合餐和饮食记录都会被备份内容替换，且无法撤销。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: AppColors.subtext)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '覆盖',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _FoodsList extends StatelessWidget {
  final List<Food> foods;

  const _FoodsList({required this.foods});

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return const _EmptyHint(emoji: '🥗', text: '没有找到食材\n点右上角 + 添加常用食材');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 220),
      itemCount: foods.length,
      itemBuilder: (context, i) {
        final food = foods[i];
        return Dismissible(
          key: ValueKey(food.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: ShapeDecoration(
              color: AppColors.danger,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
            ),
          ),
          confirmDismiss: (_) => confirmDelete(
            context,
            '删除食材',
            '「${food.name}」会从组合餐配方中移除；已有的饮食记录是快照，不受影响。确定删除吗？',
          ),
          onDismissed: (_) => context.read<AppStore>().removeFood(food.id),
          child: _FoodTile(food: food),
        );
      },
    );
  }
}

class _FoodTile extends StatelessWidget {
  final Food food;

  const _FoodTile({required this.food});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => FoodEditScreen(food: food))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            EmojiBadge(food.emoji, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '每份 ${fmtNum(food.servingGrams)}g · ${food.kcalPer100.round()} 千卡/100g · 蛋白 ${fmtNum(food.protein)} 碳水 ${fmtNum(food.carbs)} 脂肪 ${fmtNum(food.fat)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.subtext,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Color(0xFFC6C9CF),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealsList extends StatelessWidget {
  final List<MealTemplate> meals;

  const _MealsList({required this.meals});

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) {
      return const _EmptyHint(
        emoji: '🍱',
        text: '没有找到组合餐\n点右上角 + 把常吃的一餐组合保存下来',
      );
    }
    final store = context.read<AppStore>();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 220),
      itemCount: meals.length,
      itemBuilder: (context, i) {
        final meal = meals[i];
        return Dismissible(
          key: ValueKey(meal.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: ShapeDecoration(
              color: AppColors.danger,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
            ),
          ),
          confirmDismiss: (_) => confirmDelete(
            context,
            '删除组合餐',
            '「${meal.name}」会被移除；已有的饮食记录是快照，不受影响。确定删除吗？',
          ),
          onDismissed: (_) => store.removeMeal(meal.id),
          child: _MealTile(meal: meal),
        );
      },
    );
  }
}

class _MealTile extends StatelessWidget {
  final MealTemplate meal;

  const _MealTile({required this.meal});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final n = store.mealNutrition(meal);
    return PressableScale(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => MealEditScreen(meal: meal))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            EmojiBadge(meal.emoji, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${meal.items.length} 种食材 · ${n.calories.round()} 千卡/份'
                    '${meal.prepMinutes > 0 ? ' · 约 ${meal.prepMinutes} 分钟' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.subtext,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Color(0xFFC6C9CF),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String emoji;
  final String text;

  const _EmptyHint({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.subtext,
            ),
          ),
        ],
      ),
    );
  }
}
