import 'package:lexilearn/domain/word_progress.dart';
import 'package:sqflite/sqflite.dart';

class ProgressDao {
  const ProgressDao(this._db);

  final Database _db;

  /// Upsert in a single statement so a killed app can never leave attempts and
  /// correct counts out of step with each other.
  ///
  /// Pinned by `progress_dao_test.dart :: concurrent records never lose an
  /// attempt`. Rewritten as read-then-write, twenty concurrent calls leave
  /// `attempts` at 1 instead of 20 while every other test still passes — so
  /// this is a claim worth keeping and worth a test.
  Future<void> record({
    required String packKey,
    required String entryId,
    required bool wasCorrect,
    required DateTime at,
  }) async {
    await _db.rawInsert(
      '''
      INSERT INTO word_progress (entry_id, pack_key, attempts, correct_count, last_seen_at)
      VALUES (?, ?, 1, ?, ?)
      ON CONFLICT(pack_key, entry_id) DO UPDATE SET
        attempts = attempts + 1,
        correct_count = correct_count + excluded.correct_count,
        last_seen_at = excluded.last_seen_at
      ''',
      <Object?>[
        entryId,
        packKey,
        wasCorrect ? 1 : 0,
        at.toUtc().toIso8601String(),
      ],
    );
  }

  Future<WordProgress?> get({required String packKey, required String entryId}) async {
    final rows = await _db.query(
      'word_progress',
      where: 'pack_key = ? AND entry_id = ?',
      whereArgs: <Object?>[packKey, entryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<List<WordProgress>> allForPack(String packKey) async {
    final rows = await _db.query('word_progress',
        where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
    return rows.map(_fromRow).toList();
  }

  /// Deletes one pack's progress, returning how many rows went.
  ///
  /// [executor] exists so a caller that must delete atomically alongside
  /// another table can pass its `Transaction`. Left unset it runs on this DAO's
  /// own `Database` handle — the same object, not a second connection — which is
  /// what every ordinary call wants.
  Future<int> reset(String packKey, {DatabaseExecutor? executor}) =>
      (executor ?? _db).delete(
        'word_progress',
        where: 'pack_key = ?',
        whereArgs: <Object?>[packKey],
      );

  /// Deletes the progress rows of named entries in one pack, returning how many
  /// rows went.
  ///
  /// **For one pack's own words, and no others.** The derived "My Favourites"
  /// pack holds no rows of its own — every answer about one of its words is
  /// filed in the pack the word came from — so clearing *its* progress means
  /// clearing the rows of its words, in the packs they belong to, and nothing
  /// else. `reset` would clear the whole source pack, including words the
  /// user has not saved, which is not what was asked for.
  ///
  /// **In chunks, because a bound-variable list has a limit.** SQLite refuses
  /// a statement with more than 999 bound variables, and a user who has saved
  /// a thousand words asks for exactly that. The chunks are deleted through
  /// the caller's handle, so the whole reset is still one transaction.
  ///
  /// [executor] exists for the same reason [reset] has one: a caller that
  /// must delete atomically alongside another table can pass its
  /// `Transaction`. Left unset it runs on this DAO's own `Database` handle —
  /// the same object, not a second connection — which is what every ordinary
  /// call wants. A call made *inside* a transaction without the handle does
  /// not fail: it **waits**. See `docs/engineering-standards.md` §3.
  Future<int> resetEntries(
    String packKey,
    Set<String> entryIds, {
    DatabaseExecutor? executor,
  }) async {
    if (entryIds.isEmpty) return 0;
    final handle = executor ?? _db;
    final ids = entryIds.toList();
    var cleared = 0;
    for (var start = 0; start < ids.length; start += _resetChunkSize) {
      final end = start + _resetChunkSize < ids.length
          ? start + _resetChunkSize
          : ids.length;
      final chunk = ids.sublist(start, end);
      final placeholders = List<String>.filled(chunk.length, '?').join(', ');
      cleared += await handle.delete(
        'word_progress',
        where: 'pack_key = ? AND entry_id IN ($placeholders)',
        whereArgs: <Object?>[packKey, ...chunk],
      );
    }
    return cleared;
  }

  /// How many entry ids go into one `IN (...)` clause.
  ///
  /// **Small enough for the oldest SQLite this app runs against**, which
  /// refuses a statement with more than 999 bound variables — and the pack key
  /// takes one of them.
  static const int _resetChunkSize = 500;

  /// Writes an absolute value, used only by backup restore. Never increments.
  ///
  /// [executor] is NOT optional-by-omission here: `importBackupJson` calls this
  /// inside a transaction, and a `replace` made without the transaction's handle
  /// does not fail — it **waits**, on the Dart-side `_rawLock` that
  /// `transaction()` holds for its whole body
  /// (`sqflite_common-2.5.14/lib/src/database_mixin.dart:496`, taken at `:894`
  /// and waited on at `:549-592`) and on the FFI layer's queue behind it
  /// (`sqflite_common_ffi-2.4.4/lib/src/sqflite_ffi_impl.dart:275-315`). Same
  /// `Database` object, no second connection, and nothing to do with a SQLite
  /// file lock — `:423` opens `BEGIN IMMEDIATE`. See
  /// `docs/engineering-standards.md` §3.
  Future<void> replace(WordProgress progress, {DatabaseExecutor? executor}) =>
      (executor ?? _db).insert(
        'word_progress',
        <String, Object?>{
          'entry_id': progress.entryId,
          'pack_key': progress.packKey,
          'attempts': progress.attempts,
          'correct_count': progress.correct,
          'last_seen_at': progress.lastSeenAt?.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  WordProgress _fromRow(Map<String, Object?> row) => WordProgress(
        entryId: row['entry_id']! as String,
        packKey: row['pack_key']! as String,
        attempts: (row['attempts']! as num).toInt(),
        correct: (row['correct_count']! as num).toInt(),
        lastSeenAt: row['last_seen_at'] == null
            ? null
            : DateTime.parse(row['last_seen_at']! as String),
      );
}
