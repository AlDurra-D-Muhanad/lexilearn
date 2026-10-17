import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:sqflite/sqflite.dart';

class SessionDao {
  const SessionDao(this._db);

  final Database _db;

  /// [executor] joins a caller's transaction. `importBackupJson` restores the
  /// whole session history through here, and a call made without the
  /// transaction's handle does not fail — it **waits**, on the Dart-side
  /// `_rawLock` `transaction()` holds for its whole body
  /// (`sqflite_common-2.5.14/lib/src/database_mixin.dart:496`, taken at `:894`
  /// and waited on at `:549-592`) and on the FFI layer's queue behind it
  /// (`sqflite_common_ffi-2.4.4/lib/src/sqflite_ffi_impl.dart:275-315`). Same
  /// `Database` object, not a second connection. See
  /// `docs/engineering-standards.md` §3.
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
  /// another table can pass its `Transaction`. Left unset it runs on this DAO's
  /// own `Database` handle — the same object, not a second connection — which is
  /// what every ordinary call wants.
  Future<int> deleteForPack(String packKey, {DatabaseExecutor? executor}) =>
      (executor ?? _db).delete(
        'quiz_sessions',
        where: 'pack_key = ?',
        whereArgs: <Object?>[packKey],
      );
}
