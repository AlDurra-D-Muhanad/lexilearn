import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:sqflite/sqflite.dart';

class SessionDao {
  const SessionDao(this._db);

  final Database _db;

  Future<int> insert(QuizSessionResult result) => _db.insert('quiz_sessions', <String, Object?>{
        'pack_key': result.packKey,
        'started_at': result.startedAt.toUtc().toIso8601String(),
        'total_questions': result.totalQuestions,
        'correct_count': result.correctCount,
      });

  Future<List<QuizSessionResult>> recent({int limit = 10}) async {
    final rows = await _db.query('quiz_sessions',
        orderBy: 'started_at DESC, id DESC', limit: limit);
    return rows
        .map((row) => QuizSessionResult(
              packKey: row['pack_key']! as String,
              startedAt: DateTime.parse(row['started_at']! as String),
              totalQuestions: (row['total_questions']! as num).toInt(),
              correctCount: (row['correct_count']! as num).toInt(),
            ))
        .toList();
  }
}
