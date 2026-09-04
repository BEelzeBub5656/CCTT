import 'package:flutter/material.dart';

/// CCTT 设计色板 —— 「毛纺温暖」色系。
///
/// 来源：Web 端 admin 已有色板 + 2026-08-30 三 agent 美化组会仲裁 + WCAG 实测。
/// 规则：品牌主色 [brand] 只做装饰（大标题/图标/选中边框），
///       所有承载文字的颜色一律使用 deep 变体（白字对比度 ≥4.5:1）。
/// 详见 Obsidian Wiki：杂项/CCTT-美化组会-2026-08-30.md
abstract final class CcttColors {
  // ---- 品牌 ----
  /// 品牌主色（装饰用途，禁止小文字）
  static const Color brand = Color(0xFFC4724F);

  /// 主行动色（按钮背景/强调文字，白字 5.01:1）
  static const Color brandDeep = Color(0xFFA85A3A);

  /// 发光/渐变亮色
  static const Color brandGlow = Color(0xFFD4896B);

  /// 品牌浅底（大面积容器背景）
  static const Color brandLight = Color(0xFFF5E6DC);

  // ---- 业务状态色（deep 变体，白字 ≥4.5:1）----
  static const Color greenDeep = Color(0xFF6E7B53); // 入库/进货
  static const Color greenBg = Color(0xFFEEF0E4);
  static const Color redDeep = Color(0xFFC0524D); // 错误/作废
  static const Color redBg = Color(0xFFFAF0EE);
  static const Color amberDeep = Color(0xFF91722C); // 警告/待处理
  static const Color amberBg = Color(0xFFFAF3E0);
  static const Color blueDeep = Color(0xFF677985); // 信息/中性强调
  static const Color blueBg = Color(0xFFEDF1F4);

  // ---- 中性 ----
  /// 正文色（深栗色，白底 15.9:1，户外日光可读）
  static const Color ink = Color(0xFF2D1F14);

  /// 暖白背景
  static const Color surface = Color(0xFFFFFDFB);
  static const Color surfaceVariant = Color(0xFFEFE6DE);
  static const Color onSurfaceVariant = Color(0xFF58493C);
  static const Color outline = Color(0xFFA19288);
  static const Color outlineVariant = Color(0xFFD4C7BC);

  /// 卡片层级背景
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFFBF7F3);
  static const Color surfaceContainer = Color(0xFFF7EFE8);
  static const Color surfaceContainerHigh = Color(0xFFF2E8DF);

  // ---- 容器内文字（on*Container，各自 ≥4.5:1）----
  static const Color onPrimaryContainerInk = Color(0xFF9E5537);
  static const Color onSecondaryContainerInk = Color(0xFF65714C);
  static const Color onTertiaryContainerInk = Color(0xFF876A29);
  static const Color onErrorContainerInk = Color(0xFFB44D49);
  static const Color onInfoContainerInk = Color(0xFF60707C);
}

/// 品牌与状态色的运行时扩展（页面通过 Theme.of(context) 取用）。
@immutable
class CcttBrandColors extends ThemeExtension<CcttBrandColors> {
  const CcttBrandColors({
    required this.brand,
    required this.brandDeep,
    required this.brandGlow,
    required this.brandLight,
    required this.greenDeep,
    required this.redDeep,
    required this.amberDeep,
    required this.blueDeep,
  });

  final Color brand;
  final Color brandDeep;
  final Color brandGlow;
  final Color brandLight;
  final Color greenDeep;
  final Color redDeep;
  final Color amberDeep;
  final Color blueDeep;

  static const CcttBrandColors light = CcttBrandColors(
    brand: CcttColors.brand,
    brandDeep: CcttColors.brandDeep,
    brandGlow: CcttColors.brandGlow,
    brandLight: CcttColors.brandLight,
    greenDeep: CcttColors.greenDeep,
    redDeep: CcttColors.redDeep,
    amberDeep: CcttColors.amberDeep,
    blueDeep: CcttColors.blueDeep,
  );

  @override
  CcttBrandColors copyWith({
    Color? brand,
    Color? brandDeep,
    Color? brandGlow,
    Color? brandLight,
    Color? greenDeep,
    Color? redDeep,
    Color? amberDeep,
    Color? blueDeep,
  }) {
    return CcttBrandColors(
      brand: brand ?? this.brand,
      brandDeep: brandDeep ?? this.brandDeep,
      brandGlow: brandGlow ?? this.brandGlow,
      brandLight: brandLight ?? this.brandLight,
      greenDeep: greenDeep ?? this.greenDeep,
      redDeep: redDeep ?? this.redDeep,
      amberDeep: amberDeep ?? this.amberDeep,
      blueDeep: blueDeep ?? this.blueDeep,
    );
  }

  @override
  CcttBrandColors lerp(CcttBrandColors? other, double t) {
    if (other is! CcttBrandColors) return this;
    return CcttBrandColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandDeep: Color.lerp(brandDeep, other.brandDeep, t)!,
      brandGlow: Color.lerp(brandGlow, other.brandGlow, t)!,
      brandLight: Color.lerp(brandLight, other.brandLight, t)!,
      greenDeep: Color.lerp(greenDeep, other.greenDeep, t)!,
      redDeep: Color.lerp(redDeep, other.redDeep, t)!,
      amberDeep: Color.lerp(amberDeep, other.amberDeep, t)!,
      blueDeep: Color.lerp(blueDeep, other.blueDeep, t)!,
    );
  }
}
