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
  /// another table can pass its `Transaction`. Left unset it runs on this
  /// DAO's own connection, which is what every ordinary call wants.
  Future<int> reset(String packKey, {DatabaseExecutor? executor}) =>
      (executor ?? _db).delete(
        'word_progress',
        where: 'pack_key = ?',
        whereArgs: <Object?>[packKey],
      );

  /// Writes an absolute value, used only by backup restore. Never increments.
  ///
  /// [executor] is NOT optional-by-omission here: `importBackupJson` calls this
  /// inside a transaction, and a `replace` that opens its own connection while
  /// that transaction holds the write lock **hangs forever** — no exception, no
  /// log line, no timeout you wrote. See `docs/engineering-standards.md` §3.
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
