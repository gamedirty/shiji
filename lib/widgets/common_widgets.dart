import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';

/// iOS 连续曲率圆角（squircle）半径
BorderRadius squircle(double r) => BorderRadius.circular(r);

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
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius)),
        shadows: shadows ??
            const [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4))],
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

  const GlassSurface({super.key, required this.child, required this.radius, this.margin, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: squircle(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 6)),
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
                colors: [Color(0x8CFFFFFF), Color(0x40FFFFFF)],
              ),
              border: Border.all(color: const Color(0x73FFFFFF), width: 1),
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

  const EmojiBadge(this.emoji, {super.key, this.size = 48, this.color = AppColors.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.32)),
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

  const MacroStat({super.key, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 34,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.15)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.subtext, height: 1.2)),
          ],
        ),
      ],
    );
  }
}

/// 一行四个营养指标：热量 / 蛋白质 / 碳水 / 脂肪
class MacroRow extends StatelessWidget {
  final Nutrition n;

  const MacroRow({super.key, required this.n});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: MacroStat(value: '${n.calories.round()}', label: '千卡', color: AppColors.kcal)),
        Expanded(child: MacroStat(value: '${fmtNum(n.protein)}g', label: '蛋白', color: AppColors.protein)),
        Expanded(child: MacroStat(value: '${fmtNum(n.carbs)}g', label: '碳水', color: AppColors.carbs)),
        Expanded(child: MacroStat(value: '${fmtNum(n.fat)}g', label: '脂肪', color: AppColors.fat)),
      ],
    );
  }
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
                Text(kWeekdayShort[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSel ? AppColors.accent : AppColors.subtext)),
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
                        ? const [BoxShadow(color: Color(0x440A7AFF), blurRadius: 10, offset: Offset(0, 4))]
                        : null,
                  ),
                  child: Text('${day.day}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSel || isToday ? FontWeight.w700 : FontWeight.w500,
                          color: isSel
                              ? Colors.white
                              : (isToday ? AppColors.accent : AppColors.text))),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 份数调整对话框（步进 0.5 份）
class QuantityDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double initial;

  const QuantityDialog({super.key, required this.title, required this.initial, this.subtitle});

  static Future<double?> show(BuildContext context,
      {required String title, required double initial, String? subtitle}) {
    return showDialog<double>(
      context: context,
      builder: (_) => QuantityDialog(title: title, initial: initial, subtitle: subtitle),
    );
  }

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late double _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null)
            Text(widget.subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.subtext)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepButton(Icons.remove_rounded, _v > 0.5 ? () => setState(() => _v -= 0.5) : null),
              const SizedBox(width: 20),
              Text('${fmtNum(_v)} 份',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 20),
              _stepButton(Icons.add_rounded, () => setState(() => _v += 0.5)),
            ],
          ),
        ],
      ),
      actions: [
        OutlinedButton(
            onPressed: () => Navigator.of(context).pop(null), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_v), child: const Text('确定')),
      ],
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.bg : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
        ),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 22, color: onTap == null ? AppColors.subtext : AppColors.accent),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String title, String content) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: AppColors.subtext))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700))),
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

  const EditorHeader(
      {super.key, required this.title, required this.onCancel, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onCancel,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('取消', style: TextStyle(fontSize: 15, color: AppColors.subtext)),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
        GestureDetector(
          onTap: onSave,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('保存',
                style: TextStyle(
                    fontSize: 15,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700)),
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
    return Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtext));
  }
}

/// 白色圆角输入框
class RoundedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool numeric;
  final String? suffix;

  const RoundedTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.numeric = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: numeric ? [NumericTextFormatter()] : null,
      cursorColor: AppColors.accent,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.subtext),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 13, color: AppColors.subtext),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.transparent)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
      ),
    );
  }
}

/// 只允许输入数字与小数点
class NumericTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final reg = RegExp(r'^\d*\.?\d*$');
    if (reg.hasMatch(newValue.text)) return newValue;
    return oldValue;
  }
}
