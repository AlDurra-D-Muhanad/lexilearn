import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:sqflite/sqflite.dart';

class SessionDao {
  const SessionDao(this._db);

  final Database _db;

  /// [executor] joins a caller's transaction. `importBackupJson` restores the
  /// whole session history through here while holding the write lock, and a
  /// call on this DAO's own connection in that state does not fail — it hangs
  /// forever. See `docs/engineering-standards.md` §3.
  Future<int> insert(QuizSessionResult result, {DatabaseExecutor? executor}) =>
      (executor ?? _db).insert('quiz_sessions', <String, Object?>{
        'pack_key': result.packKey,
        'started_at': result.startedAt.toUtc().toIso8601String(),
        'total_questions': result.totalQuestions,
        'correct_count': result.correctCount,
      });

  /// Most recent sessions, newest first.
  ///
  /// [packKey] filters to one pack. It is optional and `null` means "every
  /// pack": a backup legitimately carries the whole session history, while the
  /// Stats screen must only ever show sessions from the pack it is displaying.
  Future<List<QuizSessionResult>> recent({
    int limit = 10,
    String? packKey,
  }) async {
    final rows = await _db.query(
      'quiz_sessions',
      where: packKey == null ? null : 'pack_key = ?',
      whereArgs: packKey == null ? null : <Object?>[packKey],
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
    );
    return rows
        .map((row) => QuizSessionResult(
              packKey: row['pack_key']! as String,
              startedAt: DateTime.parse(row['started_at']! as String),
              totalQuestions: (row['total_questions']! as num).toInt(),
              correctCount: (row['correct_count']! as num).toInt(),
            ))
        .toList();
  }

  /// Removes one pack's session history, returning how many rows went. Used by
  /// a progress reset, and by a pack deletion.
  ///
  /// [executor] exists so a caller that must delete atomically alongside
  /// another table can pass its `Transaction`. Left unset it runs on this
  /// DAO's own connection, which is what every ordinary call wants.
  Future<int> deleteForPack(String packKey, {DatabaseExecutor? executor}) =>
      (executor ?? _db).delete(
        'quiz_sessions',
        where: 'pack_key = ?',
        whereArgs: <Object?>[packKey],
      );
}
