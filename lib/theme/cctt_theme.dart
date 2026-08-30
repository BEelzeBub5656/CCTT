import 'package:flutter/material.dart';

import 'cctt_colors.dart';

/// CCTT 全局主题构建。
///
/// 设计原则（2026-08-30 组会仲裁）：
/// 1. 主色收敛到 Web 端「毛纺温暖」色系，移动端向 Web 对齐；
/// 2. 所有承载文字的颜色使用 deep 变体（WCAG AA ≥4.5:1）；
/// 3. 正文用深栗色 ink，保证户外日光可读；
/// 4. 纯视觉主题：不改变任何交互结构与操作路径。
ColorScheme _buildScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: CcttColors.brandDeep,
    onPrimary: Colors.white,
    primaryContainer: CcttColors.brandLight,
    onPrimaryContainer: CcttColors.onPrimaryContainerInk,
    secondary: CcttColors.greenDeep,
    onSecondary: Colors.white,
    secondaryContainer: CcttColors.greenBg,
    onSecondaryContainer: CcttColors.onSecondaryContainerInk,
    tertiary: CcttColors.amberDeep,
    onTertiary: Colors.white,
    tertiaryContainer: CcttColors.amberBg,
    onTertiaryContainer: CcttColors.onTertiaryContainerInk,
    error: CcttColors.redDeep,
    onError: Colors.white,
    errorContainer: CcttColors.redBg,
    onErrorContainer: CcttColors.onErrorContainerInk,
    surface: CcttColors.surface,
    onSurface: CcttColors.ink,
    surfaceContainerHighest: CcttColors.surfaceVariant,
    onSurfaceVariant: CcttColors.onSurfaceVariant,
    outline: CcttColors.outline,
    outlineVariant: CcttColors.outlineVariant,
  );
}

/// 构建 CCTT 亮色主题。
ThemeData buildCcttTheme() {
  final ColorScheme scheme = _buildScheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CcttColors.surface,
    extensions: const <ThemeExtension<dynamic>>[CcttBrandColors.light],

    appBarTheme: const AppBarTheme(
      backgroundColor: CcttColors.surface,
      foregroundColor: CcttColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),

    cardTheme: CardThemeData(
      color: CcttColors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: CcttColors.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CcttColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CcttColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CcttColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CcttColors.brandDeep, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CcttColors.redDeep),
      ),
      labelStyle: const TextStyle(color: CcttColors.onSurfaceVariant),
      hintStyle: const TextStyle(color: CcttColors.onSurfaceVariant),
    ),

    dividerTheme: const DividerThemeData(
      color: CcttColors.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CcttColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: CcttColors.brandLight,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final bool selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          color: selected ? CcttColors.brandDeep : CcttColors.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final bool selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? CcttColors.brandDeep : CcttColors.onSurfaceVariant,
        );
      }),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: CcttColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
