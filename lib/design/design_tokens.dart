import 'package:flutter/material.dart';

/// The single source of truth for visual values. Screens import these; they do
/// not invent their own. See docs/design/style-direction.md for the reasoning.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

class AppRadii {
  const AppRadii._();

  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double pill = 999;
}

class AppColors {
  const AppColors._();

  // Light mode
  static const Color primaryLight = Color(0xFF885CF6);
  static const Color backgroundLight = Color(0xFFF8F7F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF1F2937);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color borderLight = Color(0xFFE5E7EB);

  // Dark mode
  static const Color primaryDark = Color(0xFFA78BFA);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color textDark = Color(0xFFF9FAFB);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color borderDark = Color(0xFF334155);

  // Shared across both modes
  /// The book mark and achievement accent. Icons and fills only — its contrast
  /// against a near-white background is too low for body text.
  static const Color accent = Color(0xFFF59E0B);

  static const Color successLight = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF4ADE80);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);
}

class AppShadows {
  const AppShadows._();

  /// The brand spec: 0 4px 12px rgba(0, 0, 0, 0.05).
  static const List<BoxShadow> light = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// Dark mode has no visible shadow; separation comes from a 1px border there.
  static const List<BoxShadow> none = <BoxShadow>[];
}

class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
}

/// Latin runs name the brand's Latin face explicitly.
///
/// Tajawal does carry Latin glyphs — its `cmap` maps 95 printable ASCII
/// codepoints — but they are not the brand's Latin. Leaving an English term to
/// the ambient family would render it in Tajawal's own Latin at Tajawal's
/// weights, which reads as an accident rather than a decision. Naming Inter
/// keeps every English word on the same face and the same type scale.
class AppText {
  const AppText._();

  static const TextStyle latin = TextStyle(fontFamily: 'Inter');
  static const TextStyle latinDisplay =
      TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600);
  static const TextStyle arabic = TextStyle(fontFamily: 'Tajawal');

  /// The display size on the Home screen's word-of-the-day card.
  ///
  /// A word being *asked about* is the largest text on its screen, so this is the
  /// one place in the app that needs a size above the Material body scale. Named
  /// here rather than written as a literal at the call site, so the card is not
  /// the sixth place in the app where a raw number appears.
  static const double wordOfTheDay = 28;

  /// The size of a secondary Latin run: a pack key in a pill, the fraction
  /// counter beside a progress bar, a caption under a label.
  ///
  /// Not a size the app invented — it is Material's own `bodySmall` — but named
  /// for the same reason [wordOfTheDay] is: a literal at each call site is how
  /// two screens drift apart on what is meant to be one decision.
  static const double caption = 12;
}