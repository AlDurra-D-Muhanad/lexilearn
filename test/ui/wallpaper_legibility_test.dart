import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_gradient.dart';

import '../helpers/test_env.dart';

/// WCAG 2.1 relative luminance of one already-composited pixel.
///
/// The same formula `contrastRatio` in `test/helpers/test_env.dart` uses for a
/// `Color`, spelled out for three doubles because this test composites channel
/// arithmetic itself.
double _luminance(double r, double g, double b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/// `photo * (1 - a) + ink * a`, per channel, in sRGB — which is what
/// `Color.lerp` and `BlendMode.srcOver` on an sRGB surface both do.
double _blend(double photo, double ink, double a) =>
    photo * (1 - a) + ink * a;

/// The four text bands on the card, as fractions of the card's height.
///
/// **Measured off the rendered tree on the golden phone** (1080x2340 at 3x),
/// not copied from a note, and **shared** with
/// `test/ui/home_screen_test.dart`, which measures the tree and asserts it
/// against these — so a layout change goes red in the place that owns the
/// number. See `wordOfTheDayBands` in `test/helpers/test_env.dart` for the
/// measurement and the reason the card's fraction of height is the
/// photograph's fraction of height.
///
/// The measurement is **the whole width of every row the glyphs occupy**, not
/// only the columns the glyphs cover. That is a superset of "behind the
/// glyphs": a longer word reaches further right, and a pixel the word does not
/// cover today is a pixel the word could cover tomorrow. The photograph is
/// also sampled across its **full** width, while the card crops 9.2% off each
/// side, so the figures include pixels that are not even on screen.
const _bands = wordOfTheDayBands;

/// The ratio the artwork's own label measures, and the floor this
/// implementation is held to.
///
/// **Measured off `Memorize app theme and style.png`, not asserted.** The
/// artwork's light Home card occupies `x 30..204, y 352..477` — 175×126 px —
/// and the "Word of the Day" label runs `x 45..118, y 371..382`. The sky
/// behind it is **not** one flat colour:
///
/// | where | the sky | the white ink against it |
/// |---|---|---|
/// | the label's left end, `x 42` | `#5D7F80` | **4.36:1** |
/// | just right of the label, `x 126` | `#AEB5A5` | **2.11:1** |
/// | the card's sunlit cloud, `x 200` | `#D5D5C0` | **1.49:1** |
///
/// **So the artwork's own label is below AA over part of its own extent**,
/// and it is legible there only because of its text shadow. This number is the
/// floor: the implementation is held to **no worse than the artwork**, and it
/// measures **1.94:1** at its worst.
const double _artworkLabelRatio = 1.49;

/// One photograph, decoded once and sampled many times.
class _Photo {
  _Photo(this.path, this.bytes, this.width, this.height);

  final String path;
  final Uint8List bytes;
  final int width;
  final int height;

  /// The red channel at [x], [y], as 0..1.
  double r(int x, int y) => bytes[(y * width + x) * 4] / 255.0;
  double g(int x, int y) => bytes[(y * width + x) * 4 + 1] / 255.0;
  double b(int x, int y) => bytes[(y * width + x) * 4 + 2] / 255.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The inks Home's card draws its text in, read from the theme's own tokens
  // rather than restated.
  //
  // **Both modes draw the same white**, and that is the artwork's own doing:
  // the card's text sits on a photograph, which does not change with the
  // phone's theme. The two entries are kept separate because the brief asks
  // for the numbers in both modes, and a future change that gave the dark
  // card its own ink again would have to be measured again.
  const inks = <String, Color>{
    'light': AppColors.onPhoto,
    'dark': AppColors.onPhoto,
  };

  /// Decodes every photograph the app ships.
  Future<List<_Photo>> loadAll() async {
    final out = <_Photo>[];
    for (final path in Wallpapers.all) {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final bytes = (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      out.add(_Photo(path, bytes, frame.image.width, frame.image.height));
      frame.image.dispose();
      codec.dispose();
    }
    return out;
  }

  /// The worst WCAG ratio of [ink] over the whole of [band], for one
  /// photograph, under the gradient as it is actually configured.
  ///
  /// **[ink] is the card's own text colour for the mode being measured** —
  /// `AppColors.onPhoto`, `#FFFFFF`, in both modes — and the ratio is computed
  /// against that rather than against a hard-coded white, so a change to the
  /// card's ink goes red here rather than being measured against the wrong
  /// thing.
  ///
  /// **[shadowAlpha] is the shadow's own opacity**, and it is applied to the
  /// background *under the glyph* as a real composite — `background * (1 - a) +
  /// shadowColour * a`, in sRGB, which is what the engine does — rather than as
  /// a plain multiply. That is the honest way to say what a shadow does. It
  /// cannot raise the ratio of the glyph's **interior**, and this test never
  /// claims it does: the interior is measured with the shadow switched off, and
  /// the shadowed figure is reported beside it as the *edge* contrast the
  /// shadow buys.
  ///
  /// **[withInk] false** measures the photograph *alone*, which is the
  /// "before" figure the ramp exists to move.
  double worstInBand(
    _Photo photo,
    List<double> band, {
    Color ink = const Color(0xFFFFFFFF),
    double shadowAlpha = 0.0,
    bool withInk = true,
  }) {
    final inkR = WallpaperGradient.colour.r;
    final inkG = WallpaperGradient.colour.g;
    final inkB = WallpaperGradient.colour.b;
    final inkL = _luminance(ink.r, ink.g, ink.b);
    // The shadow's own colour, so the composite is the engine's and not a
    // multiply. `AppShadows.onPhoto.single.color` carries its alpha in `.a`
    // and its channels in `.r`/`.g`/`.b`.
    final shadow = AppShadows.onPhoto.single.color;
    final y0 = (photo.height * band[0]).round();
    final y1 = (photo.height * band[1]).round();
    var worst = double.infinity;
    for (var y = y0; y <= y1 && y < photo.height; y++) {
      // The card shows the photograph's full height, so the card's fraction of
      // height is the photograph's fraction of height.
      final a =
          withInk ? WallpaperGradient.alphaAt(y / (photo.height - 1)) : 0.0;
      for (var x = 0; x < photo.width; x++) {
        var cr = _blend(photo.r(x, y), inkR, a);
        var cg = _blend(photo.g(x, y), inkG, a);
        var cb = _blend(photo.b(x, y), inkB, a);
        if (shadowAlpha > 0) {
          cr = cr * (1 - shadowAlpha) + shadow.r * shadowAlpha;
          cg = cg * (1 - shadowAlpha) + shadow.g * shadowAlpha;
          cb = cb * (1 - shadowAlpha) + shadow.b * shadowAlpha;
        }
        final lum = _luminance(cr, cg, cb);
        final ratio = (inkL + 0.05) / (lum + 0.05);
        if (ratio < worst) worst = ratio;
      }
    }
    return worst;
  }

  group('the ramp, which replaced the scrim', () {
    test('it starts at nothing on the top edge', () {
      // **The scrim this replaced held 0.60 across the top 58% and released
      // it below.** That is the shape the artwork does not have and the user
      // ruled out: a hard band over the picture, dimming the *top* rather than
      // the bottom.
      expect(WallpaperGradient.alphaAt(0), 0.0);
      expect(WallpaperGradient.gradient.colors.first.a, 0.0);
    });

    test('it is already at 0.60 by the word\'s band, and holds to the bottom',
        () {
      expect(WallpaperGradient.alphaAt(WallpaperGradient.wordBandTop),
          WallpaperGradient.peakAlpha);
      expect(WallpaperGradient.alphaAt(0.4577), WallpaperGradient.peakAlpha);
      expect(WallpaperGradient.alphaAt(0.7065), WallpaperGradient.peakAlpha);
      expect(WallpaperGradient.alphaAt(1.0), WallpaperGradient.peakAlpha);
      // **The scrim reached zero at the bottom edge.** This one does not.
      expect(WallpaperGradient.gradient.colors.last.a,
          WallpaperGradient.peakAlpha);
    });

    test('the peak is 0.60, and it is nowhere stronger', () {
      expect(WallpaperGradient.peakAlpha, 0.60);
      var highest = 0.0;
      for (var i = 0; i <= 1000; i++) {
        highest = math.max(highest, WallpaperGradient.alphaAt(i / 1000));
      }
      expect(highest, WallpaperGradient.peakAlpha);
    });

    test('it never falls: a ramp, not a band', () {
      var previous = -1.0;
      for (var i = 0; i <= 1000; i++) {
        final a = WallpaperGradient.alphaAt(i / 1000);
        expect(a, greaterThanOrEqualTo(previous),
            reason: 'the ramp fell at ${i / 1000}');
        previous = a;
      }
    });

    test('the ink is at its peak across the whole of the word\'s band, which '
        'is what a pure-white pixel needs', () {
      // **0.59 is the alpha a pure-white photograph pixel needs to clear
      // 4.5:1.** The word's band starts at 0.25871 and the ramp reaches its
      // peak exactly there, so no pixel of the word is ever under less than
      // 0.60 of ink.
      for (var t = _bands['word']![0]; t <= _bands['word']![1]; t += 0.0005) {
        expect(WallpaperGradient.alphaAt(t), greaterThanOrEqualTo(0.59),
            reason: 'the word at $t is under ${WallpaperGradient.alphaAt(t)}');
      }
      expect(WallpaperGradient.peakAlpha, greaterThanOrEqualTo(0.59));
    });

    test('the gradient itself carries the same shape as the function', () {
      // The two cannot drift: the stops are built from the same two numbers
      // `alphaAt` uses, and this checks the built gradient against the
      // function row by row.
      final gradient = WallpaperGradient.gradient;
      final stops = gradient.stops!;
      expect(stops.length, 3);
      expect(gradient.colors.length, 3);
      expect(stops.first, 0.0);
      expect(stops[1], WallpaperGradient.wordBandTop);
      expect(stops.last, 1.0);
      expect(gradient.colors[1].a, WallpaperGradient.peakAlpha);
      expect(gradient.colors.last.a, WallpaperGradient.peakAlpha);
    });

    test('the ink is the app\'s own darkest neutral, never black', () {
      // `#000000` is the exact colour `tool/golden_census.ps1` fails a golden
      // for; a literal black ink would smuggle it into the reference images by
      // the back door.
      expect(WallpaperGradient.colour, AppColors.backgroundDark);
      expect(WallpaperGradient.colour, isNot(const Color(0xFF000000)));
    });
  });

  group('the ink over every photograph the app ships', () {
    test('the word, the phonetic and the button clear 4.5:1 in both modes',
        () async {
      // **Ruling F, made permanent.** The ink's strength was solved from these
      // numbers, so this re-derives the answer on every run instead of trusting
      // a comment: if a photograph is replaced, or the ramp weakened, this goes
      // red rather than the card quietly becoming unreadable on somebody's
      // phone.
      //
      // **Each mode is measured against its own ink.** The card's ink is
      // `AppColors.onPhoto` in both modes, and this loop measures it twice so
      // a change that gave one mode a different ink would show up as a
      // different number rather than as silence.
      final photos = await loadAll();
      expect(photos, hasLength(13));

      for (final photo in photos) {
        for (final entry in inks.entries) {
          for (final band in <String>['word', 'phonetic', 'button']) {
            final worst = worstInBand(photo, _bands[band]!, ink: entry.value);
            expect(worst, greaterThanOrEqualTo(4.5),
                reason: 'the ${entry.key} ink over the $band of '
                '${photo.path.split('/').last} measures '
                '${worst.toStringAsFixed(3)}:1');
          }
        }
      }
    });

    test('the label is the one exception, and it is no worse than the '
        'artwork\'s own', () async {
      // **The artwork accepts a sub-AA ratio for that one small label** — its
      // own sky runs from 4.36:1 at the label's left end to 2.11:1 at its
      // right, and the card's sunlit cloud is 1.49:1 — so it is legible only
      // because of its shadow. A text shadow does not raise the WCAG ratio of
      // the glyph's interior; it softens the edge. So the label is measured
      // here against the artwork's own figure rather than against 4.5:1.
      final photos = await loadAll();
      var worstOverAll = double.infinity;
      for (final photo in photos) {
        final worst = worstInBand(photo, _bands['label']!);
        worstOverAll = math.min(worstOverAll, worst);
        expect(worst, greaterThanOrEqualTo(_artworkLabelRatio),
            reason: 'the label over ${photo.path.split('/').last} measures '
                '${worst.toStringAsFixed(3)}:1, worse than the artwork\'s own '
                '$_artworkLabelRatio:1');
      }
      // And it really is below AA over the user's brightest photographs, which
      // is what makes it the exception rather than a claim.
      expect(worstOverAll, lessThan(4.5));
    });

    test('the shadow is what lifts the label\'s edge, and it is measured',
        () async {
      // The shadow's own opacity, read from the token the card draws with.
      final shadow = AppShadows.onPhoto.single;
      final shadowAlpha = shadow.color.a;
      expect(shadowAlpha, greaterThan(0.5));
      expect(shadow.blurRadius, greaterThan(0.0));

      final photos = await loadAll();
      // Over the photograph the shadow is dark enough to rescue the label's
      // *edge*, even though it cannot touch the interior.
      final worstLabelEdge = photos
          .map((p) => worstInBand(p, _bands['label']!, shadowAlpha: shadowAlpha))
          .reduce(math.min);
      expect(worstLabelEdge, greaterThan(4.5),
          reason: 'with the artwork\'s shadow the label\'s edge clears AA');
    });

    test('the measured numbers, so a reader does not have to re-run to see them',
        () async {
      final photos = await loadAll();
      final buffer = StringBuffer();
      for (final photo in photos) {
        final name = photo.path.split('/').last;
        for (final band in _bands.keys) {
          final light = worstInBand(photo, _bands[band]!,
              ink: inks['light']!);
          final dark = worstInBand(photo, _bands[band]!,
              ink: inks['dark']!);
          final shadowed = worstInBand(photo, _bands[band]!,
              ink: inks['light']!,
              shadowAlpha: AppShadows.onPhoto.single.color.a);
          buffer.write('$name/$band  light=${light.toStringAsFixed(2)}:1  '
              'dark=${dark.toStringAsFixed(2)}:1  '
              'shadowed-edge=${shadowed.toStringAsFixed(2)}:1\n');
        }
      }
      // ignore: avoid_print
      print('wallpaper legibility, worst WCAG ratio of the card\'s own ink over '
          'each photograph and band:\n$buffer');
    });

    test('without any ink only a handful of band/photo pairs clear 4.5:1',
        () async {
      // **The measurement the ramp exists because of.** The binding pixels in
      // the user's own photographs are pure white — stars, snow, foam, cloud —
      // and no ink weaker than 0.60 lifts one of them to 4.5:1.
      final photos = await loadAll();
      var passing = 0;
      var total = 0;
      for (final photo in photos) {
        for (final band in _bands.keys) {
          total++;
          final worst = worstInBand(photo, _bands[band]!, withInk: false);
          if (worst >= 4.5) passing++;
        }
      }
      // ignore: avoid_print
      print('wallpaper legibility, band/photo pairs that clear 4.5:1 with no '
          'ink at all: $passing of $total');
      expect(passing, lessThan(total ~/ 4),
          reason: 'the photographs are bright enough that most bands need the '
              'ink; if this number has risen, the ramp may be stronger than '
              'it needs to be');
    });
  });
}
