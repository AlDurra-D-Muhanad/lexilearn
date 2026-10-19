import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

/// The scrim that keeps Home's word-of-the-day card legible over a photograph.
///
/// **Why Home needs one and the flashcard panel does not, measured rather than
/// assumed.** The panel in `flashcards_screen.dart` is a bare 2:1 photograph
/// with **no ink on it at all** — the word, its pronunciation and its meaning
/// are on the separate surface below it, which is why `_NaturePanel` has no
/// scrim and a test asserts it has none. Home's card is the opposite shape: the
/// label, the term and the phonetic sit **on** the picture. So the scrim lives
/// here, beside Home's card, and not in `NaturePhoto`.
///
/// **How strong, and how it was arrived at.** The ink is the card's own — white
/// in both modes — and the composite under a scrim of [colour] at alpha `a` is
/// `photo * (1 - a) + scrim * a` per channel, which is what `Color.lerp` and
/// `BlendMode.srcOver` on an sRGB surface both do.
///
/// The alpha was solved for, not chosen by eye. `test/ui/wallpaper_legibility_test.dart`
/// composites **every pixel of the text band of all fourteen photographs** and
/// reports the worst WCAG ratio it finds; [topAlpha] is the smallest value on a
/// 0.01 grid that clears 4.5:1 across the whole set, in both modes.
///
/// **It holds its strength across the whole text band and then lets go.** The
/// band was measured off the rendered tree on the golden phone, 1080x2340 at
/// 3x: the label runs `y 0.1244 .. 0.2189` of the card, the term
/// `0.2587 .. 0.4577`, the phonetic `0.4577 .. 0.5572`, and the button —
/// which needs nothing, being an opaque amber pill — `0.7065 .. 0.8060`.
/// [holdFraction] is 0.58, which clears 0.5572 and stops short of the button.
///
/// **What it does not do is flatten the photograph.** Two thirds of the card's
/// height carries no scrim at all, and on the flashcard panel there is none
/// anywhere. The numbers for the residual signal are in the legibility test's
/// output, and in the task report.
class WallpaperScrim {
  const WallpaperScrim._();

  /// The app's own darkest neutral, `#0F172A`, not black.
  ///
  /// A named token rather than an invented literal, for the reason every other
  /// colour in this app is a token — and because `#000000` is the exact colour
  /// `tool/golden_census.ps1` fails a golden for, so a literal black scrim
  /// would put a forbidden colour into the reference images by the back door.
  static const Color colour = AppColors.backgroundDark;

  /// The scrim's strength where the text is. **Solved, see the class doc.**
  static const double topAlpha = 0.60;

  /// How far down the card the scrim holds at [topAlpha].
  ///
  /// **0.58 is measured, not chosen** — it is the phonetic's measured bottom
  /// (0.5572) plus the 8 px of `AppSpacing.s` that sits below it, expressed as a
  /// fraction of the card's measured 201 px height.
  static const double holdFraction = 0.58;

  /// The scrim's alpha at vertical fraction `t` of the card, `0` at the top.
  ///
  /// Constant at [topAlpha] down to [holdFraction], then a straight ramp to
  /// nothing at the bottom edge. A ramp that started at the top instead would
  /// have to be stronger everywhere to cover the text at `t = 0.56`, and would
  /// put that strength on the one part of the card — the bottom quarter, which
  /// carries only the photograph — that needed none.
  static double alphaAt(double t) {
    if (t <= holdFraction) return topAlpha;
    if (t >= 1) return 0;
    return topAlpha * (1 - (t - holdFraction) / (1 - holdFraction));
  }

  /// The scrim's three stops, built from [topAlpha] rather than written as byte
  /// literals — a literal here is a second copy of [topAlpha] that can drift
  /// from it silently, which is §8's failure with a `0.6` on one side and
  /// `0x99` on the other.
  static List<Color> get stops => <Color>[
        colour.withValues(alpha: topAlpha),
        colour.withValues(alpha: topAlpha),
        colour.withValues(alpha: 0),
      ];

  /// The gradient, built rather than declared.
  static LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: stops,
        stops: const <double>[0, holdFraction, 1],
      );
}