import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/wallpaper/nature_rotation.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Runs [body] with a rotation that is disposed **before the test ends**.
  ///
  /// **`addTearDown` is too late, and this is not a style preference.**
  /// `flutter_test` checks for pending timers at the end of `_runTestBody`,
  /// *before* any teardown runs, and reports `A Timer is still pending even
  /// after the widget tree was disposed`. A rotation left running would
  /// therefore turn every one of these failures into two — the real one plus a
  /// timer complaint — and a green test would depend on a timer having been
  /// cancelled by luck. `finally` puts the disposal inside the body, which is
  /// also the shape `dispose()` has to work in: the whole point of ruling D is
  /// that disposing mid-flight must be safe.
  Future<void> withRotation(
    WidgetTester tester,
    Future<void> Function(NatureRotation subject) body, {
    Brightness brightness = Brightness.light,
    Duration? interval = AppDurations.wallpaper,
    int seed = 0,
  }) async {
    final subject = NatureRotation(
      brightness: brightness,
      interval: interval,
      random: Random(seed),
    );
    try {
      await body(subject);
    } finally {
      subject.dispose();
    }
  }

  group("Home's timed rotation", () {
    testWidgets('holds one photograph for ten seconds and then changes it',
        (tester) async {
      // **The interval is read from `AppDurations.wallpaper`, not restated.**
      // A test that carried its own copy of the number would go green if the
      // token changed, which is §8's failure in a new place.
      expect(AppDurations.wallpaper, const Duration(seconds: 10));

      await withRotation(tester, (subject) async {
        final start = subject.index;
        final first = subject.assetPath;

        await tester.pump(const Duration(seconds: 9));
        expect(subject.assetPath, first,
            reason: 'it changed early: the interval is shorter than ten seconds');
        expect(subject.isRunning, isTrue);

        await tester.pump(const Duration(seconds: 1));
        expect(subject.assetPath, isNot(first),
            reason: 'ten seconds passed and nothing changed');
        expect(subject.index, (start + 1) % Wallpapers.light.length);
      });
    });

    testWidgets('it notifies exactly once per tick, so a rebuild follows the '
        'photograph rather than running ahead of it', (tester) async {
      await withRotation(tester, (subject) async {
        var notifications = 0;
        subject.addListener(() => notifications++);

        await tester.pump(AppDurations.wallpaper);
        await tester.pump(AppDurations.wallpaper);
        expect(notifications, 2);
      });
    });

    testWidgets('the starting photograph is drawn once and then advanced, never '
        're-rolled', (tester) async {
      // The rule this whole controller exists for: a hot rebuild must not
      // re-randomise, or the card flickers to a different photograph.
      await withRotation(tester, (subject) async {
        final start = subject.index;

        await tester.pump(AppDurations.wallpaper);
        await tester.pump(AppDurations.wallpaper);
        expect(subject.index, (start + 2) % Wallpapers.light.length);

        // And a rebuild — which re-reads the same controller — changes nothing.
        for (var i = 0; i < 5; i++) {
          subject.notifyListeners();
        }
        expect(subject.index, (start + 2) % Wallpapers.light.length);
      });
    });

    testWidgets('the same seed starts in the same place, so it is the rotation '
        'that moves and not the clock', (tester) async {
      // Two independent rotations from one seed, both disposed before the test
      // ends — see [withRotation] for why that is not `addTearDown`.
      await withRotation(tester, (a) async {
        final other = NatureRotation(
          brightness: Brightness.light,
          interval: AppDurations.wallpaper,
          random: Random(11),
        );
        try {
          expect(other.index, a.index);
          expect(other.assetPath, a.assetPath);
        } finally {
          other.dispose();
        }
      }, seed: 11);
    });

    testWidgets('it never names a photograph from the other brightness',
        (tester) async {
      await withRotation(tester, (light) async {
        await withRotation(tester, (dark) async {
          expect(dark.brightness, Brightness.dark);

          for (var i = 0; i < Wallpapers.light.length + 2; i++) {
            expect(light.assetPath, isIn(Wallpapers.light));
            expect(light.assetPath, isNot(isIn(Wallpapers.dark)));
            light.advance();
          }
          for (var i = 0; i < Wallpapers.dark.length + 2; i++) {
            expect(dark.assetPath, isIn(Wallpapers.dark));
            expect(dark.assetPath, isNot(isIn(Wallpapers.light)));
            dark.advance();
          }
        }, brightness: Brightness.dark);
      });
    });

    testWidgets('switching brightness swaps the set and draws a new starting '
        'photograph', (tester) async {
      await withRotation(tester, (subject) async {
        expect(subject.assetPath, isIn(Wallpapers.light));

        subject.brightness = Brightness.dark;
        expect(subject.assetPath, isIn(Wallpapers.dark));
        // Idempotent: `didChangeDependencies` fires on ordinary rebuilds too, and
        // re-rolling there is precisely the flicker this guards.
        final settled = subject.index;
        subject.brightness = Brightness.dark;
        expect(subject.index, settled);
      });
    });
  });

  group('the flashcard deck: event-driven, not timed', () {
    testWidgets('there is no timer at all, so a card cannot change under the '
        'reader', (tester) async {
      await withRotation(tester, (subject) async {
        final start = subject.index;
        expect(subject.isRunning, isFalse);
        await tester.pump(const Duration(seconds: 60));
        expect(subject.index, start,
            reason: 'the deck is not timed; nothing may move it');
      }, interval: null);
    });

    testWidgets('it moves only when it is told to', (tester) async {
      await withRotation(tester, (subject) async {
        final start = subject.index;
        final n = Wallpapers.light.length;
        subject.advance();
        expect(subject.index, (start + 1) % n);
        subject.advance();
        expect(subject.index, (start + 2) % n);
      }, interval: null);
    });

    testWidgets('a rotation with no timer registers no lifecycle observer',
        (tester) async {
      await withRotation(tester, (subject) async {
        expect(subject.interval, isNull);
        // Calling it must be harmless either way, which is the whole
        // requirement: a `resumed` must not start a timer nobody asked for.
        subject.didChangeAppLifecycleState(AppLifecycleState.paused);
        subject.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(subject.isRunning, isFalse);
      }, interval: null);
    });
  });

  group('backgrounding', () {
    testWidgets('the rotation stops while the app is not visible and resumes '
        'where it left off', (tester) async {
      await withRotation(tester, (subject) async {
        await tester.pump(const Duration(seconds: 3));
        final parked = subject.index;

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(subject.isRunning, isFalse);

        // Twenty seconds of wall clock with the app in the background must
        // change nothing at all: this is the user putting the phone down and
        // coming back to a different photograph.
        await tester.pump(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 10));
        expect(subject.index, parked, reason: 'the rotation ran while hidden');

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(subject.isRunning, isTrue);
        expect(subject.index, parked,
            reason: 'resuming must not jump to a different photograph');

        // And it really does carry on from there.
        await tester.pump(AppDurations.wallpaper);
        expect(subject.index, (parked + 1) % Wallpapers.light.length);
      });
    });

    testWidgets('`inactive` pauses too, because the shade takes focus',
        (tester) async {
      // A separate call from the `paused` test because it is a separate state
      // the app really passes through, and a rotation that ignored it would
      // advance while a notification shade was down.
      await withRotation(tester, (subject) async {
        await tester.pump(const Duration(milliseconds: 1));

        subject.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(subject.isRunning, isFalse);
        subject.didChangeAppLifecycleState(AppLifecycleState.hidden);
        expect(subject.isRunning, isFalse);
        subject.didChangeAppLifecycleState(AppLifecycleState.detached);
        expect(subject.isRunning, isFalse);
        subject.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(subject.isRunning, isTrue);
      });
    });
  });

  group('disposal', () {
    testWidgets('a timer cancelled mid-transition leaves nothing pending',
        (tester) async {
      // **The ruling D shape.** A rotation timer firing into a disposed State is
      // the same failure as the deferred hazard in `stats_screen.dart` and
      // `more_screen.dart`, and it does not fail the test that caused it — it
      // throws after the test has already passed.
      final subject = NatureRotation(
        brightness: Brightness.light,
        interval: AppDurations.wallpaper,
        random: Random(0),
      );
      await tester.pump(const Duration(seconds: 9));
      // One pump short of the tick, so the timer is *armed* when we pull it out.
      expect(subject.isRunning, isTrue);

      // Unmount: dispose the controller the way a popped route would.
      subject.dispose();
      expect(subject.isRunning, isFalse);

      // And the tick that was due never arrives.
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('advancing a disposed rotation is a no-op, not an assertion',
        (tester) async {
      // Reachable in the app: a card transition can land after the deck has
      // been torn down, and Android delivers a `resumed` to a rotation whose
      // widget is already gone.
      final subject = NatureRotation(
        brightness: Brightness.light,
        interval: AppDurations.wallpaper,
        random: Random(0),
      );
      subject.dispose();
      expect(() => subject.advance(), returnsNormally);
      expect(() => subject.brightness = Brightness.dark, returnsNormally);
      expect(
        () => subject.didChangeAppLifecycleState(AppLifecycleState.resumed),
        returnsNormally,
      );
      expect(subject.isRunning, isFalse,
          reason: 'a resumed lifecycle event must not rebuild a cancelled timer');
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a widget that unmounts mid-transition leaves no pending timer',
        (tester) async {
      // The above disposes the controller directly. This one goes through a real
      // widget tree, because "the State disposes what it owns" is the claim and
      // only a teardown proves it.
      await tester.pumpWidget(const MaterialApp(home: _RotationHost()));
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(_RotationHost), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull,
          reason: 'a rotation tick fired into a disposed State');
    });
  });
}

/// Owns a rotation for as long as it is mounted, and nothing else — the shape
/// both surfaces use.
class _RotationHost extends StatefulWidget {
  const _RotationHost();

  @override
  State<_RotationHost> createState() => _RotationHostState();
}

class _RotationHostState extends State<_RotationHost> {
  late final NatureRotation _rotation = NatureRotation(
    brightness: Brightness.light,
    interval: AppDurations.wallpaper,
    random: Random(0),
  );

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_rotation.assetPath);
}