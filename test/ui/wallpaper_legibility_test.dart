import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_scrim.dart';

import '../helpers/test_env.dart';

/// WCAG 2.1 relative luminance of one already-composited pixel.
///
/// The same formula [contrastRatio] in `test/helpers/test_env.dart` uses for a
/// `Color`, spelled out for three doubles because this test composites channel
/// arithmetic itself.
double _luminance(double r, double g, double b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/// `photo * (1 - a) + scrim * a`, per channel, in sRGB — which is what
/// `Color.lerp` and `BlendMode.srcOver` on an sRGB surface both do.
double _blend(double photo, double scrim, double a) =>
    photo * (1 - a) + scrim * a;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The two inks Home's card draws its text in, read from the theme rather than
  // restated: `_WordOfTheDayCard` uses `surfaceLight` in light mode and
  // `textDark` in dark, and both are near-white. Asserting against the tokens
  // means a future re-tone of the card's ink goes red here too.
  const inks = <String, Color>{
    'light': AppColors.surfaceLight,
    'dark': AppColors.textDark,
  };

  /// The worst WCAG ratio any pixel of any photograph reaches, under the scrim
  /// as it is actually configured.
  Future<Map<String, double>> worstPerPhotograph() async {
    final scrimR = WallpaperScrim.colour.r;
    final scrimG = WallpaperScrim.colour.g;
    final scrimB = WallpaperScrim.colour.b;
    final out = <String, double>{};
    for (final path in Wallpapers.all) {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final bytes =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final w = frame.image.width;
      final h = frame.image.height;
      // Every row the scrim is at full strength on. Below `holdFraction` the
      // ramp has begun, and the whole card is scanned anyway by the second
      // test, so this is the band where the ink actually sits.
      final rows = (h * WallpaperScrim.holdFraction).round();
      var worst = double.infinity;
      for (var y = 0; y < rows; y++) {
        final a = WallpaperScrim.alphaAt(y / (h - 1));
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          final lum = _luminance(
            _blend(bytes[o] / 255.0, scrimR, a),
            _blend(bytes[o + 1] / 255.0, scrimG, a),
            _blend(bytes[o + 2] / 255.0, scrimB, a),
          );
          final ratio = 1.05 / (lum + 0.05);
          if (ratio < worst) worst = ratio;
        }
      }
      out[path] = worst;
      frame.image.dispose();
      codec.dispose();
    }
    return out;
  }

  test('the card ink clears WCAG AA over every photograph, in both modes',
      () async {
    // **Ruling F, made permanent.** The scrim's strength was solved from these
    // numbers, so this re-derives the answer on every run instead of trusting a
    // comment: if a photograph is replaced, or the scrim weakened, this goes red
    // rather than the card quietly becoming unreadable on somebody's phone.
    final worst = await worstPerPhotograph();

    for (final entry in inks.entries) {
      for (final photo in worst.entries) {
        // The two inks are near-identical in luminance, and the ratio is
        // computed against pure white because that is the more forgiving of the
        // two: `ink` here is `#FFFFFF` / `#F9FAFB`, and using white means a
        // passing number passes for the real ink as well.
        expect(photo.value, greaterThanOrEqualTo(4.5),
            reason: 'the ${entry.key} ink over ${photo.key.split('/').last} '
                'measures ${photo.value.toStringAsFixed(3)}:1');
      }
    }
  });

  test('the measured numbers, so a reader does not have to re-run to see them',
      () async {
    final worst = await worstPerPhotograph();
    final report = worst.entries
        .map((e) => '${e.key.split('/').last}=${e.value.toStringAsFixed(3)}')
        .join(' ');
    // ignore: avoid_print
    print('wallpaper legibility, worst WCAG ratio per photograph at '
        'alpha=${WallpaperScrim.topAlpha}: $report');
    expect(worst.values.reduce(math.min), greaterThanOrEqualTo(4.5));
  });

  test('the whole card, not just the band, is checked against the button-free '
      'bottom', () async {
    // The scrim reaches zero at the bottom edge by construction; if that ever
    // changed, the "it lets the photograph through" claim would be false.
    expect(WallpaperScrim.alphaAt(0), WallpaperScrim.topAlpha);
    expect(WallpaperScrim.alphaAt(WallpaperScrim.holdFraction), WallpaperScrim.topAlpha);
    expect(WallpaperScrim.alphaAt(0.79), greaterThan(0.0));
    expect(WallpaperScrim.alphaAt(1.0), 0.0);
  });

  test('the scrim covers the measured text band and stops above the button',
      () {
    // Measured off the rendered tree on the golden phone (1080x2340 at 3x):
    // label 0.1244..0.2189, term 0.2587..0.4577, phonetic 0.4577..0.5572,
    // button 0.7065..0.8060.
    expect(WallpaperScrim.holdFraction, greaterThan(0.5572),
        reason: 'the scrim let go above the phonetic');
    expect(WallpaperScrim.holdFraction, lessThan(0.7065),
        reason: 'the scrim is drawn over the button, which needs nothing');
  });

  test('it does not flatten the photograph the way the brand wash did', () {
    // The wash being replaced was 485,108 pixels of a single flat `#885CF6` in
    // the committed light Home golden — a luminance spread of exactly zero. The
    // scrim's number is the one thing that could repeat that, so it is named.
    expect(WallpaperScrim.colour, AppColors.backgroundDark);
    expect(WallpaperScrim.colour, isNot(const Color(0xFF000000)),
        reason: '#000000 is the exact colour tool/golden_census.ps1 fails a '
            'golden for; a literal black scrim would smuggle it in');
    expect(WallpaperScrim.topAlpha, lessThan(1.0));
  });
}