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
    surfaceContainerLowest: CcttColors.surfaceContainerLowest,
    surfaceContainerLow: CcttColors.surfaceContainerLow,
    surfaceContainer: CcttColors.surfaceContainer,
    surfaceContainerHigh: CcttColors.surfaceContainerHigh,
    surfaceContainerHighest: CcttColors.surfaceVariant,
    onSurfaceVariant: CcttColors.onSurfaceVariant,
    outline: CcttColors.outline,
    outlineVariant: CcttColors.outlineVariant,
  );
}

/// 构建 CCTT 亮色主题。
ThemeData buildCcttTheme() {
  final ColorScheme scheme = _buildScheme();
  final TextTheme baseTextTheme = ThemeData.light().textTheme.apply(
        bodyColor: CcttColors.ink,
        displayColor: CcttColors.ink,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CcttColors.surface,
    extensions: const <ThemeExtension<dynamic>>[CcttBrandColors.light],
    textTheme: baseTextTheme.copyWith(
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.4),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.4),
      bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.35),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: CcttColors.surface,
      foregroundColor: CcttColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: CcttColors.ink.withValues(alpha: 0.08),
      centerTitle: true,
      titleTextStyle: baseTextTheme.titleLarge?.copyWith(
        color: CcttColors.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      iconTheme: const IconThemeData(color: CcttColors.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: CcttColors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: CcttColors.ink.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CcttColors.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CcttColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CcttColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CcttColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CcttColors.brandDeep, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
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
    listTileTheme: const ListTileThemeData(
      iconColor: CcttColors.onSurfaceVariant,
      textColor: CcttColors.ink,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: CcttColors.onSurfaceVariant,
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 46),
        side: const BorderSide(color: CcttColors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: CcttColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: baseTextTheme.titleLarge?.copyWith(
        color: CcttColors.ink,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CcttColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: CcttColors.surface,
      showDragHandle: true,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: CcttColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: CcttColors.surfaceContainerLow,
      selectedColor: CcttColors.brandLight,
      side: const BorderSide(color: CcttColors.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(color: CcttColors.onSurfaceVariant),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CcttColors.brandDeep,
      linearTrackColor: CcttColors.brandLight,
      circularTrackColor: CcttColors.brandLight,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: CcttColors.brandDeep,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}
