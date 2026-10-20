import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/app.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/dictionary/dictionary_controller.dart';
import 'package:lexilearn/ui/link/external_link.dart';
import 'package:lexilearn/ui/settings/app_settings_controller.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
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
  TestHarness._(this.database, this._inner, this.repository);

  /// The harness's database, wrapped so every operation is counted.
  ///
  /// Counting is what lets a settle know that it has finished, rather than
  /// guessing with a fixed delay - see [_DatabaseOperations] and
  /// [_settleUntilIdle].
  final Database database;

  final Database _inner;
  final VocabRepository repository;

  /// How many operations the app has started and not yet finished.
  ///
  /// **The thing a test body must not leave behind.** A `sqflite` operation that
  /// is still running when a `testWidgets` body returns holds a real ten-second
  /// timer - `utils.lockWarningDuration`, created in
  /// `sqflite_common/src/database_mixin.dart:583-591` and cancelled only when the
  /// operation completes - which `flutter_test` counts as a pending timer and
  /// fails the test over. Zero here is the property that stops one screen's
  /// start-up read from becoming somebody else's flake.
  int get operationsInFlight => _operations.inFlight;

  /// How many operations the app has ever started, finished ones included.
  int get operationsStarted => _operations.started;

  static bool _initialised = false;

  static Future<TestHarness> create({
    List<VocabPack> packs = const <VocabPack>[],
    DateTime? now,
    String? path,
    Duration operationDelay = Duration.zero,
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
    //
    // **`path` is the one way to get a harness that survives a restart.** The
    // theme preference has to outlive the process, and "outlives the process" is
    // not testable against `:memory:`: `singleInstance: false` means a second
    // harness at that path is a *different, empty* database, which is a fresh
    // install rather than a restart. Point two harnesses at the same file and
    // the second one opens the first one's data — that is what
    // `test/ui/app_settings_test.dart` → *the theme choice survives a restart*
    // uses, and it is the only distinction that makes that test mean anything.
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path ?? inMemoryDatabasePath,
      singleInstance: false,
    );

    final counted = _CountingDatabase(db, operationDelay);
    _operations = _DatabaseOperations();
    _liveDatabase = db;

    final repository = VocabRepository(
      database: counted,
      clock: () => now ?? DateTime.utc(2026, 10, 14, 12),
    );
    for (final pack in packs) {
      await repository.importPack(PackCodec.encodePack(pack));
    }
    return TestHarness._(counted, db, repository);
  }

  Future<void> dispose() async {
    if (identical(_liveDatabase, _inner)) _liveDatabase = null;
    await repository.close();
  }
}

/// How many database operations this test isolate has in flight.
///
/// **One per isolate, not one per harness**, and that is deliberate: `flutter
/// test` runs each test file in its own isolate, so a file has at most one
/// harness open at a time, and "is anything in flight" is a question about the
/// isolate rather than about one database. The restart fixture in
/// `app_settings_test.dart` opens two harnesses in sequence, never together, so
/// the count still means what it says.
_DatabaseOperations _operations = _DatabaseOperations();

/// The unwrapped, uncounted database of the live harness, used by
/// [drainDatabase]'s probe. Deliberately not counted: the probe is the settle's
/// own work, and [TestHarness.operationsInFlight] is a statement about what the
/// *app* started.
Database? _liveDatabase;

/// A [Database] that counts every operation and can be made to answer slowly.
///
/// **Why a delegate rather than a counter inside each DAO.** The question a
/// settle has to answer is "has the *database* finished?", and only counting at
/// the database answers it. A counter above this layer would miss a read issued
/// from anywhere else, and this app's own rule is that `lib/ui/` reaches data
/// only through `VocabRepository` - the delegate sits below that rule rather
/// than above it, so nothing can route around it.
class _CountingDatabase implements Database {
  _CountingDatabase(this._inner, this._delay);

  final Database _inner;

  /// A real delay in front of every operation, for [TestHarness.create]'s
  /// `operationDelay` seam. Zero in every test but one.
  final Duration _delay;

  Future<T> _run<T>(Future<T> Function() action) async {
    _operations.started++;
    try {
      // The operation is **started first** and the delay awaited after it, not
      // the other way round. Two reasons, both measured:
      //
      //  * An operation that fails synchronously - sqflite's `checkNotClosed`
      //    throws before the future exists - must fail just as fast. Delaying
      //    first would turn `app_settings_test.dart`'s *a failed read leaves the
      //    controller on the system theme* into §5's ten-minute hang, because a
      //    real timer's completion is a fake-zone microtask that no pump runs
      //    while the body is awaiting the read.
      //  * It is what "slower" honestly means: the operation takes at least
      //    [Duration], rather than starting that much later. A settle waiting on
      //    [TestHarness.operationsInFlight] cannot tell the difference, and
      //    neither can anything else that matters.
      final future = action();
      if (_delay > Duration.zero) await _realDelay(_delay);
      return await future;
    } finally {
      _operations.finished++;
    }
  }

  @override
  String get path => _inner.path;

  @override
  bool get isOpen => _inner.isOpen;

  @override
  Database get database => this;

  @override
  Future<void> close() => _run(_inner.close);

  /// Counted once for the whole transaction, which is the right granularity: a
  /// transaction holds sqflite's `_rawLock` for its whole duration, so it is one
  /// thing a settle is waiting for, not several.
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) =>
      _run(() => _inner.transaction(action, exclusive: exclusive));

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _run(() => _inner.readTransaction(action));

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _run(() => _inner.execute(sql, arguments));

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _run(() => _inner.rawInsert(sql, arguments));

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _run(() => _inner.insert(
            table,
            values,
            nullColumnHack: nullColumnHack,
            conflictAlgorithm: conflictAlgorithm,
          ));

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) =>
      _run(() => _inner.rawQuery(sql, arguments));

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) =>
      _run(() => _inner.rawQueryCursor(sql, arguments, bufferSize: bufferSize));

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) =>
      _run(() => _inner.queryCursor(
            table,
            distinct: distinct,
            columns: columns,
            where: where,
            whereArgs: whereArgs,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
            bufferSize: bufferSize,
          ));

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _run(() => _inner.query(
            table,
            distinct: distinct,
            columns: columns,
            where: where,
            whereArgs: whereArgs,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          ));

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _run(() => _inner.rawUpdate(sql, arguments));

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _run(() => _inner.update(
            table,
            values,
            where: where,
            whereArgs: whereArgs,
            conflictAlgorithm: conflictAlgorithm,
          ));

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _run(() => _inner.rawDelete(sql, arguments));

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) =>
      _run(() => _inner.delete(table, where: where, whereArgs: whereArgs));

  /// Not counted, and neither is the batch's `commit`: a batch opens a
  /// transaction, and *that* is the operation a settle waits for.
  @override
  Batch batch() => _inner.batch();

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      // ignore: deprecated_member_use
      _run(() => _inner.devInvokeMethod<T>(method, arguments));

  @override
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) =>
      // ignore: deprecated_member_use
      _run(() => _inner.devInvokeSqlMethod<T>(method, sql, arguments));
}

/// The two counters, and nothing else.
class _DatabaseOperations {
  int started = 0;
  int finished = 0;

  int get inFlight => started - finished;
}

/// A delay on the **real** event loop, even from inside a fake-async test body.
///
/// **A plain `Future.delayed` here would be the opposite of what is wanted.** A
/// `testWidgets` body runs in a zone where `fake_async` owns `Timer`, so
/// `Future.delayed` creates a timer that fires only when the fake clock is
/// advanced by a `pump` - no wall-clock time passes at all, and a "slow
/// database" built from one would answer instantly. `Zone.root.createTimer` is
/// called on the root zone directly, so `fake_async`'s zone specification never
/// sees it and the delay is the real kind. This is the escape
/// `tester.runAsync` exists for, spelled out for a helper rather than a test.
Future<void> _realDelay(Duration duration) {
  final completer = Completer<void>();
  Zone.root.createTimer(duration, completer.complete);
  return completer.future;
}

/// How long a single drain may take before the settle says so.
///
/// **A bound, not a budget.** The settle's exit condition is "the database is
/// idle"; this only stops a *deadlock* becoming §13's first hang, which has no
/// message of its own. Ten seconds is orders of magnitude above an in-memory
/// round trip and far below `flutter_test`'s `Timeout.none`.
const Duration databaseDrainTimeout = Duration(seconds: 10);

/// How many drain-and-pump rounds a settle may run before it gives up.
///
/// **A bound, not a budget**, and it fails the test rather than returning
/// quietly: a settle that returns with work still in flight is the bug this
/// whole change exists to remove, so reaching the bound must be a red test.
///
/// Generous, because the slow fixture in `test/ui/database_settle_test.dart`
/// deliberately makes every operation take 120 ms of real time and a settle has
/// to outlast that by polling rather than by sleeping: each round costs one
/// in-memory round trip, so 120 ms is a few hundred of them. A real round trip
/// is orders of magnitude under that, so a real suite run never comes near this
/// number - and if it ever did, that is a signal worth reading rather than a
/// number worth raising.
const int maxDatabaseSettleRounds = 1000;

/// One real turn of the event loop, spent as a question to the database.
///
/// **Why a query and not a delay.** `databaseFactoryFfi` is the *isolate*
/// factory - `sqflite_common_ffi/lib/src/database_factory_ffi_io.dart:36-41`
/// routes every call through `ffiMethodCallhandleInIsolate` - so a read is
/// answered by a `SendPort` message to another isolate and a `ReceivePort` reply
/// (`isolate_io.dart:68-85`). That reply is a **real event-loop event**, not a
/// microtask, which is exactly why `pump()` cannot finish a read and `runAsync`
/// can. A body that returns while one is out leaves sqflite's ten-second
/// lock-warning timer pending, and `flutter_test` fails the test over it.
///
/// On this side of the port, `SqfliteDatabaseMixin.txnSynchronized` queues every
/// non-transactional operation on `_rawLock`, a Dart-side non-reentrant `Lock`
/// (`database_mixin.dart:549-593`). So a probe issued now **cannot complete until
/// everything already queued has finished**: awaiting it is a statement about the
/// database's state, where `Future.delayed(50ms)` is a guess about how long this
/// machine might take.
///
/// That guess is the class of bug this replaces. A fixed budget holds on an idle
/// machine and loses on a busy one, and §5 already recorded the symptom without
/// naming the cause - "the DB-settle wait was measured at 2 turns under load
/// against a 3-turn budget".
///
/// **The probe is not, by itself, sufficient, and the reason is worth writing
/// down.** An operation issued from inside a frame - which is every read a screen
/// starts - resumes on a continuation parked in the **fake** zone, so it cannot
/// complete while the settle is inside `runAsync` and no `pump` is running. The
/// probe therefore returns promptly while such an operation is still running,
/// and the counter - not the probe - is what decides the loop has finished.
Future<void> drainDatabase() async {
  final db = _liveDatabase;
  if (db == null) return;
  // **The probe is the real turn, and no explicit delay is added on top.**
  // Awaiting a query to another isolate already blocks this isolate's event loop
  // for however long the round trip takes - measured here at a fraction of a
  // millisecond - and that is the wall clock the operation waiting on a real
  // timer needs in order to elapse. Adding `Future.delayed` as well was measured
  // at roughly +45% on the whole suite for no change in outcome.
  await db.rawQuery('SELECT 1').timeout(databaseDrainTimeout);
}

/// Pumps and drains, over and over, until the database has nothing in flight.
///
/// **The exit condition is a count, not a duration.** A round is: a real turn
/// (so a `SendPort` reply can arrive, and so a real timer can elapse), then
/// frames (so the replies' `setState`s run, so a continuation parked on the fake
/// clock gets its turn, and so a `didUpdateWidget` can start a *further* read).
/// When a round ends with nothing in flight, the tree is settled **and** the
/// database is idle, which is the state a `testWidgets` body has to end in.
///
/// `inFlight == 0` is an exact statement rather than a proxy. sqflite serialises
/// every non-transactional call on one non-reentrant lock, so an operation that
/// has completed has certainly released it, and a counted operation covers a
/// whole transaction rather than its statements.
///
/// **Why it has to be a loop.** The helper this replaced was
/// `pumpAndSettle -> delay -> pumpAndSettle`, which ended one `pumpAndSettle`
/// after the read it had waited for - so anything *that* pump started was still
/// in flight when the body returned. Going Home is exactly that case: the bar
/// switch remounts `HomeScreen` and its `initState` reads the pack. Measured at
/// 6/8 runs of `back_navigation_test.dart` on its own, before this existed.
Future<void> _settleUntilIdle(WidgetTester tester) async {
  var quiet = 0;
  for (var round = 1; ; round++) {
    // A real turn and **one frame**, every round. Both are unconditional, and
    // that is measured rather than tidied: a variant that skipped the real turn
    // on a quiet round was 12% faster and failed 3 runs out of 3, because what
    // the second observation is looking for is a chain link that resumes on the
    // *real* event loop, not only on a fake-clock microtask.
    //
    // The frame rather than a settle is deliberate: a `pumpAndSettle` run while
    // a read is out meets HomeScreen's results-list `CircularProgressIndicator`,
    // which schedules frames forever and never returns - `golden_test.dart`'s
    // *word detail user shot* is the recorded instance of exactly that. One
    // frame is enough to run the `setState`s a completed read produced, and is
    // safe whatever is on screen.
    await tester.runAsync(drainDatabase);
    await tester.pump();

    if (_operations.inFlight > 0) {
      quiet = 0;
      _guardRoundBound(round);
      continue;
    }
    // Nothing is in flight, so the tree can now be settled: no read-driven
    // spinner can still be up, and `pumpAndSettle` will return.
    //
    // **And settling can start a read**, which is the whole defect. Measured on
    // this very shape with a deliberately slow database: `pumpShell` printed
    // `started=3` after draining and `started=4` one `pumpAndSettle` later -
    // Home's rebuild issued the favourites read for the word-of-the-day heart,
    // and the settle returned with it in flight. The helper this replaced ended
    // one `pumpAndSettle` after the read it had waited for, so whatever *that*
    // pump started was always still running. Going Home is the same case: the
    // bar switch remounts `HomeScreen` and its `initState` reads the pack.
    await tester.pumpAndSettle();
    if (_operations.inFlight > 0) {
      quiet = 0;
      _guardRoundBound(round);
      continue;
    }
    // Quiet, and still quiet after settling. **One quiet observation is not
    // enough**, and that is measured rather than argued:
    // `more_screen_test.dart`'s *exporting on a device with no file provider
    // says so and recovers* drives `VocabRepository.exportBackupJson`, a chain of
    // *sequential* reads. Between two of them there is an instant when the
    // counter reads zero, and a settle that returns there says "idle" while the
    // chain is still running - which is 2 runs out of 8 of that file passing,
    // measured, against 8 out of 8 once a second observation was required.
    quiet++;
    if (quiet >= 2) return;
    _guardRoundBound(round);
  }
}

/// Fails the test rather than returning quietly once the bound is reached.
///
/// A settle that gives up with work still in flight is the bug this whole change
/// exists to remove, so reaching the bound must be a red test and never a green
/// one.
void _guardRoundBound(int round) {
  if (round >= maxDatabaseSettleRounds) {
    fail('the database still had work in flight after '
        '$maxDatabaseSettleRounds settle rounds; a settle must never return '
        'with an operation running, because that operation holds sqflite\'s '
        'ten-second lock timer and flutter_test fails the test over it');
  }
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

/// Where Home's word-of-the-day card puts its four runs of text, as
/// fractions of the **card's** height.
///
/// **Measured off the rendered tree, not copied from a note.** On the golden
/// phone (1080×2340 at 3×) the card is 328×201 logical, and the four runs
/// land at:
///
/// | run | top | bottom |
/// |---|---|---|
/// | the "Word of the Day" label | `0.12438` | `0.21891` |
/// | the word | `0.25871` | `0.45771` |
/// | the phonetic | `0.45771` | `0.55721` |
/// | the "معرفة المعنى" button | `0.70647` | `0.80597` |
///
/// **They live here and not in a screen's test file because two files need
/// them and a copy is a copy.** `test/ui/wallpaper_legibility_test.dart`
/// samples the photographs over these bands, and `test/ui/home_screen_test.dart`
/// measures the rendered tree and asserts it against them, so a layout change
/// goes red in the place that owns the number rather than quietly leaving the
/// other place measuring a card that no longer exists.
///
/// **The card's fraction of height is the photograph's fraction of height**,
/// because the card shows the photograph's full height and crops 9.2% off each
/// side: the photograph is 1080×540 and the card is 328×201, so `BoxFit.cover`
/// scales it to 402×201 and cuts 37 logical pixels off each side.
const Map<String, List<double>> wordOfTheDayBands = <String, List<double>>{
  'label': <double>[0.12438, 0.21891],
  'word': <double>[0.25871, 0.45771],
  'phonetic': <double>[0.45771, 0.55721],
  'button': <double>[0.70647, 0.80597],
};

/// How long the shell's start-up query used to be given on the real event loop.
///
/// **Gone, and its removal is the point.** This was a fixed budget: long enough
/// for an in-memory `sqflite` FFI round trip on an idle machine, and a guess on
/// a busy one. `docs/engineering-standards.md` §5 recorded the symptom without
/// naming the cause - "the DB-settle wait was measured at 2 turns under load
/// against a 3-turn budget" - and every helper below used to be `this` many
/// milliseconds of `Future.delayed` on the real event loop. Now a settle waits on
/// [drainDatabase], which cannot return until the database says it is idle. It is
/// kept as a name rather than deleted outright only so this sentence has
/// something to point at.
@Deprecated('A settle waits for the database now; see drainDatabase.')
const Duration shellDatabaseSettle = Duration(milliseconds: 50);

/// Mounts `LexiLearnApp` on [repository] and waits for its start-up read to land.
///
/// A real turn of the event loop is **required**, not a nicety: a `testWidgets`
/// body runs inside a fake-async zone, and the shell resolves the active pack
/// from SQLite in `initState` over a `SendPort` to another isolate. `pump()`
/// cannot answer that - the reply is a real event, not a microtask - so without
/// the drain the shell sits there with an empty pack key and every assertion
/// about it fails for a reason that has nothing to do with the shell.
///
/// Shared rather than copied: Tasks 10, 13, 14 and 15 all reach their screens
/// through `HomeShell` and all hit this same trap.
///
/// **There are two sequential reads, and the rebuild between them is the whole
/// trick.** The shell's read fills in the active pack key. A destination that
/// needs the pack's *entries* cannot start reading until it has that key, and it
/// learns it in `didUpdateWidget`, which runs during a **rebuild** - not during
/// the shell's `setState`. So the second read has not even been *issued* when the
/// shell's read finishes, and a single drain would be waiting on a queue that
/// does not exist yet. Measured, not assumed: with the pair back to back,
/// `HomeScreen`'s card was missing from every dashboard test and its read landed
/// *after* the assertions had already failed.
///
/// **That is now the job of the settle's loop rather than of two hand-placed
/// waits.** Each round drains, pumps, and asks whether the pump started anything
/// new; a destination that grows a third sequential read costs one more round and
/// needs no edit here at all. `HomeScreen` used to carry its own extra
/// `runAsync` turn in each of the two test files that reach it, which is the two
/// copies §5 forbids, and Tasks 13, 14 and 15 would have added three more.
///
/// If a destination ever grows a read that a `pumpAndSettle` cannot outlast -
/// an indeterminate progress indicator - it needs [realTurnThenSettle] instead,
/// for the reason that helper gives.
Future<void> pumpShell(
  WidgetTester tester,
  VocabRepository repository, {
  int? wallpaperSeed,
  DictionaryController? dictionary,
}) async {
  // The link seam is the **recording** launcher, not the real one. `LexiLearnApp`
  // defaults to `url_launcher`, which has no implementation under `flutter_test`
  // — so without this every test that touched the overflow menu would throw a
  // `MissingPluginException` from a platform channel, which is §5's "no platform
  // at all" violation in a new place. A test asserts on [launchedLinks].
  await tester.pumpWidget(
    LexiLearnApp(
      repository: repository,
      openUrl: _recordNothingLaunched,
      // Null for every existing caller: the photograph is unseeded in every
      // test that is not photographing one.
      wallpaperSeed: wallpaperSeed,
      // **The dictionary, when the test has one.** The app's own controller is
      // an idle one, and a test that wants the dictionary's screens hands in
      // a controller that already has its engine.
      dictionary: dictionary,
    ),
  );
  // The shell's read, the destination's read, and anything either of them woke
  // up - until a round starts nothing new.
  await _settleUntilIdle(tester);
}

/// One real turn of the event loop, for a read that was **issued** rather than
/// awaited — a `FutureBuilder`, or a controller `start()` already in flight.
///
/// [pumpShell] is this once the loop has run. A destination or widget that mounts
/// its own read needs only this.
///
/// Same reason as `pumpShell`, and the same ten-minute timeout if it is skipped.
Future<void> settleDatabase(WidgetTester tester) => _settleUntilIdle(tester);

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
  // Kept as its own name, and its whole reason for existing still holds: the
  // database has to be given its turn **before** the first settle, because a
  // `pumpAndSettle` that runs while a read is out meets HomeScreen's
  // `CircularProgressIndicator`, which schedules frames forever.
  //
  // It no longer needs hand-placing that order, though. [_settleUntilIdle]
  // settles only on a round that began with nothing in flight, so the guarantee
  // is enforced by the loop rather than by where a wait was put - which is why
  // this and [settleDatabase] can share one implementation and why neither can
  // drift out of it.
  await _settleUntilIdle(tester);
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
  await _settleUntilIdle(tester);
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

/// The two providers a **stand-in** app must add when it mounts one screen
/// directly instead of the whole application.
///
/// `LexiLearnApp` installs `AppSettingsController` and `OpenExternalUrl` above
/// its `MaterialApp`, and every screen that carries the overflow menu reads
/// both. A stand-in that skips `LexiLearnApp` — `_MoreApp` in
/// `more_screen_test.dart`, the flashcard mount in `flashcards_screen_test.dart`,
/// and the Home mounts in three others — therefore has to supply them itself,
/// exactly as it already supplies `VocabRepository`.
///
/// **It is a loud failure by design, and that is the argument for it.** The menu
/// asks for its two seams with `read`/`watch`, not with a nullable lookup and a
/// silent fallback: a menu whose theme rows did nothing because no controller
/// was above it would be a screen that looks right and cannot be tested. Every
/// stand-in adding two lines is cheaper than that.
///
/// `ChangeNotifierProvider.value` and not `Provider.value` for the controller:
/// provider **asserts** against a `Listenable` in a plain `Provider` and names
/// `ChangeNotifierProvider` in the message. Measured on this SDK, not guessed.
List<SingleChildWidget> appSeamProviders({
  required AppSettingsController settings,
  OpenExternalUrl? openUrl,
  DictionaryController? dictionary,
}) =>
    <SingleChildWidget>[
      ChangeNotifierProvider<AppSettingsController>.value(value: settings),
      Provider<OpenExternalUrl>.value(value: openUrl ?? _recordNothingLaunched),
      // **The dictionary, the third seam.** `LexiLearnApp` installs it above
      // the `MaterialApp`, and `HomeScreen` reads it to know whether the
      // dictionary is ready and how far its copy has got. A stand-in that
      // skipped it would throw on the read, which is the same loud failure
      // the other two seams exist to prevent.
      //
      // An **idle** controller by default: no asset loader, no file system and
      // no database factory, so `start()` returns at once and nothing is
      // installed. A test that wants the dictionary passes one in.
      ChangeNotifierProvider<DictionaryController>.value(
        value: dictionary ?? DictionaryController.idle(),
      ),
    ];

/// A settings controller for a stand-in app, with a teardown that disposes it.
///
/// The load is fired and not awaited, for the reason the production controller's
/// doc gives: a `testWidgets` body is a fake-async zone and the row it reads has
/// to land on the real event loop, which is what `settleDatabase` is for.
AppSettingsController createAppSettings(VocabRepository repository) {
  final controller = AppSettingsController(repository: repository);
  addTearDown(controller.dispose);
  unawaited(controller.load());
  return controller;
}

/// The stand-in launcher: records the last link it was asked to open and answers
/// that nothing handled it, so a test can assert the `Uri` without a device.
///
/// A `static` rather than a closure so a test can read the capture back after
/// the widget that fired it has been disposed — `test/ui/app_settings_test.dart`
/// asserts on it, and a closure would have to be threaded through the stand-in
/// by hand for no gain.
final List<Uri> launchedLinks = <Uri>[];

Future<bool> _recordNothingLaunched(Uri url) async {
  launchedLinks.add(url);
  return false;
}

/// Clears [launchedLinks]. Call it from `setUp`, not from a test body: a test
/// body runs inside a fake-async zone where a `Future` is awkward, and a static
/// list surviving between tests is a test that passes for the wrong reason.
void clearLaunchedLinks() => launchedLinks.clear();

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
