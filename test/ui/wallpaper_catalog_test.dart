import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("the user's photographs, as filed", () {
    test('there are fourteen of them, six dark and eight light', () {
      expect(Wallpapers.dark, hasLength(6));
      expect(Wallpapers.light, hasLength(8));
      expect(Wallpapers.all, hasLength(14));
    });

    test('every path is inside the declared directory and uniquely named', () {
      for (final path in Wallpapers.all) {
        expect(path, startsWith('assets/wallpapers/'), reason: path);
      }
      expect(Wallpapers.all.toSet(), hasLength(14),
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

    test('all fourteen resident would be 32.66 MB, which is why there are three',
        () {
      final allFourteen = decodedWallpaperBytes * Wallpapers.all.length;
      expect(allFourteen, 14 * 2332800);
      expect(allFourteen, 32659200);
      expect(allFourteen / 1000000, closeTo(32.66, 0.01),
          reason: 'MB, decimal');
      expect(allFourteen / 1048576, closeTo(31.14, 0.01),
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