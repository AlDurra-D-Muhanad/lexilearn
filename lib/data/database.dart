import 'package:sqflite/sqflite.dart';

/// v1. Every future migration adds a branch to [_onUpgrade] and bumps this.
///
/// `favorites` is part of this v1, not a v2. It ships in the first release, so
/// nothing anywhere has ever opened a v1 database that lacked the table and
/// there is no install a migration could be written for. The first schema change
/// *after* a release is the thing that bumps this — and that release is also the
/// first time `if (from < 2)` in [_onUpgrade] becomes reachable.
const int databaseSchemaVersion = 1;

/// Opens the app database, creating or migrating the schema as needed.
///
/// [singleInstance] defaults to `true`, which is right for the app: it opens one
/// database, once, and holds it for the process lifetime.
///
/// It must be `false` for any caller that wants two genuinely independent
/// databases at the same path. sqflite caches its open-database helper by path
/// whenever single-instance is on, so a second `openDatabase` of the same path
/// returns the *first* connection rather than a new one — including for
/// `:memory:`, where two callers would silently share one database. The test
/// harness needs an independent database per `TestHarness`, so it passes
/// `false`; nothing in `lib/` does.
Future<Database> openAppDatabase({
  required DatabaseFactory factory,
  String path = 'lexilearn.db',
  bool singleInstance = true,
}) {
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: databaseSchemaVersion,
      singleInstance: singleInstance,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    ),
  );
}

Future<void> _onConfigure(Database db) async {
  // SQLite ships with foreign keys OFF by default and sqflite does not change
  // that. Without this, deleting a pack would leave orphaned entries.
  await db.execute('PRAGMA foreign_keys = ON');
}

Future<void> _onCreate(Database db, int version) async {
  final batch = db.batch();
  batch.execute('''
    CREATE TABLE packs (
      pack_key         TEXT PRIMARY KEY,
      title            TEXT NOT NULL,
      source_language  TEXT NOT NULL,
      target_language  TEXT NOT NULL,
      schema_version   INTEGER NOT NULL,
      entry_count      INTEGER NOT NULL,
      is_bundled       INTEGER NOT NULL DEFAULT 0,
      imported_at      TEXT NOT NULL
    )
  ''');
  batch.execute('''
    CREATE TABLE entries (
      entry_id     TEXT NOT NULL,
      pack_key     TEXT NOT NULL,
      term         TEXT NOT NULL,
      translations TEXT NOT NULL,
      note         TEXT NOT NULL DEFAULT '',
      phonetic     TEXT NOT NULL DEFAULT '',
      part_of_speech TEXT NOT NULL DEFAULT '',
      synonyms     TEXT NOT NULL DEFAULT '[]',
      examples     TEXT NOT NULL DEFAULT '[]',
      sort_index   INTEGER NOT NULL,
      PRIMARY KEY (pack_key, entry_id),
      FOREIGN KEY (pack_key) REFERENCES packs (pack_key) ON DELETE CASCADE
    )
  ''');
  batch.execute(
      'CREATE INDEX idx_entries_pack ON entries (pack_key, sort_index)');
  // No foreign key to `entries` on purpose: re-importing a pack replaces its
  // rows, and the progress recorded against deterministic ids must survive.
  batch.execute('''
    CREATE TABLE word_progress (
      entry_id     TEXT NOT NULL,
      pack_key     TEXT NOT NULL,
      attempts     INTEGER NOT NULL DEFAULT 0,
      correct_count INTEGER NOT NULL DEFAULT 0,
      last_seen_at TEXT,
      PRIMARY KEY (pack_key, entry_id)
    )
  ''');
  batch.execute('''
    CREATE TABLE quiz_sessions (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      pack_key        TEXT NOT NULL,
      started_at      TEXT NOT NULL,
      total_questions INTEGER NOT NULL,
      correct_count   INTEGER NOT NULL
    )
  ''');
  batch.execute(
      'CREATE INDEX idx_sessions_started ON quiz_sessions (started_at DESC)');
  // Favourites: one row per saved word, scoped to the pack it was saved from.
  //
  // **No foreign key to `entries`, on the same grounds as `word_progress` above:**
  // a pack re-import replaces its entry rows, and re-favouriting every word
  // afterwards would be a decision the user never made. The key onto `packs` is
  // the other way round and is what makes deleting a pack take its favourites
  // with it — [_onConfigure] already runs `PRAGMA foreign_keys = ON`, so the
  // cascade needs nothing here.
  //
  // **What the cascade destroys, and where that stopped being a bug.** Deleting a
  // pack deletes the words the user saved from it. That is right when the user
  // deletes a pack. It was **data loss** when `importBackupJson` deleted every
  // `packs` row inside its transaction to restore a backup — the user's whole
  // curated list went with it, silently, because `BackupDocument` carried only
  // packs, progress and sessions. The cascade is unchanged; `BackupDocument` now
  // carries `favorites` and the restore writes them back in the same
  // transaction. Pinned by `test/data/vocab_repository_test.dart` →
  // *a backup carries the user's favourites, and restores them*.
  //
  // Pinned by `test/data/favorite_dao_test.dart` → *favourites are removed when
  // the pack is deleted*, **and that test is itself a guard on the pragma above.**
  // It was once documented as passing with foreign keys off, on the reasoning
  // that no favourite would be found either. Measured, that is backwards: with
  // the pragma off the row survives the delete and `favoritesIn('p')` still
  // returns `{a}`, so the test **fails** — which is what makes it load-bearing.
  batch.execute('''
    CREATE TABLE favorites (
      pack_key  TEXT NOT NULL,
      entry_id  TEXT NOT NULL,
      added_at  TEXT NOT NULL,
      PRIMARY KEY (pack_key, entry_id),
      FOREIGN KEY (pack_key) REFERENCES packs (pack_key) ON DELETE CASCADE
    )
  ''');
  await batch.commit(noResult: true);
}

Future<void> _onUpgrade(Database db, int from, int to) async {
  // v1 is the first shipped schema, so there is nothing to migrate yet.
  // Future revisions append `if (from < 2) { ... }` blocks here.
}
