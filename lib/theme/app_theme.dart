import 'package:flutter/material.dart';

import '../models/stock_movement.dart';

/// CCTT 设计系统 —— 工业精准美学（Industrial Precision）
///
/// 设计取材于 App 自身所处的世界：地磅、货物标签、称重秤 LED 数字。
/// 刻意避开 Material 默认的 Teal / 紫色种子色方案，改用工业蓝灰做骨架，
/// 用称重秤上那种橙红色 LED 做唯一的强调色（全 App 只有一处强调色，
/// 集中花在「金额」和「主操作按钮」上）。
///
/// 字体说明：项目 pubspec.yaml 未声明 fonts:，也没有 .ttf 资源，
/// 因此这里不引用任何自定义字体，避免构建后静默回退成系统字体。
/// 层级完全由「字重 + 字号 + 字距」承担，数字用等宽字体保证竖向对齐
/// （账目类界面里数字对齐比字形好看更重要）。
class CCTTTheme {
  CCTTTheme._();

  // ─────────────────────────── 色彩令牌 ───────────────────────────

  /// 骨架色：工业蓝灰，用于 AppBar、深色区块、主要文字
  static const Color primaryDark = Color(0xFF1A2332);
  static const Color primaryMid = Color(0xFF2D3E50);
  static const Color primaryLight = Color(0xFF4A5F7F);

  /// 强调色：称重秤 LED 橙红。全 App 唯一的高饱和色，克制使用。
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color accentOrangeLight = Color(0xFFFF8A50);
  static const Color accentAmber = Color(0xFFFFA726);

  /// 语义色：单据类型
  static const Color typeInbound = Color(0xFF2E7D32); // 入库
  static const Color typeOutbound = Color(0xFFC62828); // 出库
  static const Color typeSupply = Color(0xFFEF6C00); // 进货

  /// 语义色：同步状态
  static const Color statusSynced = Color(0xFF00A344);
  static const Color statusPending = Color(0xFFFFB300);
  static const Color statusSyncing = Color(0xFF1E88E5);
  static const Color statusFailed = Color(0xFFD32F2F);

  /// 中性色阶
  static const Color neutral900 = Color(0xFF1A1A1A);
  static const Color neutral700 = Color(0xFF616161);
  static const Color neutral500 = Color(0xFF9E9E9E);
  static const Color neutral300 = Color(0xFFE0E0E0);
  static const Color neutral100 = Color(0xFFF5F5F5);
  static const Color neutral50 = Color(0xFFFAFAFA);

  // ─────────────────────────── 间距 / 圆角 ───────────────────────────

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space6 = 24;
  static const double space8 = 32;

  /// 圆角刻意保持克制（最大 16dp）：这是一个记账工具，
  /// 过大的圆角会让它看起来像消费类 App，削弱「单据」的严肃感。
  static const double radiusSmall = 4;
  static const double radiusMedium = 8;
  static const double radiusLarge = 12;
  static const double radiusXLarge = 16;

  /// 数字专用等宽字体族（系统内置，无需声明资源）
  static const String monoFont = 'monospace';

  // ─────────────────────────── ColorScheme ───────────────────────────

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primaryDark,
    onPrimary: Colors.white,
    primaryContainer: primaryMid,
    onPrimaryContainer: Colors.white,
    secondary: accentOrange,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFE5DB),
    onSecondaryContainer: Color(0xFF8A2E10),
    tertiary: primaryLight,
    onTertiary: Colors.white,
    error: statusFailed,
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF8C1D18),
    surface: Colors.white,
    onSurface: neutral900,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: neutral50,
    surfaceContainer: neutral100,
    surfaceContainerHigh: Color(0xFFEEEEEE),
    surfaceContainerHighest: Color(0xFFE8EAED),
    onSurfaceVariant: neutral700,
    outline: neutral300,
    outlineVariant: Color(0xFFEDEDED),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: primaryDark,
    onInverseSurface: Colors.white,
    inversePrimary: accentOrangeLight,
  );

  // ─────────────────────────── ThemeData ───────────────────────────

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _lightScheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: neutral100,
      dividerColor: neutral300,

      textTheme: _textTheme(base.textTheme),

      appBarTheme: const AppBarTheme(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: IconThemeData(color: Colors.white, size: 22),
      ),

      // 卡片用 1px 描边代替阴影：单据列表里阴影叠加会让页面显得脏，
      // 描边更接近纸质单据的边界感。
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: neutral300),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space3,
          vertical: space3,
        ),
        border: _inputBorder(neutral300),
        enabledBorder: _inputBorder(neutral300),
        focusedBorder: _inputBorder(accentOrange, width: 2),
        errorBorder: _inputBorder(statusFailed),
        focusedErrorBorder: _inputBorder(statusFailed, width: 2),
        labelStyle: const TextStyle(color: neutral700, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: accentOrange,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: neutral500, fontSize: 14),
        prefixIconColor: neutral700,
        suffixIconColor: neutral700,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentOrange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: neutral300,
          disabledForegroundColor: neutral500,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: space6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryMid,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: space4),
          side: const BorderSide(color: neutral300, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentOrange,
        foregroundColor: Colors.white,
        elevation: 2,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: neutral100,
        side: const BorderSide(color: neutral300),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: neutral700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFullish),
        ),
        padding: const EdgeInsets.symmetric(horizontal: space2, vertical: 2),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXLarge),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: neutral900,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryDark,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: neutral700,
        contentPadding: EdgeInsets.symmetric(horizontal: space4),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusXLarge),
          ),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentOrange,
        linearTrackColor: neutral300,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentOrange
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentOrange.withValues(alpha: 0.35)
              : neutral300,
        ),
      ),
    );
  }

  static const double radiusFullish = 999;

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// 层级靠字重和字距拉开，而不是靠颜色 —— 颜色留给语义。
  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: neutral900,
        letterSpacing: -0.2,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: neutral900,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: neutral900,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: neutral900,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, color: neutral900),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, color: neutral700),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12, color: neutral700),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: neutral700,
        letterSpacing: 0.8,
      ),
    );
  }

  // ─────────────────────────── 语义辅助 ───────────────────────────

  static Color typeColor(MovementType type) {
    switch (type) {
      case MovementType.inbound:
        return typeInbound;
      case MovementType.outbound:
        return typeOutbound;
      case MovementType.supply:
        return typeSupply;
    }
  }

  static String typeLabel(MovementType type) {
    switch (type) {
      case MovementType.inbound:
        return '入库';
      case MovementType.outbound:
        return '出库';
      case MovementType.supply:
        return '进货';
    }
  }

  static IconData typeIcon(MovementType type) {
    switch (type) {
      case MovementType.inbound:
        return Icons.south_west;
      case MovementType.outbound:
        return Icons.north_east;
      case MovementType.supply:
        return Icons.local_shipping_outlined;
    }
  }

  static Color syncColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return statusSynced;
      case SyncStatus.pending:
        return statusPending;
      case SyncStatus.syncing:
        return statusSyncing;
      case SyncStatus.failed:
        return statusFailed;
    }
  }

  static String syncLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return '已同步';
      case SyncStatus.pending:
        return '待同步';
      case SyncStatus.syncing:
        return '同步中';
      case SyncStatus.failed:
        return '同步失败';
    }
  }

  /// 金额 / 重量专用样式：等宽 + tabular figures，保证列表里小数点竖向对齐
  static TextStyle numeric({
    double size = 16,
    FontWeight weight = FontWeight.w700,
    Color color = neutral900,
  }) {
    return TextStyle(
      fontFamily: monoFont,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

