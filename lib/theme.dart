import 'package:flutter/material.dart';

import 'models.dart';

/// iOS 风格配色
class AppColors {
  static const bg = Color(0xFFF2F3F7);
  static const card = Colors.white;
  static const accent = Color(0xFF0E9F6E); // 新鲜墨绿
  static const accentSoft = Color(0x170E9F6E);
  static const text = Color(0xFF1C1C1E);
  static const subtext = Color(0xFF8A8F98);
  static const divider = Color(0xFFECECF0);

  // 三大营养素 / 热量
  static const kcal = Color(0xFFFF9F0A);
  static const protein = Color(0xFF0A84FF);
  static const carbs = Color(0xFF34C759);
  static const fat = Color(0xFFFF453A);
  static const danger = Color(0xFFFF3B30);
}

/// 餐段主题色（UI 层职责，不进入领域模型）
extension MealTypeColorX on MealType {
  Color get accent => switch (this) {
    MealType.breakfast => const Color(0xFFFF9500), // 晨光橙
    MealType.lunch => const Color(0xFF30B15C), // 活力绿
    MealType.dinner => const Color(0xFF5E5CE6), // 静夜紫
    MealType.snack => const Color(0xFFFF2D78), // 元气粉
  };

  Color get accentSoft => accent.withValues(alpha: 0.12);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamilyFallback: const [
      'PingFang SC',
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Helvetica Neue',
      'Segoe UI',
    ],
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.accent,
          secondary: AppColors.accent,
          surface: Colors.white,
        ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    splashFactory: InkRipple.splashFactory,
    splashColor: AppColors.accent.withValues(alpha: 0.12),
    highlightColor: AppColors.accent.withValues(alpha: 0.06),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xE6222226),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 14,
        height: 1.45,
        color: AppColors.text,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size(64, 44),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
