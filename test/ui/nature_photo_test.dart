import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/wallpaper/nature_photo.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';

void main() {
  /// The photograph the host is showing, read off the widget rather than off a
  /// field: a test that asked the host what it *intended* to show would pass
  /// with the picture missing.
  String shownPath(WidgetTester tester) =>
      tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;

  Finder imageFor(WidgetTester tester, String path) => find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == path,
        description: 'Image.asset($path)',
      );

  testWidgets('it draws the photograph it is given, and only that one',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _PhotoHost(path: Wallpapers.light[0])),
    );
    expect(shownPath(tester), Wallpapers.light[0]);
    expect(imageFor(tester, Wallpapers.light[0]), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('it fills its box and never letterboxes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _PhotoHost(path: Wallpapers.light[0])),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover,
        reason: 'contain would put a band of surface above and below a card');
    expect(image.alignment, Alignment.center,
        reason: 'these are centre crops, so there is no better edge to prefer');
    expect(image.excludeFromSemantics, isTrue,
        reason: 'a photograph is decoration, not something to read aloud');
  });

  testWidgets('a change cross-fades: both photographs are on screen at once, '
      'mid-fade, neither at full strength', (tester) async {
    // **"Smoothly" is a claim, so this is the measurement of it.** A hard swap
    // shows exactly one `Image` at every instant; a fade shows two, with the
    // incoming one part-way through.
    await tester.pumpWidget(
      MaterialApp(home: _PhotoHost(path: Wallpapers.light[0])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: _PhotoHost(path: Wallpapers.light[1])),
    );
    await tester.pump();

    // Mid-fade, not at the start and not at the end.
    await tester.pump(NaturePhoto.crossFade ~/ 2);

    expect(find.byType(Image), findsNWidgets(2),
        reason: 'a cross-fade needs both frames resident; one means a hard cut');
    expect(imageFor(tester, Wallpapers.light[0]), findsOneWidget,
        reason: 'the outgoing photograph has gone already');
    expect(imageFor(tester, Wallpapers.light[1]), findsOneWidget,
        reason: 'the incoming photograph has not arrived yet');

    // Both are genuinely part-way: neither is opaque, neither is invisible.
    // **Scoped to the `NaturePhoto`'s own subtree**: `MaterialApp` builds its
    // own `FadeTransition`s for route changes, and reading the whole tree gave
    // six opacities instead of the two this is about.
    final opacities = <double>[];
    for (final element
        in find.descendant(of: find.byType(NaturePhoto), matching: find.byType(FadeTransition))
            .evaluate()) {
      opacities.add((element.widget as FadeTransition).opacity.value);
    }
    expect(opacities, hasLength(2),
        reason: 'one fade per frame, and there are two frames');
    for (final value in opacities) {
      expect(value, greaterThan(0.0));
      expect(value, lessThan(1.0));
    }

    // And it lands.
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(imageFor(tester, Wallpapers.light[1]), findsOneWidget);
    expect(shownPath(tester), Wallpapers.light[1]);
  });

  testWidgets('the fade lasts the brand duration, not a new number',
      (tester) async {
    expect(NaturePhoto.crossFade, AppDurations.standard);
    expect(NaturePhoto.crossFade, greaterThan(Duration.zero));
  });

  testWidgets('at most two photographs are ever resident, out of fourteen',
      (tester) async {
    // **Ruling C made checkable.** The constraint is not "the cache is small"
    // but "the widget tree never asks for more than the cross-fade needs". A
    // future edit that precached the whole set would show three or more here.
    expect(Wallpapers.all.length, 14);

    await tester.pumpWidget(
      MaterialApp(home: _PhotoHost(path: Wallpapers.light[0])),
    );
    await tester.pumpAndSettle();
    var previous = Wallpapers.light[0];
    for (final next in Wallpapers.light.sublist(1)) {
      // Let the previous change land first, so the count below is the count
      // during *this* fade and not the accumulation of unfinished ones.
      await tester.pumpWidget(
        MaterialApp(home: _PhotoHost(path: next, next: _successor(next))),
      );
      await tester.pump(NaturePhoto.crossFade ~/ 2);

      expect(find.byType(Image), findsNWidgets(2),
          reason: 'only the outgoing and the incoming photograph are resident');
      final names = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => (i.image as AssetImage).assetName)
          .toSet();
      expect(names, <String>{previous, next});

      await tester.pumpAndSettle();
      previous = next;
      expect(find.byType(Image), findsOneWidget,
          reason: 'the finished fade left two photographs behind');
    }
  });

  testWidgets('with no known next, nothing is warmed and one frame is shown',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _PhotoHost(path: Wallpapers.dark[0])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(shownPath(tester), Wallpapers.dark[0]);
  });
}

/// The photograph after [path] in the user's filed order, wrapped so the host
/// can be built without a `const`.
String _successor(String path) {
  final list = Wallpapers.all;
  return list[(list.indexOf(path) + 1) % list.length];
}

/// A bare host: a fixed-size box with one [NaturePhoto] in it, so the widget
/// under test has constraints and a `DefaultAssetBundle` above it.
class _PhotoHost extends StatelessWidget {
  const _PhotoHost({required this.path, this.next});

  final String path;
  final String? next;

  @override
  Widget build(BuildContext context) => Material(
        child: Center(
          child: SizedBox(
            width: 328,
            height: 201,
            child: NaturePhoto(assetPath: path, nextAssetPath: next),
          ),
        ),
      );
}