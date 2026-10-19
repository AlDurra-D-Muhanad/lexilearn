import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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

/// Sizes the surface like the phone the artwork is drawn on: 360×780 logical.
///
/// **Not a convenience — a precondition for tapping a Home grid tile.** The
/// default test surface is 800×600, which is tall enough for Home's header, its
/// search field and the *first* row of the 2×2 quick-launch grid and no further.
/// The second row lands below the root, and `tap` on an off-screen widget
/// throws rather than scrolling to it: measured, the centre of `إحصائياتك`
/// resolves to `Offset(204.0, 865.4)` on an 800×600 surface, and `tap` reports
/// "would not hit test on the specified widget … outside the bounds of the root
/// of the render tree, Size(800.0, 600.0)".
///
/// Shared rather than copied because two test files hit it and the copy is
/// byte-identical: `test/ui/home_screen_test.dart` and
/// `test/ui/stats_screen_test.dart`, both of which tap a tile in that second
/// row. 360×780 is the golden's own logical size
/// (`test/goldens/golden_test.dart` sets the same 1080×2340 at 3× by hand).
void useAPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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

/// One real turn **before** `pumpAndSettle` — the opposite order to
/// [settleDatabase].
///
/// **Use this, not [settleDatabase], for anything that sits behind an
/// indeterminate progress indicator.** `HomeScreen`'s results list shows a
/// `CircularProgressIndicator` while its read is in flight (`_results()`), and
/// that widget schedules frames forever, so a `pumpAndSettle` that runs while it
/// is on screen **never returns**. [settleDatabase] pumps first and takes its
/// real turn second, so it is the wrong helper there — and the failure is a
/// `pumpAndSettle timed out` with no hint about which widget is animating.
///
/// Measured, in `test/goldens/golden_test.dart`: *word detail user shot* failed
/// with `pumpAndSettle timed out` in both modes until the order was swapped.
///
/// Shared rather than copied: `home_screen_test.dart`'s `_search` was doing the
/// identical two lines privately, so there were two copies of a dance whose
/// ordering is the entire point. `docs/engineering-standards.md` §5 forbids the
/// copy; a third arriving with Task 15 is what the copy invites.
Future<void> realTurnThenSettle(WidgetTester tester) async {
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

/// The WCAG 2.1 relative-luminance contrast ratio between two opaque colours,
/// as the number the guidelines quote: `(L_lighter + 0.05) / (L_darker + 0.05)`.
///
/// **Why it lives here rather than in a test file.** "The ink passes AA" is a
/// claim, and `docs/engineering-standards.md` §1 says a claim in prose is not
/// evidence. Asserting `expect(ratio, greaterThanOrEqualTo(4.5))` puts the
/// threshold where a regression can fail, and computing it in two files is two
/// chances to compute it differently — so there is one implementation, and the
/// per-channel linearisation is written out rather than delegated to
/// `computeLuminance`, which is the same formula with a different spelling.
///
/// The `math.pow(...).toDouble()` is a `num`/`double` narrowing, not a
/// correction: `pow` returns `num`, and this file's helper returns `double`.
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// Arabic runs — U+0600 to U+06FF — in a string.
///
/// The range is **Arabic and nothing else on purpose**: it is the block Tajawal
/// covers and the block Inter does not, so it is exactly the set of codepoints
/// where picking the wrong family produces tofu. Widening it would add codepoints
/// whose absence from Inter is not a defect.
final RegExp _arabicRun = RegExp('[\u0600-\u06FF]');

/// Every Arabic string drawn under [screenType], with the font family it would
/// **actually render in**.
///
/// **The resolved family, not `Text.style.fontFamily`.** A bare `Text('…')` has a
/// null style and inherits Tajawal from the theme, so reading `style?.fontFamily`
/// would report null for a correctly-set string and would not notice if the theme
/// itself were wrong. This merges the ambient `DefaultTextStyle` at the widget's
/// own element with the widget's style, which is what the engine paints.
///
/// **Why it lives here and not in a screen's test file.** The defect it catches is
/// a *class*, not a string. It arrived on this project as one Arabic string set in
/// `AppText.latin`, which rasterised as a row of tofu boxes — and
/// `find.text('السحب للتالي')` matched it happily, because a tofu row is still a
/// `Text` whose `data` is that string. Every assertion on the string passed; only
/// opening the generated PNG showed it. A per-string assertion cannot prevent the
/// next one, because the next one is a different string. So the guard is stated
/// over *every* Arabic string on a screen, and this is the shared shape of it that
/// the next screen will want.
///
/// Callers assert the families themselves, so the failure names the string:
///
/// ```dart
/// final offenders = arabicRunsIn(tester, MyScreen)
///     .where((run) => run.family == 'Inter')
///     .toList();
/// expect(offenders, isEmpty);
/// ```
List<({String text, String? family})> arabicRunsIn(
  WidgetTester tester,
  Type screenType,
) {
  final found = <({String text, String? family})>[];
  for (final widget in tester.widgetList<Text>(
    find.descendant(of: find.byType(screenType), matching: find.byType(Text)),
  )) {
    final data = widget.data;
    // `Text.rich` and `TextSpan` carry no `data`, and neither is used for a
    // sentence of UI copy in this app; skipped rather than guessed at.
    if (data == null || !_arabicRun.hasMatch(data)) continue;
    final ambient = DefaultTextStyle.of(tester.element(find.byWidget(widget))).style;
    found.add((text: data, family: ambient.merge(widget.style).fontFamily));
  }
  return found;
}
