import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';

/// One of the user's photographs, cross-fading into its replacement.
///
/// **The cross-fade is the reason this is a `StatefulWidget` with an
/// `AnimatedSwitcher` rather than a bare `Image`.** A hard cut between two
/// photographs reads as a flicker, and a fade needs both frames alive at once —
/// which is exactly the "a cross-fade briefly needs two resident" that
/// `wallpaper_catalog.dart`'s budget allows, and the reason
/// [residentWallpapers] is 3 rather than 2.
///
/// **One photograph is warmed, never the set.** [nextAssetPath] is the *single*
/// image `precacheImage` is given, and it is given it while the current frame is
/// still fully opaque. Nothing here decodes anything by itself: `Image.asset`
/// resolves through the shared `ImageCache`, which is why the ceiling in
/// `wallpaper_catalog.dart` is a global rather than a per-widget number.
class NaturePhoto extends StatefulWidget {
  const NaturePhoto({
    super.key,
    required this.assetPath,
    this.nextAssetPath,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  /// The photograph on screen, as an asset path from `Wallpapers`.
  final String assetPath;

  /// The photograph that comes next, warmed while [assetPath] is still up.
  ///
  /// Null disables warming entirely, which is what an unknown "next" — a set of
  /// one, or a caller that has not decided yet — should mean rather than a
  /// decode nobody asked for.
  final String? nextAssetPath;

  /// **Never `BoxFit.contain`.** The two surfaces are not the same shape: the
  /// flashcard's panel is `AspectRatio(2)` and the staged files are exactly
  /// 2.0000:1, so `cover` crops nothing there; Home's word-of-the-day card is a
  /// content-sized column that measured **328 x 201 logical on the golden phone
  /// — 1.6318:1** — where `cover` scales by `201 / 540 = 0.3722` and trims
  /// `402 - 328 = 74` logical px off the width, 9.2% from each side.
  /// `contain` would letterbox instead, which on a card is a visible band of
  /// `AppSurface`'s fill above and below the picture.
  final BoxFit fit;

  /// Where a crop is taken from. `center`, because these are **centre crops
  /// already** — the framing the user chose is the middle of the frame, so
  /// there is nothing at either edge worth preferring.
  final Alignment alignment;

  /// How long one photograph takes to hand over to the next.
  ///
  /// **The brand's own 250 ms**, not a new number: it is the same duration
  /// `AppSurface` cross-fades its fill with, so a theme change and a photograph
  /// change take the same time and cannot disagree on screen.
  static const Duration crossFade = AppDurations.standard;

  @override
  State<NaturePhoto> createState() => _NaturePhotoState();
}

class _NaturePhotoState extends State<NaturePhoto> {
  /// The path last handed to `precacheImage`, so the same one is not warmed
  /// twice — once per rebuild would be a decode queued per frame.
  String? _warmed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmNext();
  }

  @override
  void didUpdateWidget(NaturePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Both halves, because the *current* frame can change without the rotation
    // having moved on — a brightness switch re-picks the index — and the
    // outgoing photograph is then the one worth warming.
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.nextAssetPath != widget.nextAssetPath) {
      _warmNext();
    }
  }

  @override
  void dispose() {
    _warmed = null;
    super.dispose();
  }

  void _warmNext() {
    final next = widget.nextAssetPath;
    if (next == null || next == widget.assetPath || next == _warmed) return;
    _warmed = next;
    // **Not in `initState`.** `precacheImage` reads `Configuration.of(context)`,
    // which resolves the ambient `DefaultAssetBundle` — an inherited widget —
    // and depending on one from `initState` is an assertion, not a style
    // preference. `didChangeDependencies` is the documented place for exactly
    // this.
    //
    // **Fired, not awaited.** The future completes when the decode does, which
    // inside a `testWidgets` body never happens (§5) and on a device happens
    // after this frame; either way the only thing the app needs from it is that
    // the bitmap is in the cache before the next advance. A decode that throws
    // is caught rather than left as an unhandled async error out of a
    // lifecycle callback: a photograph that will not load is a missing frame,
    // not a crash, and `Image.asset` falls back to whatever it can show.
    unawaited(precacheImage(AssetImage(next), context).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: NaturePhoto.crossFade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Without this the two frames are laid out at their natural sizes and
      // `AnimatedSwitcher` centres the smaller one, which on a photograph
      // means a visible hop mid-fade.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: <Widget>[...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: Image.asset(
        widget.assetPath,
        // Keyed on the path, or `AnimatedSwitcher` sees the same widget type
        // twice and treats it as an unchanged child: no fade, just a swap.
        key: ValueKey<String>(widget.assetPath),
        fit: widget.fit,
        alignment: widget.alignment,
        // No `gaplessPlayback`: the outgoing frame is already on screen, and
        // `AnimatedSwitcher` is what holds it there.
        filterQuality: FilterQuality.medium,
        // The photograph is decoration. Without this the screen reader reads a
        // filename, and `docs/engineering-standards.md` §10's rule — judge the
        // reference image, not the code — would be reading a filename too.
        excludeFromSemantics: true,
      ),
    );
  }
}