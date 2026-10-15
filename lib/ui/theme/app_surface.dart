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
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Defaults to the brand card radius, `AppRadii.md`.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppRadii.md);
    return AnimatedContainer(
      // Cross-fades when the app switches between light and dark rather than
      // snapping the fill, hairline and shadow from one brand set to the other.
      duration: AppDurations.standard,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: radius,
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
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