import 'dart:convert';

import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite/sqflite.dart';

/// Lightweight row used by the pack list screen.
class PackSummary {
  const PackSummary({
    required this.packKey,
    required this.title,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.entryCount,
    required this.isBundled,
    required this.importedAt,
  });

  final String packKey;
  final String title;
  final String sourceLanguage;
  final String targetLanguage;
  final int entryCount;
  final bool isBundled;
  final DateTime importedAt;
}

class PackDao {
  const PackDao(this._db);

  final Database _db;

  /// Runs [action] atomically on [executor] when one was handed in, and on this
  /// DAO's own `Database` handle otherwise.
  ///
  /// "Handle", not "connection": it is the **same `Database` object** either way,
  /// which is the whole correction in `docs/engineering-standards.md` §3. Calling
  /// it a connection is what produced the first, wrong version of that rule.
  ///
  /// **The two cases are not interchangeable, and the reason is in the type.**
  /// `transaction` is a member of `Database`, **not** of `DatabaseExecutor` —
  /// `sqflite_common-2.5.14/lib/sqlite_api.dart` declares
  /// `abstract class Transaction implements DatabaseExecutor {}`, which adds
  /// nothing of its own, and puts `transaction` on `Database` alone. A
  /// `Transaction` is therefore already inside a transaction and must not be
  /// wrapped in another: its atomicity *is* the caller's atomicity, and
  /// `write(txn)` simply joins it.
  ///
  /// **Before Task 13 this DAO had no `executor` parameter on any method and
  /// held `_db` privately**, so `importBackupJson` could not tell it to join the
  /// transaction it had opened. Every call it made inside that transaction went
  /// in without the handle, and that does not fail — it **waits**, on the
  /// Dart-side `_rawLock` that `transaction()` holds for its whole body
  /// (`sqflite_common-2.5.14/lib/src/database_mixin.dart:496`, taken at `:894`
  /// and waited on at `:549-592`), and on the FFI layer's queue behind it
  /// (`sqflite_common_ffi-2.4.4/lib/src/sqflite_ffi_impl.dart:275-315`).
  /// `docs/engineering-standards.md` §3; the guard-timeout test in
  /// `test/data/vocab_repository_test.dart` is what makes a regression visible.
  Future<T> _atomic<T>(
    DatabaseExecutor? executor,
    Future<T> Function(Transaction txn) action,
  ) {
    if (executor is Transaction) return action(executor);
    final Database database = executor == null ? _db : executor as Database;
    return database.transaction(action);
  }

  /// Replaces the pack and all of its entries atomically. Progress rows are
  /// keyed on deterministic entry ids and are intentionally left untouched.
  ///
  /// **The pack's own row is written by [_writePackRow], never by a replace.**
  /// See that method for why a replace here is data loss.
  ///
  /// [executor] joins a caller's transaction; see [_atomic].
  Future<void> insertPack(
    VocabPack pack, {
    required bool isBundled,
    required DateTime importedAt,
    DatabaseExecutor? executor,
  }) async {
    await _atomic(executor, (txn) async {
      await _writePackRow(txn, <String, Object?>{
        'pack_key': pack.packId,
        'title': pack.title,
        'source_language': pack.sourceLanguage,
        'target_language': pack.targetLanguage,
        'schema_version': pack.schemaVersion,
        'entry_count': pack.entryCount,
        'is_bundled': isBundled ? 1 : 0,
        'imported_at': importedAt.toUtc().toIso8601String(),
      });
      // **The pack's old entries are removed here, and not by a cascade.**
      //
      // They used to be removed because the pack's row was *deleted* and
      // `entries.pack_key` cascades from `packs`. That delete also took the
      // pack's **favourites** with it, which is the fatal defect
      // `[_writePackRow]` exists to prevent — so the removal has to be
      // explicit now, or a re-import would leave the pack's old words in the
      // table and the pack would hold words it no longer has.
      //
      // `word_progress` and `favorites` have **no** foreign key onto `entries`
      // (`lib/data/database.dart` says so on purpose), so this delete touches
      // neither of them.
      await txn.delete('entries',
          where: 'pack_key = ?', whereArgs: <Object?>[pack.packId]);
      final batch = txn.batch();
      for (var index = 0; index < pack.entries.length; index++) {
        final entry = pack.entries[index];
        batch.insert(
          'entries',
          <String, Object?>{
            'entry_id': entry.id,
            'pack_key': pack.packId,
            'term': entry.term,
            'translations': jsonEncode(entry.translations),
            'note': entry.note,
            'phonetic': entry.phonetic,
            'part_of_speech': entry.partOfSpeech,
            // jsonEncode of an empty list is "[]", so these columns are never
            // null and the read side never has to special-case a missing list.
            'synonyms': jsonEncode(entry.synonyms),
            'examples': jsonEncode(entry.examples),
            'sort_index': index,
          },
          // **Safe here, and the reason is the direction of the foreign key.**
          // `entries.pack_key` cascades *from* `packs`, so a replace of an
          // entry row cannot fire it — a cascade only runs when a **parent**
          // row is deleted, and this one is a child. And nothing cascades
          // *from* `entries`: `word_progress` and `favorites` carry no
          // foreign key onto it at all (`lib/data/database.dart` records both
          // decisions on purpose). So replacing an entry row destroys that one
          // row and nothing else, which is what this insert means.
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Writes the pack's own row **without ever deleting it**.
  ///
  /// ## Why this is not `ConflictAlgorithm.replace`
  ///
  /// **`INSERT OR REPLACE` is a DELETE followed by an INSERT**, and the DELETE
  /// fires `favorites.pack_key`'s `ON DELETE CASCADE`. Every favourite filed
  /// under this pack key therefore disappeared the moment the pack's row was
  /// rewritten — and the pack's row **is** rewritten on every launch:
  /// `VocabRepository.ensureDictionaryPack` writes the dictionary's row through
  /// this method, and `main()` calls it on every start. So every time the user
  /// left the app and came back, the favourites were gone.
  ///
  /// That is the user's own report: «كلما اخرج من التطبيق تمسح حزمة المفضلة
  /// كليا» — every time I leave the app, the favourites pack is wiped entirely.
  ///
  /// ## What this does instead
  ///
  /// **An insert that is ignored when the row is already there, then an
  /// update.** `INSERT OR IGNORE` (`ConflictAlgorithm.ignore`) leaves an
  /// existing row exactly as it is — it does not delete it and it does not
  /// cascade — and reports `0` changed rows, which is the signal that the row
  /// is already there. The update then rewrites the row's columns **in place**,
  /// which no cascade can see.
  ///
  /// **Why not `INSERT ... ON CONFLICT DO UPDATE`.** It is the tidier
  /// statement, but UPSERT needs SQLite 3.24 (2018) and sqflite runs against
  /// the **system** SQLite on Android, which is older than that on Android 8
  /// and 9. The insert-then-update pair runs on every SQLite there is.
  ///
  /// **And not "update, and insert when the update changed no row."** That
  /// turns on whether SQLite counts a row whose columns already hold the values
  /// being written, which is a detail of the engine rather than of the schema.
  /// This pair does not depend on it: `INSERT OR IGNORE` distinguishes "the row
  /// is there" from "it is not" on its own.
  Future<void> _writePackRow(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    final inserted = await executor.insert(
      'packs',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    await executor.update(
      'packs',
      row,
      where: 'pack_key = ?',
      whereArgs: <Object?>[row['pack_key']],
    );
  }

  /// Inserts or replaces the pack's own row, with **no entries**.
  ///
  /// **A separate method, and not `insertPack` with an empty list.** The
  /// dictionary is a pack whose words live in a read-only file of their own
  /// and not in this table — it is reference data, and a backup must never
  /// carry 25 MB of it. So it needs a row (the `favorites` table's foreign key
  /// points at `packs(pack_key)`) and no entries.
  ///
  /// The row carries the dictionary's **real** size, so the pack list can say
  /// how many words there are without reading them.
  ///
  /// **The row is written by [_writePackRow], and that is the whole point of
  /// this method.** It is called on **every launch** — `main()` calls
  /// `VocabRepository.ensureDictionaryPack`, which calls this — so whatever it
  /// does to the row happens every time the user opens the app. Writing it
  /// with `ConflictAlgorithm.replace` deleted it, and the delete took the
  /// dictionary's **favourites** with it through `favorites.pack_key`'s
  /// `ON DELETE CASCADE`: the user's own saved words, wiped on every start.
  /// The user's report, verbatim: «كلما اخرج من التطبيق تمسح حزمة المفضلة
  /// كليا».
  Future<void> insertPackRow(
    PackSummary summary, {
    DatabaseExecutor? executor,
  }) async {
    await _writePackRow(
      executor ?? _db,
      <String, Object?>{
        'pack_key': summary.packKey,
        'title': summary.title,
        'source_language': summary.sourceLanguage,
        'target_language': summary.targetLanguage,
        'schema_version': VocabPack.currentSchemaVersion,
        'entry_count': summary.entryCount,
        'is_bundled': summary.isBundled ? 1 : 0,
        'imported_at': summary.importedAt.toUtc().toIso8601String(),
      },
    );
  }

  /// The pack's own row, or null.
  Future<PackSummary?> packRow(String packKey) async {
    final rows = await _db.query(
      'packs',
      where: 'pack_key = ?',
      whereArgs: <Object?>[packKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PackSummary(
      packKey: row['pack_key']! as String,
      title: row['title']! as String,
      sourceLanguage: row['source_language']! as String,
      targetLanguage: row['target_language']! as String,
      entryCount: (row['entry_count']! as num).toInt(),
      isBundled: (row['is_bundled']! as num).toInt() == 1,
      importedAt: DateTime.parse(row['imported_at']! as String),
    );
  }

  /// Cascades to `entries`. Also removes this pack's progress and sessions so
  /// Stats cannot read rows for a pack that no longer exists.
  ///
  /// [executor] joins a caller's transaction; see [_atomic]. `importBackupJson`
  /// deletes through here while restoring, and a call without the handle would
  /// wait rather than fail.
  Future<void> deletePack(String packKey, {DatabaseExecutor? executor}) async {
    await _atomic(executor, (txn) async {
      await txn.delete('word_progress',
          where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
      await txn.delete('quiz_sessions',
          where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
      await txn.delete('packs', where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
    });
  }

  /// [executor] joins a caller's transaction; see [_atomic]. `importBackupJson`
  /// reads through here *inside* the transaction it opened, because the packs it
  /// is about to delete have to be the packs as they are right now.
  Future<List<PackSummary>> listPacks({DatabaseExecutor? executor}) async {
    final rows = await (executor ?? _db).query('packs',
        orderBy: 'is_bundled DESC, imported_at DESC');
    return rows
        .map((row) => PackSummary(
              packKey: row['pack_key']! as String,
              title: row['title']! as String,
              sourceLanguage: row['source_language']! as String,
              targetLanguage: row['target_language']! as String,
              entryCount: (row['entry_count']! as num).toInt(),
              isBundled: (row['is_bundled']! as num).toInt() == 1,
              importedAt: DateTime.parse(row['imported_at']! as String),
            ))
        .toList();
  }

  /// **An explicit decision, not an oversight.** This departs from the letter of
  /// `docs/engineering-standards.md` §3, which asks that *every* DAO reachable
  /// from a transaction take an executor. The departure is recorded here so a
  /// reviewer reads "chosen" rather than "missed", and so the next caller who
  /// needs them inside a transaction knows to add them then.
  ///
  /// The reason is narrow: these three are single-statement reads, and **no
  /// caller reaches them from inside a transaction.** `exportBackupJson` walks
  /// them *before* it opens one, and nothing else in `lib/` passes a
  /// `Transaction` to this DAO — checked by reading every call site, not by
  /// assuming. Adding an unused parameter would be untested surface pretending
  /// to be a guarantee, and a guarantee nobody exercises is the thing §3 is
  /// about. If a future caller needs them inside a transaction, that caller is
  /// the moment to add it.
  Future<VocabPack?> getPack(String packKey) async {
    final rows = await _db.query('packs',
        where: 'pack_key = ?', whereArgs: <Object?>[packKey], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final entries = await entriesOf(packKey);
    return VocabPack(
      schemaVersion: (row['schema_version']! as num).toInt(),
      packId: row['pack_key']! as String,
      title: row['title']! as String,
      sourceLanguage: row['source_language']! as String,
      targetLanguage: row['target_language']! as String,
      entries: entries,
    );
  }

  Future<List<VocabEntry>> entriesOf(String packKey) async {
    final rows = await _db.query('entries',
        where: 'pack_key = ?', whereArgs: <Object?>[packKey], orderBy: 'sort_index ASC');
    return rows
        .map((row) => VocabEntry(
              id: row['entry_id']! as String,
              term: row['term']! as String,
              translations: (jsonDecode(row['translations']! as String) as List<dynamic>)
                  .cast<String>(),
              note: (row['note'] as String?) ?? '',
              phonetic: (row['phonetic'] as String?) ?? '',
              partOfSpeech: (row['part_of_speech'] as String?) ?? '',
              synonyms: _decodeStringList(row['synonyms']),
              examples: _decodeStringList(row['examples']),
            ))
        .toList();
  }

  Future<int> countEntries(String packKey) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM entries WHERE pack_key = ?',
      <Object?>[packKey],
    );
    return (rows.first['c']! as num).toInt();
  }
}

/// Reads a JSON-encoded string column. `"[]"` decodes to an empty list, and a
/// null or malformed column degrades to empty rather than crashing the read
/// path, which is the same tolerance `VocabEntry.fromJson` applies.
List<String> _decodeStringList(Object? column) => column is String
    ? (jsonDecode(column) as List<dynamic>).cast<String>()
    : const <String>[];
