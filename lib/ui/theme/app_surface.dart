import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

/// The brand surface: the hairline border, plus — in light mode only — the
/// brand's soft shadow `0 4px 12px rgba(0,0,0,0.05)`.
///
/// This exists because `CardThemeData` has no shadow field. Its only fields are
/// `clipBehavior`, `color`, `shadowColor`, `surfaceTintColor`, `elevation`,
/// `margin` and `shape`, so the shadow cannot come from the theme at all; it has
/// to be composed where the surface is actually built. `Card` with the app's
/// `cardTheme` therefore gives the surface colour, the radius and the hairline,
/// and nothing more — reaching for `elevation` to get a shadow back trades the
/// brand's shadow for Material's, which is roughly four times the umbra alpha
/// and, under the test rasteriser, strokes out as an opaque black keyline.
///
/// Screens should build surfaces with this rather than a bare `Card`, so the
/// brand shadow is applied once, in one place, instead of being re-typed.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.fill,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Defaults to the brand card radius, `AppRadii.md`.
  final BorderRadius? borderRadius;

  /// Overrides the fill, for the surfaces the brand colours rather than leaves
  /// neutral — currently Home's word-of-the-day card, which the new identity
  /// fills with the second navy surface.
  ///
  /// This is why that card could not simply have been an `AppSurface` with a
  /// different colour passed in: there was no parameter to pass it through, so
  /// the card either became an argument in prose ("this one is special") or got a
  /// private `Container` that no longer shared the radius and shadow rules. With
  /// the parameter the rule stays mechanically checkable — *every* surface is an
  /// `AppSurface`, which `test/ui/home_screen_test.dart` asserts — and the
  /// exception is one named argument.
  ///
  /// The border takes its colour from the brightness, or from [fill] when one is
  /// given — unless [borderColor] says otherwise.
  ///
  /// A card in one flat colour inside a grey hairline reads as a panel in an
  /// outline, which is not what the brand draws. A caller that needs a specific
  /// border colour is reaching for something `AppSurface` is the wrong shape for
  /// — unless it is the reference's own blue, which is what [borderColor] is
  /// for.
  ///
  /// **A supplied [fill] also removes the hairline.** The hairline exists to
  /// separate a *neutral* surface from the background behind it; a surface the
  /// brand has coloured is separated by that colour and needs no outline. That
  /// is one rule rather than a second parameter — and the reference's navy
  /// card, which *does* carry a visible blue outline, is the one case that
  /// names [borderColor] to keep it.
  final Color? fill;

  /// **The hairline's own colour, for a surface that has a [fill] of its own.**
  ///
  /// The reference draws its word-of-the-day card as a flat navy panel with a
  /// **visible blue outline** — `#17376A`, measured at the card's right edge —
  /// so "a filled surface has no outline" is not true of that card, and a rule
  /// that cannot say so would force the screen to reach for a bare `Container`
  /// and lose the shared radius, border and shadow rules.
  ///
  /// Null means the hairline follows the brightness, or is removed by a [fill]
  /// as described above.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppRadii.md);
    final hairline = borderColor ??
        (isDark ? AppColors.borderDark : AppColors.borderLight);
    return AnimatedContainer(
      // Cross-fades when the app switches between light and dark rather than
      // snapping the fill, hairline and shadow from one brand set to the other.
      duration: AppDurations.standard,
      decoration: BoxDecoration(
        color: fill ?? (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
        borderRadius: radius,
        border: Border.all(
          // A filled surface drops the hairline unless it names one.
          color: (fill != null && borderColor == null) ? fill! : hairline,
        ),
        // Dark mode separates by the hairline alone: a shadow on a dark surface
        // is invisible, and the brand does not define one for it.
        boxShadow: isDark ? AppShadows.none : AppShadows.light,
      ),
      // `MaterialType.transparency` paints nothing — the decoration above is the
      // whole surface — but supplies the ambient text style and ink handling
      // that any widget drawn inside a surface expects.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}