import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// Tab 1 —— 饮食计划：周历 + 餐段筛选 + 当日条目卡片
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
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.loaded) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    final now = DateTime.now();
    final date = widget.selectedDate;
    final key = dateKeyOf(date);
    final all = store.entriesFor(key);
    final list = _filter == null ? all : all.where((e) => e.type == _filter).toList();
    final totals = store.totalsFor(key);

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
                _header(context, now),
                const SizedBox(height: 20),
                _dateRow(date, now),
                const SizedBox(height: 12),
                WeekStrip(selected: date, onTap: _onDateChanged),
                const SizedBox(height: 24),
                Text(
                  isSameDay(date, now) ? '今天的安排' : '${date.month}月${date.day}日 的安排',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
                ),
                const SizedBox(height: 12),
                _summaryCard(store, totals),
                const SizedBox(height: 16),
                _chips(),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  _empty(context)
                else
                  ...list.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EntryCard(entry: e),
                      )),
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

  Widget _header(BuildContext context, DateTime now) {
    return Row(
      children: [
        const EmojiBadge('🍱', size: 44, color: Colors.white),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('食记', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15)),
            Text('健身饮食计划与记录', style: TextStyle(fontSize: 11, color: AppColors.subtext)),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: () => _onDateChanged(now),
          icon: const Icon(Icons.calendar_today_outlined, size: 22, color: AppColors.text),
          tooltip: '回到今天',
        ),
      ],
    );
  }

  Widget _dateRow(DateTime date, DateTime now) {
    final isToday = isSameDay(date, now);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('${date.month}月${date.day}日',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(weekdayLabel(date),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isToday ? AppColors.text : AppColors.subtext)),
        const Spacer(),
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
            child: Text('今天',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isToday ? Colors.transparent : AppColors.accent)),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(AppStore store, Nutrition totals) {
    final target = store.kcalTarget;
    final progress = target > 0 ? totals.calories / target : 0.0;
    final remaining = target - totals.calories;
    final sub = remaining >= 0
        ? '今日还可吃 ${remaining.round()} 千卡'
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
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(26)),
          shadows: const [
            BoxShadow(color: Color(0x3D26B26D), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CalorieRing(
                  progress: progress,
                  valueText: totals.calories.round().toString(),
                  unitText: '千卡',
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('全天合计',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xCCFFFFFF))),
                      const SizedBox(height: 2),
                      Text('每日目标 ${fmtNum(store.kcalTarget)} 千卡',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0x99FFFFFF))),
                      const SizedBox(height: 6),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('点按可调整目标',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0x80FFFFFF))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            MacroRow(n: totals, light: true),
          ],
        ),
      ),
    );
  }

  Future<void> _editTarget(AppStore store) async {
    final c = TextEditingController(text: store.kcalTarget.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('每日热量目标'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [NumericTextFormatter()],
          decoration: const InputDecoration(
              suffixText: '千卡', suffixStyle: TextStyle(color: AppColors.subtext)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: AppColors.subtext))),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, double.tryParse(c.text.trim())),
              child: const Text('保存',
                  style: TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (v != null && v >= 100) store.setKcalTarget(v);
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
          ...MealType.values.map((t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chip(t),
              )),
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
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18)),
          color: selected ? null : Colors.white,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(accent, Colors.white, 0.18)!,
                    accent,
                  ],
                )
              : null,
          shadows: selected
              ? [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 5)),
                ]
              : const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
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
                        color: selected ? Colors.white : accent),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.text)),
              ],
            ),
            if (range.isNotEmpty)
              Text(range,
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: selected ? const Color(0xCCFFFFFF) : AppColors.subtext)),
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

/// 单条饮食记录卡片
class _EntryCard extends StatelessWidget {
  final DiaryEntry entry;

  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final title = store.titleOf(entry);
    final subtitle = store.subtitleOf(entry);
    final n = store.nutritionOf(entry);
    final done = entry.done;

    return IosCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PressableScale(
                onTap: () => store.setDone(entry.id, !done),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(
                      opacity: done ? 0.45 : 1,
                      child: EmojiBadge(store.emojiOf(entry),
                          size: 54, color: entry.type.accentSoft),
                    ),
                    if (done)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                              color: AppColors.carbs, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
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
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.subtext,
                            color: done ? AppColors.subtext : AppColors.text)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, height: 1.4, color: AppColors.subtext)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded, color: AppColors.subtext, size: 22),
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
            position: PopupMenuPosition.under,
            onSelected: (v) async {
              switch (v) {
                case 'done':
                  store.setDone(entry.id, !done);
                case 'edit':
                  final q = await QuantityDialog.show(
                    context,
                    title: '调整「${store.titleOf(entry)}」',
                    subtitle: '一份的克数由食材/组合餐定义',
                    initial: entry.servings,
                  );
                  if (q != null) store.setServings(entry.id, q);
                case 'delete':
                  final ok = await confirmDelete(context, '删除这条记录', '将从 ${entry.dateKey} 的${entry.type.label}中移除。');
                  if (ok) store.removeEntry(entry.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'done',
                  child: Row(children: [
                    Icon(done ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
                        size: 19, color: AppColors.carbs),
                    const SizedBox(width: 10),
                    Text(done ? '标记为未吃' : '标记为已吃', style: const TextStyle(fontSize: 14)),
                  ])),
              PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.tune_rounded, size: 19, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Text('调整份量', style: const TextStyle(fontSize: 14)),
                  ])),
              PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.danger),
                    const SizedBox(width: 10),
                    Text('删除', style: const TextStyle(fontSize: 14, color: AppColors.danger)),
                  ])),
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
                Text('${date.month}月${date.day}日',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text(weekdayLabel(date),
                    style: const TextStyle(fontSize: 13, color: AppColors.subtext)),
                const Spacer(),
                if (showTodayButton)
                  PressableScale(
                    onTap: onToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: ShapeDecoration(
                        color: AppColors.accentSoft,
                        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('回到今天',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent)),
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
