import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

/// The ink ramp that keeps Home's word-of-the-day card legible over a
/// photograph.
///
/// **What it replaced, and why the replacement is not a matter of taste.** The
/// artwork — `Memorize app theme and style.png` — draws the card with **no
/// overlay at all**: the photograph is raw, and the white text is legible
/// because the artwork's own photograph is dark where the text sits *and*
/// because every run of text carries a soft dark shadow. What shipped in
/// `898ec02` was a `#0F172A` scrim at alpha **0.60** over the **top 58%** of
/// the card — a band that flattened the sky to navy and released to nothing
/// over the bottom third, which is the opposite of the shape the user ruled
/// for.
///
/// **The user's ruling was "a gradient that dims the bottom gradually",
/// chosen over a hard scrim.** A scrim cuts a band off the picture; a gradient
/// lets it go dark toward the edge. This is that gradient: the ink is **zero
/// at the top edge** and rises to [peakAlpha] by the word, and **holds** to the
/// bottom edge. The bottom of the card is the dimmed part, and there is no
/// edge anywhere in the ramp.
///
/// ## The shape, recomputed from the artwork's own card
///
/// The artwork's light Home card was measured pixel by pixel
/// (`Memorize app theme and style.png`, 1254 x 1254; the light Home card
/// occupies **x 30..204, y 352..477** — 175 x 126 px, 1.3889:1). Its four runs
/// of text, as fractions of the card's height:
///
/// | what | the artwork's rows | as a fraction |
/// |---|---|---|
/// | the top edge's sky, raw photograph, no ink | `352..353` | `0.000 .. 0.008` |
/// | the "Word of the Day" label | `371 .. 382` | `0.151 .. 0.238` |
/// | the word "serenity" | `398 .. 415` | `0.365 .. 0.500` |
/// | the phonetic | `419 .. 429` | `0.532 .. 0.611` |
/// | the "معرفة المعنى" button's label | `451 .. 458` | `0.786 .. 0.841` |
///
/// **And the card's own row luminance**, which is the photograph on its own:
///
/// | the card's height | the mean luminance of the row |
/// |---|---|
/// | `0.03 .. 0.32` — the sky | **0.32 .. 0.41** |
/// | `0.35 .. 0.98` — the mountain and the lake | **0.02 .. 0.21** |
///
/// Four things follow from those two tables, and they are the whole of the
/// shape:
///
/// 1. **The top of the artwork's card is bare photograph** — the sky, with
///    nothing over it. So the ramp starts at **no ink at all** on the top edge.
/// 2. **The ramp must be at [peakAlpha] before the word.** The artwork's own
///    word band starts at 37.6% of the card, but *this* card's word starts
///    earlier — at **25.87%**, measured off the rendered tree on the golden
///    phone (1080x2340 at 3x: the label runs `0.12438 .. 0.21891`, the term
///    `0.25871 .. 0.45771`, the phonetic `0.45771 .. 0.55721`, the button
///    `0.70647 .. 0.80597`). The ink therefore reaches its peak at
///    **[wordBandTop] = 0.25871**, which is the *earliest* it can be and still
///    protect the whole of the word.
///
///    Putting the knee where the artwork puts it instead — 37.6% — would leave
///    the top of our word band at alpha `0.60 x 0.25871 / 0.376 = 0.4128`, and
///    a **pure-white** photograph pixel there would composite to `#9B9FA7` and
///    measure **2.65:1** against the white ink. That was measured, and it is
///    why the knee is not there.
/// 3. **The artwork's card is dark from the word down to the bottom edge** —
///    the mean row luminance never climbs back above 0.21 — so the ramp
///    **holds** to the bottom. There is no second knee.
/// 4. **The artwork has no hard edge anywhere**, so the ramp is one straight
///    line from the top edge to the word and then flat.
///
/// ## Why the peak is 0.60 and not less
///
/// The binding pixels in the user's own photographs are **pure white** — stars,
/// snow, foam, cloud — and no ink weaker than 0.60 lifts a pure-white pixel
/// to 4.5:1. Measured over all thirteen photographs and all four text bands,
/// only **2 of the 52** band/photo pairs pass with no ink at all, and the
/// alpha every one of the others needs is **0.59**. The peak is therefore
/// **0.60**, the smallest value on a 0.01 grid that clears it with a margin.
///
/// ## The label is the exception, and the artwork is the reason
///
/// In the artwork "Word of the Day" is white on sky that runs from a teal
/// `#5D7F80` at the label's left end (**4.36:1**) to a pale `#AEB5A5` at its
/// right (**2.11:1**), with the card's sunlit cloud at **1.49:1** beside it —
/// so the artwork's own label is **below AA over part of its own extent** and
/// is legible there only because of its text shadow. **A text shadow does not
/// raise the WCAG ratio of the glyph's interior**; it softens the edge.
///
/// This ramp carries the label at alpha `0.288 .. 0.508` — it sits above the
/// knee — so the label measures **1.91:1** at its worst against a pure-white
/// photograph. That is below AA, and it is the artwork's own bargain rather
/// than a new one: the implementation is held to *no worse than the artwork*,
/// and it is better. The number is in
/// `test/ui/wallpaper_legibility_test.dart`.
///
/// ## What it does not do
///
/// It does not flatten the photograph. The top quarter of the card carries no
/// ink at all, the ramp is a gradient rather than a band, and the picture
/// behind the text keeps its own contrast — the residual signal is measured in
/// `test/ui/wallpaper_legibility_test.dart` and in the task report.
class WallpaperGradient {
  const WallpaperGradient._();

  /// The app's own darkest neutral, `#0F172A`, not black.
  ///
  /// A named token rather than an invented literal, for the reason every other
  /// colour in this app is a token — and because `#000000` is the exact colour
  /// `tool/golden_census.ps1` fails a golden for, so a literal black ink would
  /// put a forbidden colour into the reference images by the back door.
  static const Color colour = AppColors.backgroundDark;

  /// The ink's strongest alpha. **0.60**, and it is solved rather than chosen.
  ///
  /// See the class doc: a pure-white photograph pixel needs 0.59 to clear
  /// 4.5:1, and every one of the thirteen photographs the app ships contains
  /// one somewhere in the text band.
  static const double peakAlpha = 0.60;

  /// Where the ramp reaches [peakAlpha] — **the top of the word's band**.
  ///
  /// **0.25871 is measured, not chosen**: the word's band runs
  /// `0.25871 .. 0.45771` of the card's height on the golden phone. The knee
  /// cannot be later than this, because the ink has to be at its peak across
  /// the *whole* of the band, and it cannot be earlier without adding ink the
  /// artwork does not have.
  static const double wordBandTop = 0.25871;

  /// The bottom of the card. The ramp holds to it.
  static const double bottomStop = 1.0;

  /// The ink's alpha at vertical fraction `t` of the card, `0` at the top.
  ///
  /// **Zero on the top edge**, because the artwork's own card has bare
  /// photograph there — its sky — and **0.60 from [wordBandTop] down**,
  /// because the artwork's card is dark from the word to the bottom edge.
  /// Between them it is one straight line.
  ///
  /// This is the same function `LinearGradient` evaluates, written out so a
  /// test can measure the ramp without rasterising it, and so the two cannot
  /// drift apart: `gradient`'s stops are built from [wordBandTop] and
  /// [peakAlpha], the two numbers this function uses.
  static double alphaAt(double t) {
    if (t <= 0) return 0;
    if (t >= wordBandTop) return peakAlpha;
    return peakAlpha * t / wordBandTop;
  }

  /// The ramp's three stops, as fractions of the card's height.
  ///
  /// Built rather than written as literals, for the reason every other number
  /// in this app is a token: a literal `0.25871` here and a literal `0.25871`
  /// in [alphaAt] are two copies of one number, and §8 of
  /// `docs/engineering-standards.md` is exactly what happens when they drift.
  static List<double> get stops =>
      <double>[0.0, wordBandTop, bottomStop];

  /// The ramp's three colours, built from [colour] and [peakAlpha].
  static List<Color> get colors => <Color>[
        colour.withValues(alpha: 0),
        colour.withValues(alpha: peakAlpha),
        colour.withValues(alpha: peakAlpha),
      ];

  /// The gradient, built rather than declared.
  static LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: stops,
      );
}
