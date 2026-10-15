import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

void main() {
  test('light and dark themes use the two brand primaries', () {
    expect(AppTheme.light().colorScheme.primary, isNot(AppTheme.dark().colorScheme.primary));
    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().useMaterial3, isTrue);
  });

  test('cards use the brand surface colour and a rounded outline', () {
    final light = AppTheme.light();
    expect(light.cardTheme.color, AppColors.surfaceLight);
    final lightShape = light.cardTheme.shape as RoundedRectangleBorder;
    expect(lightShape.side.color, AppColors.borderLight);
    expect(lightShape.borderRadius, BorderRadius.circular(AppRadii.md));

    final darkShape = AppTheme.dark().cardTheme.shape as RoundedRectangleBorder;
    expect(darkShape.side.color, AppColors.borderDark);
  });

  test('search fields are pill shaped, matching the artwork', () {
    final decoration = AppTheme.light().inputDecorationTheme;
    expect(decoration.filled, isTrue);
    expect(decoration.border, isA<OutlineInputBorder>());
    final border = decoration.border as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(AppRadii.pill));
    expect(decoration.fillColor, AppColors.surfaceLight);
    expect(decoration.hintStyle?.color, AppColors.textSecondaryLight);
  });

  test('both themes bind Tajawal, which is what renders every Arabic string', () {
    // `ThemeData` takes a `fontFamily` but exposes no getter for it: the family
    // is baked into every style of the text theme, which is what a screen
    // actually renders. So the assertion is made there instead. Covering four
    // roles in both themes is strictly more than checking one field twice.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final styles = theme.textTheme;
      expect(styles.displayLarge?.fontFamily, 'Tajawal');
      expect(styles.titleLarge?.fontFamily, 'Tajawal');
      expect(styles.bodyMedium?.fontFamily, 'Tajawal');
      expect(styles.labelSmall?.fontFamily, 'Tajawal');
    }
  });

  test('scaffold backgrounds match the brand, not Material\'s default', () {
    expect(AppTheme.light().scaffoldBackgroundColor, AppColors.backgroundLight);
    expect(AppTheme.dark().scaffoldBackgroundColor, AppColors.backgroundDark);
  });

  test('fromColorScheme is a pure function of the scheme', () {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primaryLight);
    expect(AppTheme.fromColorScheme(scheme).colorScheme.primary, scheme.primary);
  });
}