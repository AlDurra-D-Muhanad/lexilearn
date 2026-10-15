import 'package:lexilearn/domain/word_progress.dart';
import 'package:sqflite/sqflite.dart';

class ProgressDao {
  const ProgressDao(this._db);

  final Database _db;

  /// Upsert in a single statement so a killed app can never leave attempts and
  /// correct counts out of step with each other.
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

  Future<int> reset(String packKey) => _db.delete(
        'word_progress',
        where: 'pack_key = ?',
        whereArgs: <Object?>[packKey],
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
