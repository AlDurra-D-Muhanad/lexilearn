import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'wallpaper_catalog.dart';

/// One rotating photograph index, for one surface.
///
/// **Two instances in the app, one class — and that is the answer to "one
/// controller or two".** Home and the flashcard deck want different *triggers*
/// and must not share an *index*:
///
/// * Home is **timed**: «تبديل كل 10 ثوانٍ» — [interval] is set and the timer
///   advances the index every ten seconds on its own.
/// * The deck is **event-driven**: «في نافذة البطاقات تتبدل عند كل انتقال من
///   بطاقة لأخرى» — [interval] is null, no timer exists at all, and the owner
///   calls [advance] from `didUpdateWidget` when the card under it changes.
///
/// Sharing a single instance would mean Home's ten-second timer kept burning
/// while the user read flashcards, advancing an index nobody could see, and a
/// swipe would move Home's photograph behind the user's back. Two instances of
/// one class keep the memory discipline, the lifecycle pause and the dispose
/// guards written exactly once.
///
/// **Every guarantee here is measured by a test, not by this comment.** See
/// `test/ui/nature_rotation_test.dart`.
class NatureRotation extends ChangeNotifier with WidgetsBindingObserver {
  /// [interval] null means **event-driven**: no timer is created, and only
  /// [advance] moves the index. That is the flashcard deck's whole difference
  /// from Home.
  ///
  /// **Assigned in the body rather than through an initializing formal**, because
  /// the field is private and the parameter is not: `this._brightness` would
  /// rename the public parameter to `_brightness`, which no other library could
  /// pass. The field carries a default of its own so the declaration is legal,
  /// and [initState]-time code overwrites it before anything reads it.
  NatureRotation({
    required Brightness brightness,
    this.interval,
    Random? random,
  }) : _random = random ?? Random() {
    _brightness = brightness;
    _index = _startIndex();
    if (interval != null) WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  /// How long one photograph holds before the next one cross-fades in, or null
  /// for a rotation nothing times.
  final Duration? interval;

  final Random _random;

  Brightness _brightness = Brightness.light;
  late int _index;
  Timer? _timer;

  /// Set in [dispose] and checked by every entry point below.
  ///
  /// **This is ruling D, and the flag is the point.** `ChangeNotifier` asserts
  /// on `notifyListeners()` after disposal, and a `Timer` that fires after its
  /// owner is gone throws from the timer body — neither is a useful error, and
  /// a rotation timer racing an image decode is exactly the shape of the
  /// deferred hazard `stats_screen.dart:134-136` and `more_screen.dart:179-181`
  /// already carry. `advance` is reachable from a card transition that lands
  /// after the deck has been torn down, so the public entry point is guarded
  /// too, not only the private timer callback.
  bool _disposed = false;

  Brightness get brightness => _brightness;

  /// The photographs this brightness may draw, in the user's filed order.
  List<String> get assets => Wallpapers.forBrightness(_brightness);

  /// The photograph on screen right now.
  String get assetPath => assets[_index];

  /// The photograph that will replace it — the one `NaturePhoto` warms while
  /// this one is still up.
  String get nextAssetPath {
    final list = assets;
    if (list.length < 2) return assetPath;
    return list[(_index + 1) % list.length];
  }

  int get index => _index;

  /// Whether a timer is actually running.
  ///
  /// A test reads this rather than inferring it from an image change, because
  /// "the picture did not move" is also what a paused-but-warm timer looks
  /// like for the first ten seconds.
  bool get isRunning => _timer?.isActive ?? false;

  /// Move to the next photograph and tell whoever is listening.
  ///
  /// **The public entry point is guarded** for the reason [dispose] gives.
  void advance() {
    if (_disposed) return;
    final list = assets;
    if (list.isEmpty) return;
    _index = (_index + 1) % list.length;
    notifyListeners();
  }

  /// Switch to the other brightness's set.
  ///
  /// **The starting index is drawn again, once, and only because the new set has
  /// a different number of photographs** — index 4 of eight is a different
  /// picture from index 4 of six. Everything else, including a hot rebuild,
  /// leaves [_index] alone.
  set brightness(Brightness value) {
    if (_disposed || _brightness == value) return;
    _brightness = value;
    _index = _startIndex();
    notifyListeners();
  }

  /// **Once per session, never per build.**
  ///
  /// [random] null means the default generator, which is what the app uses: a new
  /// [Random] per rotation, so two sessions begin on different photographs. A
  /// **seed** is what the reference-image capture passes, and it is the same seam
  /// `FlashcardController.random` and `QuizController.random` already are — a
  /// reference image that photographs a different picture on every regeneration
  /// is a reference nobody can compare against, which is the objection
  /// `golden_test.dart` already records about the word of the day moving with
  /// the calendar.
  ///
  /// Re-rolling on a rebuild is what makes a card flicker to a different
  /// photograph on each hot rebuild, so this is called from the constructor and
  /// from [brightness] and from nowhere else.
  int _startIndex() {
    final list = assets;
    if (list.length < 2) return 0;
    return _random.nextInt(list.length);
  }

  // --- the timer -----------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    // **Checked here as well as in [advance].** The lifecycle callback below is
    // the one path that reaches this after disposal — Android delivers a
    // `resumed` to a rotation whose widget was already torn down, and without
    // this guard it would build a brand-new timer that nothing will ever cancel.
    // Caught by `test/ui/nature_rotation_test.dart` → *advancing a disposed
    // rotation is a no-op*: with the check removed, `isRunning` read `true` on a
    // rotation that had already been disposed.
    if (_disposed || interval == null) return;
    _timer = Timer.periodic(interval!, (_) => _tick());
  }

  /// The timer body. Guarded twice over: [_disposed] for the case where the
  /// timer fired between `dispose` cancelling it and Dart noticing, and the
  /// mounted check inside [advance] is the notification's own guard.
  void _tick() {
    if (_disposed) return;
    advance();
  }

  // --- lifecycle (ruling E) ------------------------------------------------------

  /// **Pause while the app is not visible, and resume where it left off.**
  ///
  /// The index is untouched, so coming back to the app shows the photograph the
  /// user left rather than jumping to another one; only the countdown restarts.
  ///
  /// `inactive` is included on purpose: it is the state an app passes through
  /// when the notification shade or a dialog takes focus, and a rotation that
  /// kept running there would advance while the user was not looking.
  ///
  /// Written as a resume / everything-else pair rather than a `switch`, because
  /// "paused means pause" is the rule and the four states that mean it are
  /// listed only so the next reader can see which ones were considered.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      return;
    }
    // `inactive`, `paused`, `hidden` and `detached` all mean "not on screen".
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    // Removed only here. A live observer on `WidgetsBinding` after disposal is
    // a message callback into a dead object, and the lifecycle callback above
    // starts a timer — which would then outlive the widget it belongs to.
    if (interval != null) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}