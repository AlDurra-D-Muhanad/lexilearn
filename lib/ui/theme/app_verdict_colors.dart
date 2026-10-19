import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

/// The six colours an answered quiz option draws for its verdict.
///
/// **Why this is a `ThemeExtension` and not six more `isDark ? … : …` lines.**
/// `ColorScheme` has `error` / `errorContainer` / `onErrorContainer` and no
/// success counterpart, so the *wrong* answer is expressible from the scheme and
/// the *right* answer is not. That gap is where the defect lived: the right
/// answer's fill was written as `scheme.primaryContainer` — purple — with a
/// green border painted on top of it, and the user reported exactly that
/// («الاختيار الصحيح يكون فقط اطاره بالاخضر و الحقل بنفسجي»). A screen with no
/// place to ask "what green?" invents one, and what it invents is a raw literal
/// that a `const` icon then cannot vary by brightness.
///
/// So the role is added to the theme, where `light()` and `dark()` each fill it
/// in, and the screen reads it. There is one place to be wrong and it is under
/// `test/design/app_theme_test.dart`.
///
/// **The green is Material's, not mine.** A green *container* is exactly what
/// `errorContainer` is for the error hue: the M3 tonal palette of a seed at the
/// container tone. So [forScheme] asks Material for the same thing from the
/// brand's success seed rather than writing a hex — measured on Flutter
/// 3.44.6, `ColorScheme.fromSeed(seedColor: successLight, Brightness.light)`
/// resolves `primaryContainer` to `#B7F1BA` (HSL hue 123°) and
/// `Brightness.dark` off `successDark` to `#17512B` (hue 141°). Both are green,
/// which is the property the theme needed and the reason this is a derivation
/// rather than a constant.
///
/// **What M3 does not have, and this does.** `secondaryContainer` and
/// `tertiaryContainer` *are* green nowhere: on this seed they measure
/// `#E8DEF8` / `#494458` (lavender, hue 263°/255°) and `#FFD9E3` / `#633B49`
/// (pink, hue 344°/339°). Neither is green in either brightness, so neither can
/// be the answer, and picking one on the strength of its name would have
/// reproduced the original defect in a new place.
@immutable
class AppVerdictColors extends ThemeExtension<AppVerdictColors> {
  const AppVerdictColors({
    required this.correctFill,
    required this.correctInk,
    required this.correctBorder,
    required this.wrongFill,
    required this.wrongInk,
    required this.wrongBorder,
  });

  /// The palette for [scheme]'s brightness.
  ///
  /// Takes the scheme rather than a `Brightness` so the wrong answer's fill and
  /// ink stay literally the scheme's own `errorContainer` / `onErrorContainer` —
  /// the value the user called correct («ممتاز و هو المطلوب»), carried through
  /// rather than restated.
  factory AppVerdictColors.forScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final success = ColorScheme.fromSeed(
      seedColor: isDark ? AppColors.successDark : AppColors.successLight,
      brightness: scheme.brightness,
    );
    return AppVerdictColors(
      correctFill: success.primaryContainer,
      correctInk: success.onPrimaryContainer,
      correctBorder: isDark ? AppColors.successDark : AppColors.successLight,
      wrongFill: scheme.errorContainer,
      wrongInk: scheme.onErrorContainer,
      wrongBorder: isDark ? AppColors.errorDark : AppColors.errorLight,
    );
  }

  /// The palette installed by `AppTheme.light()` / `AppTheme.dark()`.
  ///
  /// **Non-null assertion, and that is a deliberate claim.** Every theme this
  /// app builds goes through `AppTheme.fromColorScheme`, which installs the
  /// extension unconditionally. A caller that mounts a bare `ThemeData()` gets
  /// a loud `null check operator used on a null value` naming the file and line
  /// rather than a quiz screen silently rendering no feedback at all — and the
  /// quiz screen is never mounted outside `AppTheme` in this app or its tests.
  static AppVerdictColors of(BuildContext context) =>
      Theme.of(context).extension<AppVerdictColors>()!;

  /// The correct option's fill. Green in both brightnesses — see the class doc.
  final Color correctFill;

  /// The ink drawn **on** [correctFill]: the option's label, and its tick.
  final Color correctInk;

  /// The correct option's 2px border: the brand's success token, per brightness.
  final Color correctBorder;

  /// The wrong option's fill. `colorScheme.errorContainer`, unchanged.
  final Color wrongFill;

  /// The ink drawn **on** [wrongFill].
  final Color wrongInk;

  /// The wrong option's 2px border: the brand's error token, per brightness.
  final Color wrongBorder;

  @override
  AppVerdictColors copyWith({
    Color? correctFill,
    Color? correctInk,
    Color? correctBorder,
    Color? wrongFill,
    Color? wrongInk,
    Color? wrongBorder,
  }) =>
      AppVerdictColors(
        correctFill: correctFill ?? this.correctFill,
        correctInk: correctInk ?? this.correctInk,
        correctBorder: correctBorder ?? this.correctBorder,
        wrongFill: wrongFill ?? this.wrongFill,
        wrongInk: wrongInk ?? this.wrongInk,
        wrongBorder: wrongBorder ?? this.wrongBorder,
      );

  @override
  AppVerdictColors lerp(covariant AppVerdictColors? other, double t) {
    if (other == null) return this;
    return AppVerdictColors(
      correctFill: Color.lerp(correctFill, other.correctFill, t)!,
      correctInk: Color.lerp(correctInk, other.correctInk, t)!,
      correctBorder: Color.lerp(correctBorder, other.correctBorder, t)!,
      wrongFill: Color.lerp(wrongFill, other.wrongFill, t)!,
      wrongInk: Color.lerp(wrongInk, other.wrongInk, t)!,
      wrongBorder: Color.lerp(wrongBorder, other.wrongBorder, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVerdictColors &&
          other.correctFill == correctFill &&
          other.correctInk == correctInk &&
          other.correctBorder == correctBorder &&
          other.wrongFill == wrongFill &&
          other.wrongInk == wrongInk &&
          other.wrongBorder == wrongBorder;

  @override
  int get hashCode => Object.hash(
        correctFill,
        correctInk,
        correctBorder,
        wrongFill,
        wrongInk,
        wrongBorder,
      );
}