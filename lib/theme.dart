import 'package:flutter/material.dart';

/// 品牌主色（Indigo Blue）
const Color kBrandPrimary = Color(0xFF4C6FFF);

/// 品牌辅色（Sky Blue），用于渐变
const Color kBrandAccent = Color(0xFF38BDF8);

/// 品牌渐变（页头 / 主按钮）
const LinearGradient kBrandGradient = LinearGradient(
  colors: <Color>[kBrandPrimary, kBrandAccent],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// 全局主题（浅色 / 深色），卡片、输入框、按钮统一样式。
ThemeData buildGiWiFiTheme([Brightness brightness = Brightness.light]) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandPrimary,
    brightness: brightness,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: isDark ? Colors.transparent : const Color(0xFFE3E8F2),
    ),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? null : const Color(0xFFF2F5FB),
    splashFactory: InkRipple.splashFactory,
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? scheme.surfaceContainerHigh : const Color(0xFFF1F4FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .55),
      ),
      border: inputBorder,
      enabledBorder: inputBorder,
      disabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
