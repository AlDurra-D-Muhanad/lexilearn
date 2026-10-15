import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/app.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An in-memory database plus a repository, for widget and DAO tests.
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
Future<void> pumpShell(WidgetTester tester, VocabRepository repository) async {
  await tester.pumpWidget(LexiLearnApp(repository: repository));
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}