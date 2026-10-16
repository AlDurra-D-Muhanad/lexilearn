import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/app.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An in-memory database plus a repository, for widget and DAO tests.
///
/// **Build it in `setUp`, `setUpAll` or `tearDown`-free scope — never inside a
/// `testWidgets` body.** [TestHarness.create] opens a real database, and a
/// `testWidgets` body runs inside a fake-async zone in which a real `Future`
/// never completes on its own. Awaiting the harness there does not fail: it
/// hangs until the ten-minute test timeout, with no message naming the cause.
/// That is the same trap as the one [pumpShell] was written for, one level up,
/// and it is reached by `setUp` / `setUpAll` being outside the fake zone and
/// `testWidgets` being inside it.
class TestHarness {
  TestHarness._(this.database, this.repository);

  final Database database;
  final VocabRepository repository;

  static bool _initialised = false;

  static Future<TestHarness> create({
    List<VocabPack> packs = const <VocabPack>[],
    DateTime? now,
  }) async {
    // `flutter test` runs each test file in its own isolate, so this static
    // guard is per-file. Initialising here rather than in a `setUpAll` is what
    // makes the harness self-contained: no test file depends on another file
    // having called `sqfliteFfiInit()` first.
    if (!_initialised) {
      sqfliteFfiInit();
      _initialised = true;
    }

    // `singleInstance: false` is what makes this a real `:memory:` database.
    // Left at the default, sqflite caches its open-database helper by path and
    // would hand every harness in this isolate the SAME database — the second
    // harness would be created successfully and silently wrong.
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      singleInstance: false,
    );

    final repository = VocabRepository(
      database: db,
      clock: () => now ?? DateTime.utc(2026, 10, 14, 12),
    );
    for (final pack in packs) {
      await repository.importPack(PackCodec.encodePack(pack));
    }
    return TestHarness._(db, repository);
  }

  Future<void> dispose() => repository.close();
}

/// How long the shell's start-up query is given on the real event loop.
///
/// Long enough for an in-memory `sqflite` FFI round trip on any machine this
/// runs on, short enough not to slow the suite down. Deliberately a delay
/// rather than a spin: there is no future to await, because the query's
/// completion is driven by the FFI isolate rather than by this isolate.
const Duration shellDatabaseSettle = Duration(milliseconds: 50);

/// Mounts `LexiLearnApp` on [repository] and waits for its start-up read to land.
///
/// `runAsync` is **required**, not a nicety: a `testWidgets` body runs inside a
/// fake-async zone in which a real `Future` never completes on its own, and
/// `HomeShell` resolves the active pack from SQLite in `initState`. Without this
/// turn the shell sits there with an empty pack key and every assertion about
/// it fails for a reason that has nothing to do with the shell.
///
/// Shared rather than copied: Tasks 10, 13, 14 and 15 all reach their screens
/// through `HomeShell` and all hit this same trap.
///
/// **There are two sequential reads, so the waits are interleaved with a
/// rebuild — and the `pump()` between them is the whole trick.** The shell's read
/// fills in the active pack key. A destination that needs the pack's *entries*
/// cannot start reading until it has that key, and it learns it in
/// `didUpdateWidget`, which runs during a **rebuild** — not during the shell's
/// `setState`. So the second read has not even been *issued* when the shell's
/// turn ends, and two `runAsync` calls back to back wait for nothing: the second
/// finds no read in flight and `pumpAndSettle` issues the read and then settles
/// before it can answer. Measured, not assumed — with the pair back to back,
/// `HomeScreen`'s card was missing from every dashboard test and its read landed
/// *after* the assertions had already failed.
///
/// `HomeScreen` does exactly this — its word-of-the-day card needs the entries —
/// so it carried its own `runAsync` turn in each of the two test files that reach
/// it. That is two copies, and Tasks 13, 14 and 15 would have added three more,
/// so the turn lives here. If a destination ever grows a *third* sequential read,
/// add a `pump()`-then-`runAsync` pair here rather than copying one into a test.
Future<void> pumpShell(WidgetTester tester, VocabRepository repository) async {
  await tester.pumpWidget(LexiLearnApp(repository: repository));
  // The shell's own start-up read: this is what fills in the active pack key.
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  // Rebuild, so `didUpdateWidget` runs and the destination issues its read.
  await tester.pump();
  // The destination's read, which only now exists.
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// One real turn of the event loop, for a read that was **issued** rather than
/// awaited — a `FutureBuilder`, or a controller `start()` already in flight.
///
/// [pumpShell] is this plus the pump that makes the second read exist at all. A
/// destination or widget that mounts its own read needs only this.
///
/// Same reason as `pumpShell`, and the same ten-minute timeout if it is skipped.
Future<void> settleDatabase(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// Fires [write] — an async call that is expected to reach the database — and
/// gives it a real turn of the event loop before returning.
///
/// **Do not `await` such a call inside a `testWidgets` body.** It never
/// completes there, and the failure mode is a ten-minute timeout rather than an
/// error. This is what a controller's `answer()` looks like from a test: the
/// synchronous half (counters, and the pixels the user sees) has already run by
/// the time this returns, and the `recordAnswer` write behind it has landed.
///
/// ```dart
/// await commitAndSettle(tester, () => pushed.answer(index));
/// expect(controller.correctCount, 1);
/// ```
///
/// The alternative, `tester.runAsync(...)` around the whole call, also works but
/// runs the call outside the fake zone, so any `notifyListeners()` inside it
/// lands outside a frame. Firing it inside and then pumping keeps the widget
/// updates on the normal schedule.
Future<void> commitAndSettle(
  WidgetTester tester,
  Future<void> Function() write,
) async {
  unawaited(write());
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// Awaits [read] — a database query — from inside a `testWidgets` body.
///
/// The read-only counterpart of [commitAndSettle], and the same trap: awaited
/// bare, it hangs for the full ten minutes. `runAsync` is the only way to give a
/// real `Future` a turn from inside the fake zone.
///
/// ```dart
/// final stats = await readOutsideFakeAsync(tester, () => repository.stats('p'));
/// ```
Future<T> readOutsideFakeAsync<T>(
  WidgetTester tester,
  Future<T> Function() read,
) async =>
    (await tester.runAsync(read)) as T;
