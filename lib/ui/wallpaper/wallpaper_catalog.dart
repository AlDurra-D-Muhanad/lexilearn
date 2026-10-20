import 'package:flutter/material.dart';

/// The user's own photographs, as bundled local assets, and the memory budget
/// they are decoded under.
///
/// **These are the user's files.** They were selected, cropped and filed by
/// hand; nothing here re-grades, re-orders or re-classifies them. The dark and
/// light split is **exactly as filed**, including the fact that five of the
/// light images measure mid-tone — see
/// `docs/engineering-standards.md` §1 for why that is recorded rather than
/// silently corrected.
///
/// **No network, no permission, nothing added to the offline guarantee.** These
/// are bytes inside the APK; §12's claim is about the merged release manifest
/// and this file cannot contribute a `<uses-permission>` to it.
class Wallpapers {
  const Wallpapers._();

  static const String _directory = 'assets/wallpapers';

  /// The six filed for the **dark** screen, in the order they were filed.
  ///
  /// Names are the subject, because `01-dark.jpg` tells the next reader nothing.
  /// The numeric prefix is kept so the order is deterministic and so the
  /// light/dark split is legible from a filename alone.
  static const List<String> dark = <String>[
    // stars over a silhouette of bare winter trees, the Milky Way behind them
    '$_directory/dark-1-stars-over-bare-trees.jpg',
    // layered blue mountain ridges under a moonlit sky
    '$_directory/dark-2-moonlit-mountain-ridges.jpg',
    // neon magenta light ribbons curving across a ridgeline under stars
    '$_directory/dark-3-neon-ribbons-across-the-peaks.jpg',
    // violet peaks, an orange crescent moon, a lone figure on the ridge
    '$_directory/dark-4-violet-peaks-under-a-crescent.jpg',
    // a turquoise glacial lake between snow peaks under a starry sky
    '$_directory/dark-5-turquoise-lake-under-stars.jpg',
    // a full moon over a still mountain lake, and its reflection in the water
    '$_directory/dark-6-full-moon-over-a-still-lake.jpg',
  ];

  /// The **seven** filed for the **light** screen, in the order they were filed.
  ///
  /// **There were eight, and one of them came out.** `light-2` and
  /// `light-6-hiker-beneath-giant-mushrooms-copy.jpg` are the **same
  /// photograph** — the user filed it twice, and both copies shipped.
  /// Measured, not guessed: sampling 64,800 points across the two files found
  /// 2,323 differing by more than 12/765 and a maximum per-pixel channel
  /// difference of 92, i.e. two encodes of one picture rather than two
  /// pictures. The copy was withdrawn; the original stayed.
  ///
  /// **The numbering keeps its gap on purpose.** `light-6` is not `light-7`
  /// now, because a renumbering would erase the record that a file was
  /// withdrawn; the sequence says what was filed, and the comment above says
  /// what changed.
  static const List<String> light = <String>[
    // a teal wave cresting under a golden sky
    '$_directory/light-1-wave-under-a-golden-sky.jpg',
    // a lone hiker in teal fog beneath giant glowing mushrooms
    '$_directory/light-2-hiker-beneath-giant-mushrooms.jpg',
    // a peach dusk sky over a dark choppy sea, with one small boat
    '$_directory/light-3-dusk-sea-and-a-distant-boat.jpg',
    // turquoise surf and white foam, seen from above
    '$_directory/light-4-turquoise-foam-from-above.jpg',
    // wolves standing in golden mist, a planet and stars above
    '$_directory/light-5-wolves-in-golden-mist.jpg',
    // a painted blue-hour valley: a gnarled tree, snow-dusted hills, a water tower
    '$_directory/light-7-painted-blue-hour-valley.jpg',
    // pale snow mountains above a sea of cream-coloured cloud
    '$_directory/light-8-snow-peaks-above-clouds.jpg',
  ];

  /// The set a given brightness draws.
  ///
  /// **The user's classification, read from the theme and nowhere else.** A test
  /// asserts each set is non-empty, disjoint from the other, and named by its
  /// own brightness, so a wallpaper cannot be added to the wrong list by a
  /// rename that happens to start with the other word.
  static List<String> forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Every wallpaper, for the tests that must see all of them.
  static List<String> get all => <String>[...dark, ...light];
}

// --------------------------------------------------------------------------------
// The memory budget. This is the arithmetic, not an intention.
// --------------------------------------------------------------------------------

/// Every staged file measures **1080 x 540**, verified from the files themselves
/// rather than taken from a note.
///
/// 1080 x 540 x 4 bytes = **2,332,800 bytes** per decoded bitmap (2.2246 MiB).
/// **All thirteen resident would be 30,326,400 bytes — 30.33 MB, 28.92 MiB** —
/// on a phone, held for as long as the image cache holds them. That is the
/// number ruling C exists to prevent, and it is why [residentWallpapers] is 3
/// rather than 13.
const int wallpaperPixelWidth = 1080;
const int wallpaperPixelHeight = 540;

/// `width * height * 4` — RGBA8888, which is what `instantiateImageCodec` hands
/// back and what `ImageCache` counts.
const int decodedWallpaperBytes =
    wallpaperPixelWidth * wallpaperPixelHeight * 4; // 2,332,800

/// How many decoded wallpapers the app is willing to hold at once.
///
/// **Three, and each of the three is load-bearing:**
///
/// 1. the one on screen;
/// 2. the one cross-fading in, which `AnimatedSwitcher` keeps alive for the
///    length of the fade — a cross-fade briefly needs two resident, which is
///    fine;
/// 3. the one `precacheImage` is warming while 1 and 2 are both still up.
///
/// A fourth would be a spare nobody holds at any instant, and a thirteenth is
/// the number this whole section is about.
const int residentWallpapers = 3;

/// The ceiling this app puts on Flutter's image cache: **6,998,400 bytes**
/// (6.67 MiB) — exactly three decoded wallpapers, and a **14.3x** reduction on
/// the 100 MB default.
///
/// **Deliberately global, and why that is safe here:** these photographs are the
/// only bitmaps this app ever decodes. Nothing else loads an image, so lowering
/// the shared ceiling lowers it for them and nothing else. If a second image is
/// ever added this number has to be revisited rather than assumed still fine.
const int wallpaperImageCacheBytes = decodedWallpaperBytes * residentWallpapers;

/// 100 MB / 6.67 MiB, printed rather than asserted: the reduction is the point,
/// and a future edit that halves [residentWallpapers] should be visible here.
const double imageCacheReductionFactor =
    100 * 1024 * 1024 / wallpaperImageCacheBytes; // 14.98x on the 100 MiB default

/// Puts the ceiling above into effect. **Idempotent** — it assigns, it does not
/// accumulate — so calling it from a `State.initState` that a test may mount
/// twenty times is harmless.
///
/// Called from `LexiLearnApp.initState`, which is the one place every run of
/// this app passes through, including `pumpShell`'s mount and the golden
/// captures.
void configureWallpaperImageCache() {
  PaintingBinding.instance.imageCache.maximumSizeBytes = wallpaperImageCacheBytes;
}