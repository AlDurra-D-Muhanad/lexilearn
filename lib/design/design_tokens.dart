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

/// The brand palette: **navy and gold**.
///
/// **The authority is `docs/new-identity.md`, and the authority behind it is
/// `C:\Users\user\Desktop\lexilearn notes\new theme.png`, sampled pixel by
/// pixel.** Every hex below was read off that reference rather than chosen, and
/// the two places where the reference and the prose disagree are recorded where
/// the token is declared.
///
/// ## The one rule that shapes all of it
///
/// **The gold is a FILL, and the ink on it is dark.** The reference's
/// "معرفة المعنى" button is a solid gold pill with near-black lettering, so
/// the gold is never a text colour on a light surface — on `#F8F7F5` it
/// measures **1.95 : 1**, a third of AA. Where the brand accent has to be
/// *ink* rather than a fill, [accentInk] carries the rule: the gold in dark
/// mode, the body ink in light mode.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------------
  // The gold — the brand primary, and one value in both modes.
  // ---------------------------------------------------------------------------

  /// **The brand primary: `#F3AC43`.**
  ///
  /// Sampled off the reference's "معرفة المعنى" button: the median over the
  /// whole button is `#F3AD42` and the brightest pixel is `#FFD35F`; the
  /// button's flat interior measures `#F2AD46` / `#F3AD47`.
  ///
  /// **One value in both modes.** The user's brief is "the light palette is
  /// the same system inverted": the background and the surface invert, the
  /// **primary does not**. The light mode's gold is the same gold.
  ///
  /// **Measured:** relative luminance **0.4897**, so it is **9.90 : 1** on the
  /// navy background `#020E24` and **8.04 : 1** on the navy surface `#0E2344`.
  /// On the light background `#F8F7F5` it is **1.95 : 1** — which is exactly
  /// why [onGold] exists and why the gold is never a text colour in light
  /// mode.
  static const Color gold = Color(0xFFF3AC43);

  /// **The ink drawn on [gold]: `#020E24`, the app's own darkest navy.**
  ///
  /// The reference's button lettering is black — the darkest pixels in the
  /// button's text measure `#000012` … `#00001A`, i.e. black with the JPEG's
  /// own ringing around it. **Pure black is not available here**, and the
  /// reason is mechanical rather than aesthetic: `tool/golden_census.ps1`
  /// fails any reference image that contains a `#000000` pixel, because that is
  /// the exact colour a phantom Material keyline leaves behind. The app's
  /// darkest navy is two channels away from black on the red channel and
  /// **indistinguishable from it on a gold pill**, and it measures
  /// **9.90 : 1** against the gold.
  static const Color onGold = Color(0xFF020E24);

  /// **The active destination's field: the brand gold, translucent — `#F3AC43`
  /// at 28 %.**
  ///
  /// **The alpha is fitted, not assumed.** The reference's active tab is a
  /// translucent gold field over the bar's navy, and the fit is a composite:
  /// `gold * a + bar * (1 - a)` in sRGB, which is what the engine does.
  ///
  /// | the reference's field | the alpha the red channel asks for | the alpha the green channel asks for |
  /// |---|---|---|
  /// | `#493F30` | 0.283 | 0.283 |
  /// | `#443B2F` | 0.262 | 0.257 |
  /// | `#3A352D` | 0.219 | 0.217 |
  ///
  /// **The red and the green agree at every sample** — that is the signature of
  /// a single gold at a single alpha — and the composite of the brand gold at
  /// **0.28** over the bar's `#06142D` is `#483F33`, within one unit of the
  /// reference on both channels.
  ///
  /// **The blue channel, and what was done about it.** The reference's field
  /// reads **3 units lower in blue** than the straight composite predicts
  /// (51 against 48). Two things were checked before that was accepted: the
  /// reference's own golds carry a blue channel that ranges over **55 … 69**
  /// across the whole image (`#FFC63F`, `#FBAD37`, `#F7B145`, `#AA8040`,
  /// `#C58E43`), and the field's own blue reads **43 … 51** within one badge —
  /// so the deficit is inside the reference's own measurement noise, and it is
  /// in the same direction as that noise. **No second gold was invented for
  /// it**: the identity fixes the accent at `#F3AC43`, and a 6 % deviation on
  /// one channel of a translucent field is not visible. The residual is
  /// recorded here rather than papered over with a colour that is not the
  /// brand's.
  static const Color goldField = Color(0x47F3AC43);

  /// **The active destination's edge: the brand gold, stronger — `#F3AC43` at
  /// 70 %.**
  ///
  /// **Fitted the same way.** The reference's badge edge reads `#AA8040` where
  /// it crosses the bar's navy, and the composite of the brand gold at
  /// `a` over `#06142D` asks for **0.692** on the red channel and **0.711** on
  /// the green one — the same pair the fill's fit produced, within one
  /// hundredth. So the edge is the gold at **0.70**, which is what makes it
  /// read as an *edge* against the field rather than as more of it.
  ///
  /// **The blue channel again**: the edge's `#AA8040` carries a blue of 64
  /// against the 60 the composite predicts — the same 4-unit deficit, in the
  /// same direction, and inside the same noise.
  static const Color goldEdge = Color(0xB3F3AC43);

  /// **The ink for a run of text — or an icon — that carries the accent.**
  ///
  /// **The rule that keeps the gold a fill, in one place.** In dark mode the
  /// gold is legible as ink on the navy (**9.90 : 1** on the background,
  /// **8.04 : 1** on the surface) and the reference draws exactly that — the
  /// active tab's label is gold on navy. In light mode the same gold is
  /// **1.95 : 1** on `#F8F7F5` and **1.95 : 1** on `#FFFFFF`, so the accent
  /// ink there is the body ink instead.
  ///
  /// Every screen reads this rather than writing `isDark ? gold : textLight`
  /// for itself, because that expression is the rule and the rule belongs in
  /// one file.
  static Color accentInk(bool isDark) => isDark ? gold : textLight;

  // ---------------------------------------------------------------------------
  // Light mode — the same system, inverted.
  // ---------------------------------------------------------------------------

  /// The page background, light: `#F8F7F5`. Unchanged by the new identity.
  static const Color backgroundLight = Color(0xFFF8F7F5);

  /// The card and field surface, light: `#FFFFFF`. Unchanged.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// The body ink, light: `#1F2937`. Unchanged.
  static const Color textLight = Color(0xFF1F2937);

  /// The muted ink, light: `#6B7280`. Unchanged.
  static const Color textSecondaryLight = Color(0xFF6B7280);

  /// The hairline on a card, light: `#E5E7EB`. Unchanged.
  static const Color borderLight = Color(0xFFE5E7EB);

  /// The outline on an input or a chip, light: `#E5E7EB`.
  ///
  /// **The same value as [borderLight], and that is the inversion.** In dark
  /// mode the structure is a *blue* line on navy; inverted, it is a pale line
  /// on white.
  static const Color outlineLight = Color(0xFFE5E7EB);

  // ---------------------------------------------------------------------------
  // Dark mode — the measured navy system.
  // ---------------------------------------------------------------------------

  /// The page background, dark: **`#020E24`**.
  ///
  /// Sampled off the reference: the page reads `#041129` / `#031027` on the
  /// left margin and `#010D24` at the very bottom.
  static const Color backgroundDark = Color(0xFF020E24);

  /// The card and field surface, dark: **`#0E2344`**.
  ///
  /// Sampled off the reference's search field, whose interior measures
  /// `#0E2343` / `#0E2444` / `#0F2445`.
  static const Color surfaceDark = Color(0xFF0E2344);

  /// **The second surface, dark: `#071937`.**
  ///
  /// Sampled off the reference's word-of-the-day card, whose interior reads
  /// `#041837` at the top and `#061B3C` at the bottom — the flat value of that
  /// ramp is `#071937`. It is also the value the reference's tiles carry at
  /// their lower edge.
  static const Color surfaceDarkAlt = Color(0xFF071937);

  /// The body ink, dark: **`#FFFFFF`**.
  ///
  /// The reference's text is white — the word "peony" measures `#F4F4F6` — and
  /// the identity document names `#FFFFFF` and, for the title, `#FDFDFD`.
  static const Color textDark = Color(0xFFFFFFFF);

  /// The muted ink, dark: `#94A3B8`. Unchanged.
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  /// **The hairline on a card, dark: `#17376A`.**
  ///
  /// Sampled off the reference: the word-of-the-day card's own outline reads
  /// `#18386C` / `#163468` at its right edge, and a quick-launch tile's reads
  /// `#1C396D` / `#18356A` at its left edge.
  ///
  /// **Where this differs from `docs/new-identity.md`, and why.** The document
  /// records the border as `#061836`, "sampled where the blue border meets the
  /// background". Measured off the same PNG, the border's own pixels are
  /// `#17376A` and `#061836` is the *anti-aliased junction* where that border
  /// meets the fill — a value **1.09 : 1** against `#020E24`, i.e. invisible.
  /// The reference draws a visible blue outline, and the PNG outranks the
  /// prose, so the token is the border's own colour. The number is recorded
  /// here rather than left to be rediscovered.
  static const Color borderDark = Color(0xFF17376A);

  /// **The outline on an input or a chip, dark: `#31599B`.**
  ///
  /// Sampled off the reference's search field, whose single-pixel outline
  /// measures `#315690` at its top edge and `#31599B` / `#345CA7` at its left,
  /// and off the pack chip, whose outline reads `#375DA7` / `#2F5492`.
  ///
  /// **A second blue, and the reference has one.** The card's hairline is
  /// `#17376A` and the *field's* outline is this brighter `#31599B`; both are
  /// structure rather than accent, and neither competes with the gold.
  static const Color outlineDark = Color(0xFF31599B);

  /// **The bottom bar, dark: `#06142C`.**
  ///
  /// Sampled off the reference's bottom bar: `#06142C` / `#06142D` throughout.
  ///
  /// **The bar's own ramp, and the two ends of it.** The reference's bar is a
  /// rounded-top surface and its fill is a **gradient**, not a flat colour: a
  /// vertical slice down the bar reads `#07152D` at the top and `#06142B` at the
  /// foot, and the two are what [AppGradients.bottomBar] is built from. The
  /// difference is small — the reference's bar is nearly flat, and the number
  /// is recorded here so that it is a measurement and not an invention.
  static const Color bottomBarDark = Color(0xFF06142C);

  /// **The top of the bottom bar's ramp, dark: `#07152D`.**
  ///
  /// Sampled off the reference's bottom bar, at the row just inside its top
  /// edge: `#07152D` / `#07152E` / `#07142D`.
  static const Color bottomBarDarkTop = Color(0xFF07152D);

  /// **The foot of the bottom bar's ramp, dark: `#06142B`.**
  ///
  /// Sampled off the reference's bottom bar, at its lowest rows: `#06142B` /
  /// `#06132B`.
  static const Color bottomBarDarkBottom = Color(0xFF06142B);

  /// **The darker line along the bottom bar's top edge, dark: `#000A1E`.**
  ///
  /// Sampled off the reference's bottom bar: the row where the bar meets the
  /// page reads `#000A1E`, darker than both the page `#010D24` and the bar's
  /// own fill `#06142C`. **It is the edge the user asked for** — «الريط
  /// السفلي ليس له حافة منحنية ذات لون اغمق بدرجة لتباين الحافة» — a rounded
  /// edge with a tone a step darker than the surface it bounds, so the edge is
  /// visible rather than implied.
  ///
  /// **Not `#000000`**, for the reason every other ink in this file is not:
  /// `tool/golden_census.ps1` fails a golden that contains a pure-black pixel.
  static const Color bottomBarEdgeDark = Color(0xFF000A1E);

  /// **The circle behind a tile's icon, dark: `#0C1E38`.**
  ///
  /// Sampled off the reference's tile badges: `#10213D` / `#0D1D37` around the
  /// glyph.
  ///
  /// **The flat value, and the badge is no longer flat.** The reference's badge
  /// is a **disc with a gradient in it**, and the two ends of that ramp are
  /// [iconBadgeDarkTop] and [iconBadgeDarkBottom]. This token is the middle of
  /// the ramp and is kept for the surfaces that want the badge's own colour
  /// rather than its ramp — the header's book mark disc.
  static const Color iconBadgeDark = Color(0xFF0C1E38);

  /// **The top of the icon badge's ramp, dark: `#172B4F`.**
  ///
  /// **Measured, not chosen.** A vertical slice through the reference's badge —
  /// the disc behind the top-left tile's icon, whose centre is at `x 144` and
  /// whose radius is 64 reference px — reads:
  ///
  /// | where | the badge |
  /// |---|---|
  /// | the disc's top row, `y 973` | **`#172B4F`** |
  /// | a third of the way down, `y 999` | `#13284B` |
  /// | two thirds down, `y 1035` | `#0D1E39` |
  /// | the disc's foot, `y 1099` | **`#091C3B`** |
  ///
  /// The tile's own fill around it measures `#0D2245`, so the badge is lighter
  /// than the tile at its top and darker at its foot.
  static const Color iconBadgeDarkTop = Color(0xFF172B4F);

  /// **The foot of the icon badge's ramp, dark: `#091C3B`.**
  ///
  /// Measured with [iconBadgeDarkTop] — the last row inside the reference's
  /// badge disc.
  static const Color iconBadgeDarkBottom = Color(0xFF091C3B);

  // ---------------------------------------------------------------------------
  // The verdicts — unchanged, and deliberately so.
  // ---------------------------------------------------------------------------

  static const Color successLight = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF4ADE80);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);

  // ---------------------------------------------------------------------------
  // The ink on a photograph.
  // ---------------------------------------------------------------------------

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
  ///
  /// **It stays, and the new identity does not touch it.** The card keeps its
  /// shape — the photograph full-bleed, the ramp, the shadow — so the text is
  /// still on the photograph and still needs this ink.
  static const Color onPhoto = Color(0xFFFFFFFF);
}

/// The brand's gradients.
///
/// **Every ramp in the app is here, and every one of them is a ramp.** The
/// identity is navy and gold, and the reference draws three surfaces with a
/// gradient in them: the disc behind a tile's icon, the bottom bar, and the
/// short gold rule beside "Word of the Day". The user named the first two
/// explicitly — «لون هذه المربعات ليس متدرجا» and «لونه ليس متدرجا» — and the
/// third is the line the reference draws beside the label.
///
/// **A gradient is built from tokens, never from literals**, for the reason
/// every other colour in this app is a token: `grep Color(0x` over `lib/ui/`
/// must return nothing, and a ramp written at the call site would put a colour
/// back into a screen.
class AppGradients {
  const AppGradients._();

  /// **The disc behind a quick-launch tile's icon.**
  ///
  /// The reference's badge is a **disc slightly lighter than the tile, with a
  /// ramp in it** — `#172B4F` at its top down to `#091C3B` at its foot, both
  /// measured off the reference (see [AppColors.iconBadgeDarkTop]).
  ///
  /// **In light mode the same system inverted**: the tile is white, so the
  /// disc's top is the surface itself and its foot is a step down to the page
  /// background — the same "lit from above" direction the dark ramp has.
  static LinearGradient iconBadge(bool isDark) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const <Color>[
                AppColors.iconBadgeDarkTop,
                AppColors.iconBadgeDarkBottom,
              ]
            : const <Color>[
                AppColors.surfaceLight,
                AppColors.backgroundLight,
              ],
      );

  /// **The bottom bar's own fill.**
  ///
  /// The reference's bar is a **gradient, not a flat colour**: `#07152D` at its
  /// top down to `#06142B` at its foot, both measured (see
  /// [AppColors.bottomBarDarkTop]). The difference is small, and it is a
  /// gradient because the reference's is one — the user named the flat fill as
  /// the same defect as the flat tiles.
  ///
  /// **In light mode the bar is the surface**, and the surface is flat in the
  /// reference's light palette; the ramp is therefore the dark one alone, and
  /// light mode keeps the bar on [AppColors.surfaceLight].
  static LinearGradient bottomBar(bool isDark) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const <Color>[
                AppColors.bottomBarDarkTop,
                AppColors.bottomBarDarkBottom,
              ]
            : const <Color>[
                AppColors.surfaceLight,
                AppColors.surfaceLight,
              ],
      );

  /// **The short gold rule beside "Word of the Day".**
  ///
  /// The reference draws a line to the trailing side of the label, and **the
  /// line is a gradient, not a flat gold**: it starts at the full brand gold
  /// and fades away until it is gone. Measured off the reference, the rule's
  /// first row is `#FFC831` at its gold end and `#483E2E` where it dies out.
  ///
  /// **Directional, so it fades away from the text in either mode.** The rule
  /// sits on the trailing side of the label, which is the left in this Arabic
  /// app, so the gold end is against the text and the transparent end is away
  /// from it. `AlignmentDirectional` is resolved by the painter against the
  /// ambient text direction — the same one the label's own row is laid out in —
  /// so the gradient follows the reading direction without being told twice.
  static LinearGradient get goldRule => LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: <Color>[
          AppColors.gold,
          AppColors.gold.withValues(alpha: 0),
        ],
      );
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
  /// **The ink is the app's darkest navy and not `#000000`**, and the reason is
  /// the same one `WallpaperGradient.colour` gives: `#000000` is the exact
  /// colour `tool/golden_census.ps1` fails a golden for, and a 70%-black
  /// shadow over a photograph that happens to contain a pure-black pixel would
  /// composite to pure black and put a forbidden colour into the reference
  /// images by the back door. The two are visually indistinguishable over a
  /// photograph — 70% of `#020E24` is 70% of black to within a few units of 255
  /// — and the neutral cannot produce a forbidden pixel.
  ///
  /// **What a shadow cannot do, said plainly: it does not raise the WCAG
  /// ratio of the glyph's interior.** It softens the edge. The label on this
  /// card is white on a bright sky in the artwork too — the sky behind it runs
  /// from 4.36:1 at its left end to 1.49:1 at the card's sunlit cloud — and the
  /// artwork accepts a sub-AA ratio for that one small run of text — so
  /// this implementation does the same, and the number is in
  /// `test/ui/wallpaper_legibility_test.dart`.
  static const List<Shadow> onPhoto = <Shadow>[
    Shadow(
      color: Color(0xB3020E24),
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
  /// A word being *asked about* is the largest text on its screen, so this is
  /// the one place in the app that needs a size above the Material body scale. Named
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
