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
  ///
  /// **This is also the artwork's pronunciation icon.** Measured off
  /// `Memorize app theme and style.png`: the speaker beside the phonetic is
  /// gold, and the brand's own palette in the same file names the accent
  /// `#F59E0B`. The glyph renders lighter than the token because it is small
  /// and antialiased over a dark photograph — the artwork's most saturated
  /// pixel in it is `#FCCF3D` — but the colour it is drawn with is this one.
  static const Color accent = Color(0xFFF59E0B);

  /// The translucent dark fill the artwork's "معرفة المعنى" button wears.
  ///
  /// **45% of the app's darkest neutral**, `#0F172A`. The artwork draws that
  /// button as a *translucent* pill with a thin light outline rather than an
  /// opaque one, and the fill has to be dark for the white label to clear
  /// 4.5:1 over the user's brightest photographs — measured: behind the button
  /// the ink ramp already carries 0.60, and the label over a pure-white
  /// photograph measures **4.74:1** with no fill of its own and **8.90:1**
  /// with this one.
  ///
  /// **A note on the artwork's own button, because it is not a dark fill.**
  /// Measured off `Memorize app theme and style.png`: the pill's interior
  /// renders *lighter* than the photograph around it — in the light card the
  /// photo outside the pill is at luminance 0.010..0.057 and the pill's
  /// interior at 0.066..0.079, and in the dark card the photo outside is at
  /// 0.010 and the interior at 0.022. The mock's button is a frosted pill. The
  /// user's ruling is a **translucent dark** fill, and that is what ships; the
  /// measurement is here so the difference is on the record rather than
  /// discovered later.
  static const Color photoButtonFill = Color(0x730F172A);

  /// The thin light outline the artwork's "معرفة المعنى" button wears.
  ///
  /// **70% white.** The outline in the artwork is a single light pixel on the
  /// mock's 175 px card, which is 1.87 logical px on the 328 px card this app
  /// draws; it is drawn here at [photoButtonOutlineWidth]. Measured off the
  /// light card, the outline's brightest pixel is `#91AAB9` over a `#154F5A`
  /// photograph, which is 53% of white.
  static const Color photoButtonOutline = Color(0xB3FFFFFF);

  /// How thick the artwork's button outline is: **1.5 logical px**.
  ///
  /// The mock's card is 175 px wide and this app's card is 328 logical px
  /// wide, so the mock is drawn at 0.5336 scale and its single-pixel
  /// outline is 1.87 logical px here. Drawn a shade under that, because a
  /// hairline at 1.87 px disappears into an antialiased stadium edge.
  static const double photoButtonOutlineWidth = 1.5;

  static const Color successLight = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF4ADE80);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);

  /// The ink the word-of-the-day card draws its text in — **white in both
  /// modes**.
  ///
  /// **The artwork is the reason, and the measurement is the reason too.**
  /// `Memorize app theme and style.png` draws "serenity" in white on the light
  /// card and "ambition" in white on the dark one: the card's text sits on a
  /// photograph, and the photograph does not change with the phone's theme.
  ///
  /// The app's **dark body ink** `#F9FAFB` was what the card used in dark
  /// mode, and it is 3.3% the weaker of the two over the same background:
  /// measured, the word over `dark-5-turquoise-lake-under-stars.jpg` came to
  /// **4.497:1** — 0.003 below AA — while the same word in white measures
  /// **4.70:1**. `#F9FAFB` is a token for text on the app's dark *surfaces*;
  /// this is text on a photograph, and it gets its own token.
  static const Color onPhoto = Color(0xFFFFFFFF);
}

class AppShadows {
  const AppShadows._();

  /// The brand spec: 0 4px 12px rgba(0, 0, 0, 0.05).
  static const List<BoxShadow> light = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// Dark mode has no visible shadow; separation comes from a 1px border there.
  static const List<BoxShadow> none = <BoxShadow>[];

  /// The shadow the artwork draws behind every run of text that sits **on** a
  /// photograph.
  ///
  /// **This is the artwork's own mechanism for legibility**, and it is what the
  /// `#0F172A` scrim was standing in for. Measured off
  /// `Memorize app theme and style.png`: the white glyphs of "Word of the Day"
  /// and "serenity" are each surrounded by a dark halo that darkens the
  /// photograph **on the left of a stroke, above it and below it** — the same
  /// on all three sides, so the shadow is **centred, not dropped**.
  ///
  /// The measurement, on the light card at `x 50`, through the "W" of the
  /// label: the sky beside the glyph is at luminance 0.171, the pixel
  /// immediately **left** of the stroke is 0.101, the pixel immediately
  /// **below** it is 0.106, and the pixel between two strokes is 0.038. A
  /// single stroke's halo therefore darkens the photograph by **about 40%**,
  /// and two overlapping halos by about 78%.
  ///
  /// **70% of the app's darkest neutral at a 3 px blur.** The artwork's halo
  /// reads about one mock pixel wide at the mock's 0.5336 scale, which is 1.87
  /// logical px here.
  ///
  /// **The ink is `#0F172A` and not `#000000`**, and the reason is the same one
  /// `WallpaperGradient.colour` gives: `#000000` is the exact colour
  /// `tool/golden_census.ps1` fails a golden for, and a 70%-black shadow over a
  /// photograph that happens to contain a pure-black pixel would composite to
  /// pure black and put a forbidden colour into the reference images by the back
  /// door. The two are visually indistinguishable over a photograph — 70% of
  /// `#0F172A` is 70% of black to within two units of 255 — and the neutral
  /// cannot produce a forbidden pixel.
  ///
  /// **What a shadow cannot do, said plainly: it does not raise the WCAG
  /// ratio of the glyph's interior.** It softens the edge. The label on this
  /// card is white on a bright sky in the artwork too — the sky behind it runs
  /// from 4.36:1 at its left end to 1.49:1 at the card's sunlit cloud — and
  /// the artwork accepts a sub-AA ratio for that one small run of text — so
  /// this implementation does the same, and the number is in
  /// `test/ui/wallpaper_legibility_test.dart`.
  static const List<Shadow> onPhoto = <Shadow>[
    Shadow(
      color: Color(0xB30F172A),
      blurRadius: 3,
      offset: Offset.zero,
    ),
  ];
}

class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);

  /// How long one of the user's photographs holds on Home's word-of-the-day
  /// card before the next one cross-fades in — **ten seconds**, the user's own
  /// figure: «تبديل كل 10 ثوانٍ بانسيابية و سلاسة في الصفحة الرئيسية».
  ///
  /// Named here rather than written at the call site for the reason every other
  /// token in this file is: a rotation interval is a design decision, and a
  /// literal in `home_screen.dart` is a decision that can be changed by someone
  /// who never knew one had been made. `test/ui/nature_rotation_test.dart`
  /// reads **this** constant rather than its own copy of the number.
  static const Duration wallpaper = Duration(seconds: 10);
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