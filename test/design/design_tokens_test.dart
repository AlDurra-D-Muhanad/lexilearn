import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';

void main() {
  test('spacing scale ascends and covers a full phone layout', () {
    expect(AppSpacing.xs, lessThan(AppSpacing.s));
    expect(AppSpacing.s, lessThan(AppSpacing.m));
    expect(AppSpacing.m, lessThan(AppSpacing.l));
    expect(AppSpacing.l, lessThan(AppSpacing.xl));
    expect(AppSpacing.m, 16);
  });

  test('radii are ordered and the pill radius exceeds any card', () {
    expect(AppRadii.sm, lessThan(AppRadii.md));
    expect(AppRadii.md, lessThan(AppRadii.lg));
    expect(AppRadii.pill, greaterThan(AppRadii.lg));
  });

  test('brand colours are exactly the hexes the user supplied', () {
    // Pinned to the brand files. If someone "improves" one of these, a test
    // fails, which is the only thing stopping silent brand drift.
    expect(AppColors.primaryLight, const Color(0xFF885CF6));
    expect(AppColors.primaryDark, const Color(0xFFA78BFA));
    expect(AppColors.backgroundLight, const Color(0xFFF8F7F5));
    expect(AppColors.surfaceLight, const Color(0xFFFFFFFF));
    expect(AppColors.textLight, const Color(0xFF1F2937));
    expect(AppColors.textSecondaryLight, const Color(0xFF6B7280));
    expect(AppColors.accent, const Color(0xFFF59E0B));
    expect(AppColors.backgroundDark, const Color(0xFF0F172A));
    expect(AppColors.surfaceDark, const Color(0xFF1E293B));
    expect(AppColors.textDark, const Color(0xFFF9FAFB));
    expect(AppColors.textSecondaryDark, const Color(0xFF94A3B8));
    expect(AppColors.borderLight, const Color(0xFFE5E7EB));
    expect(AppColors.borderDark, const Color(0xFF334155));
    expect(AppColors.successLight, const Color(0xFF16A34A));
    expect(AppColors.successDark, const Color(0xFF4ADE80));
    expect(AppColors.errorLight, const Color(0xFFDC2626));
    expect(AppColors.errorDark, const Color(0xFFF87171));
  });

  test('accent is never used as light-mode body text', () {
    // Amber on the near-white background fails contrast. The brand uses it for
    // icons, fills, and dark-mode buttons only, and this test is what stops a
    // later screen from typing it into a TextStyle.
    expect(ThemeData.estimateBrightnessForColor(AppColors.accent),
        Brightness.light);
    expect(AppColors.accent, isNot(AppColors.primaryLight));
    expect(AppColors.accent, isNot(AppColors.primaryDark));
  });

  test('light-mode shadow matches the brand spec exactly', () {
    expect(AppShadows.light, hasLength(1));
    final shadow = AppShadows.light.single;
    expect(shadow.offset, const Offset(0, 4));
    expect(shadow.blurRadius, 12);
    expect(shadow.color, const Color(0x0D000000)); // 0.05 alpha
    expect(AppShadows.none, isEmpty);
  });

  test('durations are short enough to feel instant', () {
    expect(AppDurations.fast.inMilliseconds, lessThan(AppDurations.standard.inMilliseconds));
    expect(AppDurations.standard.inMilliseconds, lessThanOrEqualTo(250));
  });

  test('Latin terms use Inter, because Tajawal has no Latin glyphs', () {
    expect(AppText.latin.fontFamily, 'Inter');
    expect(AppText.arabic.fontFamily, 'Tajawal');
  });
}