import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => fromColorScheme(ColorScheme.fromSeed(
      seedColor: AppColors.primaryLight, brightness: Brightness.light));

  static ThemeData dark() => fromColorScheme(ColorScheme.fromSeed(
      seedColor: AppColors.primaryDark, brightness: Brightness.dark));

  static ThemeData fromColorScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      // Every Arabic string in the app renders through this family.
      fontFamily: 'Tajawal',
      // Brand separates surfaces with a soft shadow in light mode and a
      // hairline in dark mode, where a shadow is invisible. Both modes keep the
      // hairline — the brand asks for "soft borders and a light shadow", not one
      // or the other — but only light mode gets elevation, because a shadow on
      // a dark surface is invisible anyway. The surface tint is turned off so
      // the shadow stays neutral black instead of taking a purple cast; the
      // exact brand geometry lives in AppShadows.light for any surface that
      // draws its own BoxDecoration.
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        hintStyle: TextStyle(
          color:
              isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
        // The artwork's search field is a full pill.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          borderSide: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.m,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.borderDark : AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            color: isDark ? AppColors.textDark : AppColors.textLight,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Tajawal',
          color: isDark ? AppColors.textDark : AppColors.textLight,
        ),
      ),
    );
  }
}