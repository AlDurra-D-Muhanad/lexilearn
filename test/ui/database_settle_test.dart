import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/more/more_screen.dart';

import '../helpers/test_env.dart';

/// The guards on the settle that replaced a fixed delay.
///
/// **What this file is for.** `test/ui/back_navigation_test.dart` failed roughly
/// half of all full-suite runs and about a quarter of its runs on its own, with
///
/// ```
/// A Timer is still pending even after the widget tree was disposed.
/// Timer (duration: 0:00:10.000000, periodic: false), created:
///   #6  SqfliteDatabaseMixin.txnSynchronized (package:sqflite_common/src/database_mixin.dart:585:33)
///   #11 PackDao.entriesOf (package:lexilearn/data/pack_dao.dart:185:28)
///   #13 _HomeScreenState._loadPack (package:lexilearn/ui/home/home_screen.dart:220)
///   #14 _HomeScreenState.initState (package:lexilearn/ui/home/home_screen.dart:146)
/// ```
///
/// That timer is sqflite's own ten-second lock warning, created per operation and
/// cancelled only when the operation completes. So a body that returns while a
/// read is in flight fails the test, and a body that returns after one has
/// completed does not — which is why the same code passed and failed on
/// consecutive runs.
///
/// `flutter_test` *does* catch it (`binding.dart:2542`), but it catches it as a
/// framework assertion about a timer, roughly a quarter of the time, with the
/// cause three frames up a stack. These tests say the same thing **directly,
/// every time**, so the regression cannot come back silently.
const _pack = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'serenity-1', term: 'serenity', translations: <String>['هدوء']),
  ],
);

void main() {
  group('a settle waits for the database', () {
    late TestHarness harness;

    setUp(() async {
      harness = await TestHarness.create(packs: const <VocabPack>[_pack]);
    });

    tearDown(() => harness.dispose());

    testWidgets('it leaves no operation in flight, after a screen mounts one',
        (tester) async {
      await pumpShell(tester, harness.repository);

      // A destination mounting its own read is the shape every one of these
      // tests is made of: `pump()` starts the read, and nothing in the body
      // waits for it.
      await tester.tap(find.byIcon(Icons.apps));
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(harness.operationsInFlight, 0,
          reason: 'a settle must return with the database idle, because an '
              'operation still running holds sqflite\'s ten-second lock timer '
              'and flutter_test fails the test over it');
    });

    testWidgets('it drains a read a bar switch issues after the pump',
        (tester) async {
      await pumpShell(tester, harness.repository);
      await tester.tap(find.byIcon(Icons.apps));
      await settleDatabase(tester);

      // Back from a destination does not navigate, it switches the bar's index,
      // and `HomeShell` swaps the child inside one `AnimatedSwitcher` keyed by
      // that index - so `HomeScreen` **mounts afresh** and `initState` reads the
      // pack again. That read is issued *after* the settle's own drain, which is
      // why a settle that only waits for the queue it already knows about is not
      // enough; the loop has to notice that the pump started something new.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(harness.operationsInFlight, 0,
          reason: 'the remounted HomeScreen\'s read must be drained before the '
              'body ends, which is exactly what the flake was');
    });

    testWidgets('it counts the operations it waited for', (tester) async {
      final before = harness.operationsStarted;

      await pumpShell(tester, harness.repository);

      // Zero-in-flight is only a meaningful claim if reads really do start, so
      // this pins the other half: the counter is not vacuously zero.
      expect(harness.operationsStarted - before, greaterThan(0),
          reason: 'pumpShell reads the pack list and the entries; if that '
              'stopped happening the assertions above would pass for the wrong '
              'reason');
      expect(harness.operationsInFlight, 0);
    });
  });

  group('a settle waits for the database rather than for a fixed delay', () {
    late TestHarness slow;

    setUp(() async {
      // Every operation takes 120 ms of real time - more than twice the 50 ms the
      // old helper slept for - so a fixed budget cannot cover the round trip
      // **every** run, and reverting the helper fails here deterministically
      // instead of 25% of the time.
      slow = await TestHarness.create(
        packs: const <VocabPack>[_pack],
        operationDelay: const Duration(milliseconds: 120),
      );
    });

    tearDown(() => slow.dispose());

    testWidgets('a shell whose reads are slower than any fixed budget still '
        'settles', (tester) async {
      await pumpShell(tester, slow.repository);

      expect(find.byType(HomeScreen), findsOneWidget,
          reason: 'the shell reached its destination, so its reads landed');
      expect(find.byType(MoreScreen), findsNothing);
      expect(slow.operationsInFlight, 0,
          reason: 'pumpShell returned, so the database is idle - a settle that '
              'waited a fixed number of milliseconds instead would return here '
              'with these reads still running');
    });

    testWidgets('and a settle after a navigation is what drains the rest',
        (tester) async {
      await pumpShell(tester, slow.repository);

      await tester.tap(find.byIcon(Icons.apps));
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(find.byType(MoreScreen), findsOneWidget);
      expect(slow.operationsInFlight, 0);
    });
  });
}
