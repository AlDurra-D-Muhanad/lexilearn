import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

class AppTheme {
  const AppTheme._();

  /// The Arabic face. Every Arabic string in the app renders through it.
  ///
  /// Named here because `Typography` bakes the platform's default family into
  /// each text role, and the recoloured text theme built below is merged over
  /// the one `ThemeData` derives — so both halves have to name the same family
  /// or the merge quietly puts Roboto back.
  static const String arabicFamily = 'Tajawal';

  static ThemeData light() => fromColorScheme(_schemeFor(Brightness.light));

  static ThemeData dark() => fromColorScheme(_schemeFor(Brightness.dark));

  /// Builds the brand palette for a brightness.
  ///
  /// `ColorScheme.fromSeed` derives every role from the seed through Material's
  /// tonal palette, and those tones are *not* the brand's: seeding with
  /// `#885CF6` yields a `primary` of `#65558F`, a dusty plum, not the purple the
  /// artwork specifies. So the seed is kept for the roles it gets right — the
  /// `*Container` tones, `surfaceContainer*`, `inverse*`, `tertiary` — and every
  /// role the brand pins by hex is overwritten underneath it.
  ///
  /// This is deliberately not `fromColorScheme`'s job. A `ColorScheme` is
  /// immutable, so a caller who brings their own scheme cannot have the brand
  /// recovered from it, and a screen that read `colorScheme.primary` would get
  /// whatever the caller happened to pass. `light()` and `dark()` therefore go
  /// through here, and `fromColorScheme` stays a pure function for the rare
  /// caller that genuinely owns its scheme.
  static ColorScheme _schemeFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ColorScheme.fromSeed(
      seedColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      onPrimary: isDark ? AppColors.backgroundDark : AppColors.surfaceLight,
      secondary: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      onSecondary: isDark ? AppColors.backgroundDark : AppColors.surfaceLight,
      surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.textDark : AppColors.textLight,
      onSurfaceVariant:
          isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
      outline: isDark ? AppColors.borderDark : AppColors.borderLight,
      outlineVariant: isDark ? AppColors.borderDark : AppColors.borderLight,
      error: isDark ? AppColors.errorDark : AppColors.errorLight,
    );
  }

  /// The Material 3 text roles, recoloured to the brand's ink.
  ///
  /// Without this, every stock role keeps the colour `Typography` derived from
  /// the seed — `#1D1B20` on light — instead of the brand's `#1F2937`.
  static TextTheme _textThemeFor(Brightness brightness) {
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final base =
        brightness == Brightness.dark ? typography.white : typography.black;
    final ink = brightness == Brightness.dark ? AppColors.textDark : AppColors.textLight;
    return base.apply(fontFamily: arabicFamily, bodyColor: ink, displayColor: ink);
  }

  static ThemeData fromColorScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final textTheme = _textThemeFor(scheme.brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      // Every Arabic string in the app renders through this family. Latin runs
      // ask for Inter explicitly via AppText.
      fontFamily: arabicFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // A `Card` is the surface colour and the hairline, nothing more.
      // `CardThemeData` has no shadow field — only clipBehavior, color,
      // shadowColor, surfaceTintColor, elevation, margin and shape — so the
      // brand's `0 4px 12px rgba(0,0,0,0.05)` cannot be expressed here at all.
      // Material's own elevation shadow is not a substitute: at elevation 1 it
      // is roughly 4x the brand's umbra alpha and geometrically unrelated, and
      // the test rasteriser strokes it as an opaque black keyline. Elevation
      // therefore stays at 0, and AppSurface composes the real thing where the
      // surface is built.
      cardTheme: CardThemeData(
        elevation: 0,
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
        // Material 3 does NOT paint a filled field's outline from `border`. It
        // synthesises it inside the decorator from `colorScheme.onSurfaceVariant`,
        // and it picks `enabledBorder` / `focusedBorder` / `disabledBorder` to do
        // so — `border` only fills the gap if none of the three is set. All three
        // used to be null here, so every input in the app fell back to the
        // muted-text role and drew its outline in `#6B7280` instead of the brand
        // hairline. Measured: overriding `onSurfaceVariant` to `#00FF00` and
        // rasterising produced a `#00FF00` border.
        //
        // `onSurfaceVariant` itself is deliberately left alone — it is correctly
        // the muted text role, and recolouring it to fix a border would
        // recolour every muted string in the app. Pinned by
        // `test/design/app_theme_test.dart` and by
        // `test/design/input_outline_test.dart`.
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          borderSide: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          borderSide: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        // Focus reads as a colour from the palette — the brand purple, at the
        // 2px Material draws a focused outline — rather than as a heavier grey.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          borderSide: BorderSide(color: scheme.primary, width: 2),
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