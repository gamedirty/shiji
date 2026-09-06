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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 116),
        children: [
          _header(context, now),
          const SizedBox(height: 20),
          _dateRow(date, now),
          const SizedBox(height: 12),
          WeekStrip(selected: date, onTap: widget.onDateChanged),
          const SizedBox(height: 24),
          Text(
            isSameDay(date, now) ? '今天的安排' : '${date.month}月${date.day}日 的安排',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 12),
          _summaryCard(totals),
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
          onPressed: () => widget.onDateChanged(now),
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
        if (!isToday) ...[
          const Spacer(),
          TextButton(
            onPressed: () => widget.onDateChanged(now),
            child: const Text('今天', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _summaryCard(Nutrition totals) {
    return IosCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('全天合计', style: TextStyle(fontSize: 12, color: AppColors.subtext)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${totals.calories.round()}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(width: 4),
              const Text('千卡', style: TextStyle(fontSize: 13, color: AppColors.subtext)),
            ],
          ),
          const SizedBox(height: 14),
          MacroRow(n: totals),
        ],
      ),
    );
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
    return GestureDetector(
      onTap: () => setState(() => _filter = t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18)),
          color: selected ? null : Colors.white,
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF37A5FF), Color(0xFF0A7AFF)],
                )
              : null,
          shadows: selected
              ? const [
                  BoxShadow(color: Color(0x590A7AFF), blurRadius: 12, offset: Offset(0, 5)),
                ]
              : const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.text)),
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
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => store.setDone(entry.id, !done),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: done ? 0.45 : 1,
                  child: EmojiBadge(store.emojiOf(entry), size: 54),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.subtext,
                        color: done ? AppColors.subtext : AppColors.text)),
                const SizedBox(height: 3),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.subtext)),
                const SizedBox(height: 10),
                MacroRow(n: n),
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
    );
  }
}
