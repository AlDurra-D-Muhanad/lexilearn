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