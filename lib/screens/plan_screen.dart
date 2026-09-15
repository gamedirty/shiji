import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'backup_flow.dart';

/// Tab 1 —— 饮食计划：周历（可跨周翻页）+ 餐段筛选 + 当日条目卡片
class PlanScreen extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final void Function({MealType? type}) onAdd;

  const PlanScreen({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    required this.onAdd,
  });

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  MealType? _filter;
  final ScrollController _scrollController = ScrollController();
  bool _showStickyDate = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 切换日期并滚回顶部
  void _onDateChanged(DateTime d) {
    widget.onDateChanged(d);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final show = n.metrics.pixels > 160;
    if (show != _showStickyDate) {
      setState(() => _showStickyDate = show);
    }
    return false;
  }

  static final DateTime _defaultFirstDate = DateTime.now().subtract(
    const Duration(days: 730),
  );
  static final DateTime _lastDate = DateTime.now().add(
    const Duration(days: 730),
  );

  /// 浏览下界：至少今天-730天；更早的历史记录仍然可以翻到
  DateTime _firstDateFor(AppStore store) {
    DateTime? earliest;
    for (final e in store.diary) {
      final d = DateTime.tryParse(e.dateKey);
      if (d != null && (earliest == null || d.isBefore(earliest))) earliest = d;
    }
    if (earliest == null || earliest.isAfter(_defaultFirstDate)) {
      return _defaultFirstDate;
    }
    return DateTime(earliest.year, earliest.month, earliest.day);
  }

  /// 所有日期入口共用同一范围，翻周不会翻出日期选择器之外
  DateTime _clamp(DateTime d, DateTime firstDate) {
    final ms = d.millisecondsSinceEpoch.clamp(
      firstDate.millisecondsSinceEpoch,
      _lastDate.millisecondsSinceEpoch,
    );
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _pickDate(AppStore store, DateTime initial) async {
    final firstDate = _firstDateFor(store);
    final d = await showDatePicker(
      context: context,
      initialDate: _clamp(initial, firstDate),
      firstDate: firstDate,
      lastDate: _lastDate,
      helpText: '选择日期',
    );
    if (d != null) _onDateChanged(d);
  }

  /// 计划复用：把前一天有内容的条目复制为这一天的计划
  Future<void> _copyPreviousDay() async {
    final store = context.read<AppStore>();
    final target = widget.selectedDate;
    final sourceKey = dateKeyOf(target.subtract(const Duration(days: 1)));
    final targetKey = dateKeyOf(target);
    if (store
        .entriesFor(sourceKey)
        .every((e) => e.status == EntryStatus.skipped)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('前一天没有可复制的饮食'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }
    String? choice = 'merge';
    if (store
        .entriesFor(targetKey)
        .any((e) => e.status == EntryStatus.planned)) {
      if (!mounted) return;
      choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('这一天已有计划'),
          content: const Text('合并：保留现有计划，追加前一天的条目。\n替换：清掉现有计划后复制（已吃和跳过的不受影响）。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.subtext),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('替换'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text(
                '合并',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (choice == null || !mounted) return;
    final n = await store.copyDay(
      sourceKey,
      targetKey,
      replaceExisting: choice == 'replace',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (n) {
          -1 => store.lastWriteError ?? '复制失败',
          0 => '前一天没有可复制的饮食',
          _ => '已复制 $n 项到 ${target.month}月${target.day}日 的计划',
        }),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (store.loadError != null) {
      return StoreErrorView(
        message: store.loadError!,
        onRetry: store.init,
        onRestore: () => restoreFromClipboard(context, store),
      );
    }
    if (!store.loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    final now = DateTime.now();
    final date = widget.selectedDate;
    final key = dateKeyOf(date);
    final all = store.entriesFor(key);
    final list = _filter == null
        ? all
        : all.where((e) => e.type == _filter).toList();
    final consumed = store.consumedTotalsFor(key);
    final planned = store.plannedTotalsFor(key);
    final firstDate = _firstDateFor(store);

    return SafeArea(
      top: true,
      bottom: false,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 220),
              children: [
                _header(context, store, now),
                const SizedBox(height: 20),
                _dateRow(date, now),
                const SizedBox(height: 12),
                _weekRow(date, firstDate),
                const SizedBox(height: 24),
                Text(
                  isSameDay(date, now)
                      ? '今天的安排'
                      : '${date.month}月${date.day}日 的安排',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                _summaryCard(store, consumed, planned),
                const SizedBox(height: 16),
                _chips(),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  _empty(context)
                else
                  ...list.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EntryCard(entry: e),
                    ),
                  ),
              ],
            ),
          ),
          // 吸顶日期栏：滚过日期区后从顶部淡入
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_showStickyDate,
              child: AnimatedSlide(
                offset: _showStickyDate ? Offset.zero : const Offset(0, -1.4),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _showStickyDate ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _StickyDateBar(
                    date: date,
                    showTodayButton: !isSameDay(date, now),
                    onToday: () => _onDateChanged(now),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppStore store, DateTime now) {
    return Row(
      children: [
        const EmojiBadge('🍱', size: 44, color: Colors.white),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '食记',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            Text(
              '健身饮食计划与记录',
              style: TextStyle(fontSize: 11, color: AppColors.subtext),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: () => _pickDate(store, widget.selectedDate),
          icon: const Icon(
            Icons.calendar_today_outlined,
            size: 22,
            color: AppColors.text,
          ),
          tooltip: '选择日期',
        ),
      ],
    );
  }

  Widget _dateRow(DateTime date, DateTime now) {
    final isToday = isSameDay(date, now);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${date.month}月${date.day}日',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Text(
          weekdayLabel(date),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isToday ? AppColors.text : AppColors.subtext,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _copyPreviousDay,
          icon: const Icon(
            Icons.copy_rounded,
            size: 20,
            color: AppColors.subtext,
          ),
          tooltip: '复制前一天到这一天',
        ),
        // 固定行高 + 紧凑按钮，保证按钮出现/消失时不改变行高（避免列表抖动）
        SizedBox(
          height: 34,
          child: TextButton(
            onPressed: isToday ? null : () => _onDateChanged(now),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              '今天',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isToday ? Colors.transparent : AppColors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 周历 + 前后翻周
  Widget _weekRow(DateTime date, DateTime firstDate) {
    return Row(
      children: [
        _weekArrow(
          Icons.chevron_left_rounded,
          () => _onDateChanged(
            _clamp(date.subtract(const Duration(days: 7)), firstDate),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: WeekStrip(selected: date, onTap: _onDateChanged),
        ),
        const SizedBox(width: 4),
        _weekArrow(
          Icons.chevron_right_rounded,
          () => _onDateChanged(
            _clamp(date.add(const Duration(days: 7)), firstDate),
          ),
        ),
      ],
    );
  }

  Widget _weekArrow(IconData icon, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.text),
      ),
    );
  }

  Widget _summaryCard(AppStore store, Nutrition consumed, Nutrition planned) {
    final target = store.targets;
    final progress = target.kcal > 0 ? consumed.calories / target.kcal : 0.0;
    final remaining = target.kcal - consumed.calories;
    final sub = remaining >= 0
        ? '还可吃 ${remaining.round()} 千卡'
        : '已超出 ${(-remaining).round()} 千卡';

    return PressableScale(
      onTap: () => _editTarget(store),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: ShapeDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C8A5F), Color(0xFF26B26D)],
          ),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x3D26B26D),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CalorieRing(
                  progress: progress,
                  valueText: consumed.calories.round().toString(),
                  unitText: '已摄入',
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '每日目标 ${fmtNum(target.kcal)} 千卡',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0x99FFFFFF),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (planned.calories > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '还有计划 ${planned.calories.round()} 千卡未吃',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '点按可调整目标',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            MacroProgressRow(n: consumed, targets: target, light: true),
          ],
        ),
      ),
    );
  }

  Future<void> _editTarget(AppStore store) async {
    final t = store.targets;
    final kcal = TextEditingController(text: t.kcal.round().toString());
    final protein = TextEditingController(text: t.protein.round().toString());
    final carbs = TextEditingController(text: t.carbs.round().toString());
    final fat = TextEditingController(text: t.fat.round().toString());
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('每日目标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('热量（千卡）'),
              const SizedBox(height: 6),
              TextField(
                controller: kcal,
                keyboardType: TextInputType.number,
                inputFormatters: [NumericTextFormatter()],
                decoration: const InputDecoration(
                  suffixText: '千卡',
                  suffixStyle: TextStyle(color: AppColors.subtext),
                ),
              ),
              const SizedBox(height: 12),
              const FieldLabel('三大营养素（克）'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: protein,
                      keyboardType: TextInputType.number,
                      inputFormatters: [NumericTextFormatter()],
                      decoration: const InputDecoration(
                        hintText: '蛋白',
                        suffixText: 'g',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: carbs,
                      keyboardType: TextInputType.number,
                      inputFormatters: [NumericTextFormatter()],
                      decoration: const InputDecoration(
                        hintText: '碳水',
                        suffixText: 'g',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: fat,
                      keyboardType: TextInputType.number,
                      inputFormatters: [NumericTextFormatter()],
                      decoration: const InputDecoration(
                        hintText: '脂肪',
                        suffixText: 'g',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.subtext),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '保存',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
      if (saved != true || !mounted) return;
      // 在释放控制器前取值
      final kcalText = kcal.text;
      final proteinText = protein.text;
      final carbsText = carbs.text;
      final fatText = fat.text;
      final kcalV = double.tryParse(kcalText.trim()) ?? 0;
      if (kcalV < 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('热量目标至少 100 千卡'),
            duration: Duration(milliseconds: 1200),
          ),
        );
        return;
      }
      final ok = await store.setTargets(
        NutritionTargets(
          kcal: kcalV,
          protein: double.tryParse(proteinText.trim()) ?? 0,
          carbs: double.tryParse(carbsText.trim()) ?? 0,
          fat: double.tryParse(fatText.trim()) ?? 0,
        ),
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(store.lastWriteError ?? '目标保存失败'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      }
    } finally {
      kcal.dispose();
      protein.dispose();
      carbs.dispose();
      fat.dispose();
    }
  }

  Widget _chips() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          _chip(null),
          const SizedBox(width: 8),
          ...MealType.values.map(
            (t) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(MealType? t) {
    final selected = _filter == t;
    final label = t?.label ?? '全部';
    final range = t?.timeRange ?? '';
    final accent = t?.accent ?? AppColors.accent;
    return PressableScale(
      onTap: () => setState(() => _filter = t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          color: selected ? null : Colors.white,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(accent, Colors.white, 0.18)!, accent],
                )
              : null,
          shadows: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? Colors.white : accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.text,
                  ),
                ),
              ],
            ),
            if (range.isNotEmpty)
              Text(
                range,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: selected ? const Color(0xCCFFFFFF) : AppColors.subtext,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return IosCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Text(_filter?.emoji ?? '🍽️', style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          Text(
            _filter == null ? '这一天还没有安排饮食' : '${_filter!.label}还没有安排',
            style: const TextStyle(fontSize: 14, color: AppColors.subtext),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => widget.onAdd(type: _filter),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('添加饮食'),
          ),
        ],
      ),
    );
  }
}

/// 单条饮食记录卡片：展示创建时固化的快照（名称/克数/营养），来源被删也不失真。
/// 操作期间防双击；失败时提示该次操作自身的错误。
class _EntryCard extends StatefulWidget {
  final DiaryEntry entry;

  const _EntryCard({required this.entry});

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _busy = false;

  Future<void> _run(AppStore store, Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(store.lastWriteError ?? '操作失败'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final entry = widget.entry;
    final consumed = entry.status == EntryStatus.consumed;
    final skipped = entry.status == EntryStatus.skipped;
    final dim = consumed || skipped;
    final n = entry.nutrition;

    final subtitleParts = <String>[
      switch (entry.status) {
        EntryStatus.planned => '计划',
        EntryStatus.consumed => '已吃',
        EntryStatus.skipped => '已跳过',
      },
      '${fmtNum(entry.grams)} g',
      if (entry.items.length > 1) entry.items.map((it) => it.name).join(' · '),
    ];

    return IosCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PressableScale(
                semanticLabel: '切换完成状态',
                onTap: _busy
                    ? null
                    : () => _run(
                        store,
                        () => store.setEntryStatus(
                          entry.id,
                          entry.status == EntryStatus.planned
                              ? EntryStatus.consumed
                              : EntryStatus.planned,
                        ),
                      ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(
                      opacity: dim ? 0.45 : 1,
                      child: EmojiBadge(
                        entry.emoji,
                        size: 54,
                        color: entry.type.accentSoft,
                      ),
                    ),
                    if (dim)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: consumed
                                ? AppColors.carbs
                                : AppColors.subtext,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            consumed
                                ? Icons.check_rounded
                                : Icons.remove_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        decoration: consumed
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppColors.subtext,
                        color: dim ? AppColors.subtext : AppColors.text,
                      ),
                    ),
                    if (entry.title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.subtext,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.subtext,
                  size: 22,
                ),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                position: PopupMenuPosition.under,
                onSelected: (v) async {
                  switch (v) {
                    case 'toggle':
                      await _run(
                        store,
                        () => store.setEntryStatus(
                          entry.id,
                          entry.status == EntryStatus.planned
                              ? EntryStatus.consumed
                              : EntryStatus.planned,
                        ),
                      );
                    case 'skip':
                      await _run(
                        store,
                        () => store.setEntryStatus(
                          entry.id,
                          skipped ? EntryStatus.planned : EntryStatus.skipped,
                        ),
                      );
                    case 'edit':
                      final g = await GramDialog.show(
                        context,
                        title: '调整「${entry.title}」的克数',
                        subtitle: '营养按创建时的食材定义换算',
                        initial: entry.grams,
                      );
                      if (g != null) {
                        await _run(
                          store,
                          () => store.setEntryGrams(entry.id, g),
                        );
                      }
                    case 'delete':
                      final ok = await confirmDelete(
                        context,
                        '删除这条记录',
                        '将从 ${entry.dateKey} 的${entry.type.label}中移除。',
                      );
                      if (ok) {
                        await _run(store, () => store.removeEntry(entry.id));
                      }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          consumed
                              ? Icons.undo_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 19,
                          color: AppColors.carbs,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          entry.status == EntryStatus.planned
                              ? '标记为已吃'
                              : '改回计划',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'skip',
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 19,
                          color: AppColors.subtext,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          skipped ? '取消跳过' : '跳过这一项',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 19,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Text('调整克数', style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '删除',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 66, right: 8),
            child: MacroRow(n: n),
          ),
        ],
      ),
    );
  }
}

/// 吸顶日期栏：滚动越过日期区后从顶部淡入的毛玻璃小条
class _StickyDateBar extends StatelessWidget {
  final DateTime date;
  final bool showTodayButton;
  final VoidCallback onToday;

  const _StickyDateBar({
    required this.date,
    required this.showTodayButton,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: GlassSurface(
        radius: 20,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${date.month}月${date.day}日',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  weekdayLabel(date),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.subtext,
                  ),
                ),
                const Spacer(),
                if (showTodayButton)
                  PressableScale(
                    onTap: onToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: ShapeDecoration(
                        color: AppColors.accentSoft,
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '回到今天',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
