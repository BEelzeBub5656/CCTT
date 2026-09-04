import 'package:cctt/theme/cctt_colors.dart';
import 'package:cctt/theme/cctt_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warm theme exposes consistent low-risk component styling', () {
    final theme = buildCcttTheme();

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, CcttColors.brandDeep);
    expect(theme.scaffoldBackgroundColor, CcttColors.surface);
    expect(theme.extension<CcttBrandColors>(), isNotNull);
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.cardTheme.elevation, 0.5);
    expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w600);
    expect(theme.progressIndicatorTheme.color, CcttColors.brandDeep);
  });
}
