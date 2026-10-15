// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// One finished quiz. Persisted so Stats has a history and so a future backup
/// can carry it.
@immutable
class QuizSessionResult {
  const QuizSessionResult({
    required this.packKey,
    required this.startedAt,
    required this.totalQuestions,
    required this.correctCount,
  });

  final String packKey;
  final DateTime startedAt;
  final int totalQuestions;
  final int correctCount;

  double get accuracy => totalQuestions == 0 ? 0 : correctCount / totalQuestions;
}
