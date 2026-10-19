import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';
import 'app_verdict_colors.dart';

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
      // The one role `ColorScheme` has no field for and this app needs: what a
      // *right* answer looks like. Installed here rather than in `light()` /
      // `dark()` so it is derived from the scheme it is mounted with — including
      // for the `fromColorScheme` caller, which passes a scheme of its own.
      extensions: <ThemeExtension<dynamic>>[AppVerdictColors.forScheme(scheme)],
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      // Every Arabic string in the app renders through this family. Latin runs
      // ask for Inter explicitly via AppText.
      fontFamily: arabicFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // A `Card` is the surface colour and the hairline, nothing more.
      // `CardThemeData` has no shadow field — only `clipBehavior`, `color`,
      // `shadowColor`, `surfaceTintColor`, `elevation`, `margin` and `shape` — so
      // the brand's `0 4px 12px rgba(0,0,0,0.05)` cannot be expressed here at all.
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
      // Three of the five families M3 elevates, zeroed here. This is the second
      // half of Amendment 6. The first half was `cardTheme.elevation` above; the
      // second was one `ElevatedButton`'s own `elevation: 0`, and **the
      // per-widget opt-out did not hold** — measured over `lib/ui/`, three
      // widgets shipped with no elevation override at all:
      // `quiz_result_screen.dart`'s `FilledButton`, `stats_screen.dart`'s
      // `_Notice` `OutlinedButton`, and `quiz_setup_screen.dart`'s `ActionChip`.
      // Only the ones somebody happened to remember were safe.
      //
      // **These three, not all of them.** `TextButton` and `IconButton` are
      // absent from this block on purpose, because neither needs it: both default
      // to **0.0** in every state — `text_button.dart:390` and
      // `icon_button.dart:1112-1113` (with `:1254`, `:1396` and `:1523` doing the
      // same for the other three `IconButton` variants) — and entries for them
      // would be more lines defending a value Material already gets right. Say
      // that rather than "every family". The families M3 *does* elevate are
      // `ElevatedButton`, `FilledButton`, `OutlinedButton`, `Chip` and
      // `ActionChip`; the last two are both covered by the `chipTheme` entry at
      // the bottom of this block, which `chip_theme.dart:432-437` names
      // explicitly.
      //
      // The defaults these replace, read out of this SDK rather than assumed:
      //
      // | Widget | resting | hovered | pressed | source |
      // |---|---|---|---|---|
      // | `ElevatedButton` | **1.0** | **3.0** | 1.0 | `elevated_button.dart:570-585` |
      // | `FilledButton` | 0.0 | **1.0** | 0.0 | `filled_button.dart:588-603` |
      // | `OutlinedButton` | 0.0 | 0.0 | 0.0 | `outlined_button.dart:512-513` |
      //
      // `ElevatedButton` is the Amendment-6 defect outright. **`FilledButton` is
      // the one a resting-state assertion would have missed**: it rests at 0 and
      // jumps to 1.0 on hover, which is `canvas.drawShadow` again — and a golden
      // cannot catch it, because a screenshot is taken with no pointer over
      // anything. `test/design/app_theme_test.dart` therefore resolves `hovered`
      // as well as the resting state.
      //
      // Three entries for one value because M3 gives each widget family its own
      // defaults and no single `buttonTheme` covers them. Pinned at two levels:
      // here by the theme test, and per screen by the *resolved* `ButtonStyle`
      // assertions in each screen's own test.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: const ButtonStyle(elevation: WidgetStatePropertyAll<double>(0.0)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: const ButtonStyle(elevation: WidgetStatePropertyAll<double>(0.0)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: const ButtonStyle(elevation: WidgetStatePropertyAll<double>(0.0)),
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
        // **A `Chip` is not a `Card`, so `cardTheme.elevation` says nothing
        // about it.** It is also already safe: `chip.dart:1350-1352` resolves
        // `widget.elevation ?? chipTheme.elevation ?? chipDefaults.elevation ??
        // 0`, so the last fallback is zero and M3 sets nothing above it. So these
        // two lines **pin an existing value rather than fix a defect**, and they
        // are here because the value is invisible in `cardTheme` and a reader has
        // no way to know it is already right. `pressElevation` resolves through
        // the same `?? 0` fallback.
        elevation: 0.0,
        pressElevation: 0.0,
      ),
    );
  }
}