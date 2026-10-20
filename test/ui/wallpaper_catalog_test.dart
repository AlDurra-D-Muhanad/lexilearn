import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("the user's photographs, as filed", () {
    test('there are thirteen of them, six dark and seven light', () {
      expect(Wallpapers.dark, hasLength(6));
      expect(Wallpapers.light, hasLength(7));
      expect(Wallpapers.all, hasLength(13));
    });

    test('the duplicated photograph is gone, and only the copy of it', () {
      // **The user's ruling**: `light-2` and
      // `light-6-hiker-beneath-giant-mushrooms-copy.jpg` are the same
      // photograph — 64,800 sampled points, 2,323 differing by more than 12 of
      // 765, a maximum per-pixel channel difference of 92 — so the copy ships
      // no more. The original stays, because it is a photograph the user filed.
      expect(
        Wallpapers.all,
        isNot(contains('assets/wallpapers/'
            'light-6-hiker-beneath-giant-mushrooms-copy.jpg')),
        reason: 'the duplicate wallpaper still ships',
      );
      expect(
        Wallpapers.all,
        contains('assets/wallpapers/light-2-hiker-beneath-giant-mushrooms.jpg'),
        reason: 'the original of the pair was withdrawn instead of the copy',
      );
      // And the file is gone from the bundle, not merely unlisted: an asset on
      // disk that nothing lists is still 300 KB in the APK.
      expect(
        File('assets/wallpapers/'
                'light-6-hiker-beneath-giant-mushrooms-copy.jpg')
            .existsSync(),
        isFalse,
        reason: 'the duplicate file is still on disk and still in the APK',
      );
    });

    test('every path is inside the declared directory and uniquely named', () {
      for (final path in Wallpapers.all) {
        expect(path, startsWith('assets/wallpapers/'), reason: path);
      }
      expect(Wallpapers.all.toSet(), hasLength(13),
          reason: 'the same file is listed twice, so one photograph is unfiled');
    });

    test('every declared asset is really bundled and really decodes', () async {
      // **The set-equality guard, on the asset side.** `pubspec.yaml` declares
      // `assets/wallpapers/`; a path in the catalog that the bundle does not
      // carry would resolve to a decode error on a device and to nothing at all
      // in the reference images. Same failure shape as a golden on disk that
      // `tool/golden_census.ps1` never reads: a file nothing checks.
      for (final path in Wallpapers.all) {
        final data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(0), reason: '$path is empty');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        expect(frame.image.width, wallpaperPixelWidth, reason: '$path width');
        expect(frame.image.height, wallpaperPixelHeight, reason: '$path height');
        frame.image.dispose();
        codec.dispose();
      }
    });

    test('every photograph is 2:1, which is what lets one crop serve both '
        'surfaces', () async {
      for (final path in Wallpapers.all) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        final ratio = frame.image.width / frame.image.height;
        expect(ratio, closeTo(2, 0.001), reason: '$path is $ratio:1, not 2:1');
        frame.image.dispose();
        codec.dispose();
      }
    });

    test('the light and dark sets are disjoint, so a mode switch swaps the '
        'whole picture', () {
      for (final path in Wallpapers.dark) {
        expect(Wallpapers.light, isNot(contains(path)));
      }
    });
  });

  group('the set a brightness draws', () {
    test('dark draws exactly the dark set, light exactly the light set', () {
      expect(Wallpapers.forBrightness(Brightness.dark), Wallpapers.dark);
      expect(Wallpapers.forBrightness(Brightness.light), Wallpapers.light);
    });

    test('each set is named by its own brightness, file name and all', () {
      // A wallpaper dropped into the wrong list is the exact mistake this catches,
      // and it is invisible until someone runs the app on a dark phone.
      for (final path in Wallpapers.dark) {
        expect(path, contains('/dark-'), reason: '$path is not filed as dark');
        expect(path, isNot(contains('/light-')), reason: '$path is filed twice');
      }
      for (final path in Wallpapers.light) {
        expect(path, contains('/light-'), reason: '$path is not filed as light');
        expect(path, isNot(contains('/dark-')), reason: '$path is filed twice');
      }
    });
  });

  group('the memory arithmetic, which is the whole point', () {
    test('one decoded photograph is 1080 x 540 x 4 bytes', () {
      expect(decodedWallpaperBytes, 1080 * 540 * 4);
      expect(decodedWallpaperBytes, 2332800);
    });

    test('all thirteen resident would be 30.33 MB, which is why there are three',
        () {
      final allThirteen = decodedWallpaperBytes * Wallpapers.all.length;
      expect(allThirteen, 13 * 2332800);
      expect(allThirteen, 30326400);
      expect(allThirteen / 1000000, closeTo(30.33, 0.01),
          reason: 'MB, decimal');
      expect(allThirteen / 1048576, closeTo(28.92, 0.01),
          reason: 'MiB, binary');
    });

    test('the ceiling is exactly three decoded photographs', () {
      expect(residentWallpapers, 3);
      expect(wallpaperImageCacheBytes, 3 * 2332800);
      expect(wallpaperImageCacheBytes, 6998400);
    });

    test('and it is far below the 100 MB Flutter default it replaces', () {
      expect(imageCacheReductionFactor, greaterThan(10));
      // 100 MiB is what `ImageCache` ships with; asserting the ceiling is under
      // it catches a future edit that quietly raised the budget back.
      expect(
        wallpaperImageCacheBytes,
        lessThan(100 * 1024 * 1024),
      );
    });

    test('the app really puts that ceiling on the binding', () {
      final binding = PaintingBinding.instance;
      final before = binding.imageCache.maximumSizeBytes;
      addTearDown(() => binding.imageCache.maximumSizeBytes = before);
      configureWallpaperImageCache();
      expect(binding.imageCache.maximumSizeBytes, wallpaperImageCacheBytes);
      // Idempotent, because `LexiLearnApp.initState` runs once per mount and a
      // test suite mounts the app far more than once.
      configureWallpaperImageCache();
      expect(binding.imageCache.maximumSizeBytes, wallpaperImageCacheBytes);
    });
  });
}