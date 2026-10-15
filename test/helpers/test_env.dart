import 'dart:io';

import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A throwaway database plus a repository, for widget and DAO tests.
class TestHarness {
  TestHarness._(this.database, this.repository, this._directory);

  final Database database;
  final VocabRepository repository;
  final Directory _directory;

  static bool _initialised = false;
  static int _counter = 0;

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

    // A unique temp FILE, deliberately not `inMemoryDatabasePath`.
    //
    // `openAppDatabase` does not set `singleInstance: false`, and sqflite keys
    // its open-database helper by path with single-instance on by default
    // (sqflite_common/lib/src/factory_mixin.dart: `if (options?.singleInstance
    // != false)`). Two harnesses opened on `:memory:` in the same isolate
    // therefore share ONE database, and the second silently sees the first's
    // packs. That is invisible at creation time and corrupts any test needing
    // two independent states. Unique paths give real isolation.
    final directory = Directory.systemTemp.createTempSync('lexilearn_test_');
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'harness_${_counter++}.db'),
    );

    final repository = VocabRepository(
      database: db,
      clock: () => now ?? DateTime.utc(2026, 10, 14, 12),
    );
    for (final pack in packs) {
      await repository.importPack(PackCodec.encodePack(pack));
    }
    return TestHarness._(db, repository, directory);
  }

  Future<void> dispose() async {
    await repository.close();
    if (_directory.existsSync()) {
      _directory.deleteSync(recursive: true);
    }
  }
}