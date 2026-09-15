import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';

/// iOS 连续曲率圆角（squircle）半径
BorderRadius squircle(double r) => BorderRadius.circular(r);

/// 可点元素通用按压反馈：按下轻微缩小 + 变暗回弹
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final HitTestBehavior behavior;
  final String? semanticLabel;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.965,
    this.behavior = HitTestBehavior.deferToChild,
    this.semanticLabel,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _down ? 0.86 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// iOS 风格白卡：连续圆角 + 极浅投影
class IosCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color color;
  final double radius;
  final List<BoxShadow>? shadows;

  const IosCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color = Colors.white,
    this.radius = 22,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: ShapeDecoration(
        color: color,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        shadows:
            shadows ??
            const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}

/// 液态玻璃表面配方：外层投影 + 连续圆角裁剪 + 高斯模糊 + 饱和度提升 +
/// 上亮下透的白色渐变 + 高光描边
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: squircle(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: squircle(radius),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE8F4FAF4), Color(0xD2EAF3EC)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// emoji 徽章：代替食物照片的圆形/圆角图标
class EmojiBadge extends StatelessWidget {
  final String emoji;
  final double size;
  final Color color;

  const EmojiBadge(
    this.emoji, {
    super.key,
    this.size = 48,
    this.color = AppColors.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: size * 0.52, height: 1.1)),
    );
  }
}

/// 单个营养指标：彩色竖条 + 数值 + 标签（参考设计稿卡片内样式）
class MacroStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool light; // 深色/渐变底上的浅色变体

  const MacroStat({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: light ? const Color(0x8AFFFFFF) : color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: light ? Colors.white : AppColors.text,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: light ? const Color(0xB8FFFFFF) : AppColors.subtext,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一行四个营养指标：热量 / 蛋白质 / 碳水 / 脂肪
class MacroRow extends StatelessWidget {
  final Nutrition n;
  final bool light;

  const MacroRow({super.key, required this.n, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MacroStat(
            value: '${n.calories.round()}',
            label: '千卡',
            color: AppColors.kcal,
            light: light,
          ),
        ),
        Expanded(
          child: MacroStat(
            value: '${fmtNum(n.protein)}g',
            label: '蛋白',
            color: AppColors.protein,
            light: light,
          ),
        ),
        Expanded(
          child: MacroStat(
            value: '${fmtNum(n.carbs)}g',
            label: '碳水',
            color: AppColors.carbs,
            light: light,
          ),
        ),
        Expanded(
          child: MacroStat(
            value: '${fmtNum(n.fat)}g',
            label: '脂肪',
            color: AppColors.fat,
            light: light,
          ),
        ),
      ],
    );
  }
}

/// 带每日目标的营养行：显示「实际 / 目标」，用于全天汇总
class MacroProgressRow extends StatelessWidget {
  final Nutrition n;
  final NutritionTargets targets;
  final bool light;

  const MacroProgressRow({
    super.key,
    required this.n,
    required this.targets,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    String value(double actual, double target) =>
        '${fmtNum(actual)}/${fmtNum(target)}g';
    return Row(
      children: [
        Expanded(
          child: MacroStat(
            value: fmtNum(targets.kcal),
            label: '千卡目标',
            color: AppColors.kcal,
            light: light,
          ),
        ),
        Expanded(
          child: MacroStat(
            value: value(n.protein, targets.protein),
            label: '蛋白',
            color: AppColors.protein,
            light: light,
          ),
        ),
        Expanded(
          child: MacroStat(
            value: value(n.carbs, targets.carbs),
            label: '碳水',
            color: AppColors.carbs,
            light: light,
          ),
        ),
        Expanded(
          child: MacroStat(
            value: value(n.fat, targets.fat),
            label: '脂肪',
            color: AppColors.fat,
            light: light,
          ),
        ),
      ],
    );
  }
}

/// 每日热量进度环
class CalorieRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final String valueText;
  final String unitText;

  const CalorieRing({
    super.key,
    required this.progress,
    required this.valueText,
    required this.unitText,
    this.size = 78,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(progress.clamp(0.0, 1.0)),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                valueText,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              Text(
                unitText,
                style: const TextStyle(fontSize: 9, color: Color(0xB8FFFFFF)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0x42FFFFFF);
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 应用背景：暖→冷纵向渐变 + 三团低饱和氛围光斑
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3E4), Color(0xFFF3F5FB), Color(0xFFEBF3EE)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: _blob(const Color(0x59FFC46B), const Color(0x00FFC46B), 340),
          ),
          Positioned(
            top: 220,
            left: -90,
            child: _blob(const Color(0x4D7DD8A3), const Color(0x007DD8A3), 300),
          ),
          Positioned(
            bottom: 140,
            right: -60,
            child: _blob(const Color(0x408B8AF0), const Color(0x008B8AF0), 320),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _blob(Color inner, Color outer, double size) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [inner, outer]),
      ),
    ),
  );
}

/// 周历条（周一起始），选中日蓝色圆形，今日白底描边
class WeekStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onTap;

  const WeekStrip({super.key, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final start = selected.subtract(Duration(days: selected.weekday - 1));
    final today = DateTime.now();
    return Row(
      children: List.generate(7, (i) {
        final day = DateTime(start.year, start.month, start.day + i);
        final isSel = isSameDay(day, selected);
        final isToday = isSameDay(day, today);
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(day),
            child: Column(
              children: [
                Text(
                  kWeekdayShort[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSel ? AppColors.accent : AppColors.subtext,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.accent
                        : (isToday ? Colors.white : Colors.transparent),
                    shape: BoxShape.circle,
                    border: (isToday && !isSel)
                        ? Border.all(color: AppColors.accent, width: 1.2)
                        : null,
                    boxShadow: isSel
                        ? const [
                            BoxShadow(
                              color: Color(0x440E9F6E),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSel || isToday
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSel
                          ? Colors.white
                          : (isToday ? AppColors.accent : AppColors.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

Future<bool> confirmDelete(
  BuildContext context,
  String title,
  String content,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(color: AppColors.subtext)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '删除',
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

/// 编辑页顶部条：取消 / 标题 / 保存（iOS 风格）
class EditorHeader extends StatelessWidget {
  final String title;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const EditorHeader({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onCancel,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '取消',
              style: TextStyle(fontSize: 15, color: AppColors.subtext),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        GestureDetector(
          onTap: onSave,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;

  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.subtext,
      ),
    );
  }
}

/// 白色圆角输入框
class RoundedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool numeric;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  const RoundedTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.numeric = false,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric ? [NumericTextFormatter()] : null,
      cursorColor: AppColors.accent,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.subtext,
        ),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 13, color: AppColors.subtext),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
    );
  }
}

/// 只允许输入数字与小数点
class NumericTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final reg = RegExp(r'^\d*\.?\d*$');
    if (reg.hasMatch(newValue.text)) return newValue;
    return oldValue;
  }
}

/// 克数调整对话框：直接输入克数 + 常用克数快捷项（「份」只是快捷输入）
class GramDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double initial;
  final List<double> quickGrams;

  const GramDialog({
    super.key,
    required this.title,
    required this.initial,
    this.subtitle,
    this.quickGrams = const [50, 100, 150, 200],
  });

  static Future<double?> show(
    BuildContext context, {
    required String title,
    required double initial,
    String? subtitle,
    List<double> quickGrams = const [50, 100, 150, 200],
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) => GramDialog(
        title: title,
        initial: initial,
        subtitle: subtitle,
        quickGrams: quickGrams,
      ),
    );
  }

  @override
  State<GramDialog> createState() => _GramDialogState();
}

class _GramDialogState extends State<GramDialog> {
  late final TextEditingController _c = TextEditingController(
    text: fmtNum(widget.initial),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null)
            Text(
              widget.subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.subtext),
            ),
          const SizedBox(height: 16),
          RoundedTextField(
            controller: _c,
            numeric: true,
            suffix: 'g',
            hint: '输入克数',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.quickGrams.map((g) {
              final selected = _value == g;
              return PressableScale(
                onTap: () => setState(() => _c.text = fmtNum(g)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accentSoft : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    '${fmtNum(g)}g',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.accent : AppColors.subtext,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _value > 0
              ? () => Navigator.of(context).pop(_value)
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 数据加载失败视图：给出重试入口，不再无限转圈
class StoreErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const StoreErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text(
              '数据加载失败',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.subtext),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
