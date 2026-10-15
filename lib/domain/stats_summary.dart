// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

import 'package:lexilearn/domain/quiz_session_result.dart';

/// Everything the Stats screen renders, computed in one place.
@immutable
class StatsSummary {
  const StatsSummary({
    required this.totalAttempts,
    required this.totalCorrect,
    required this.wordsPracticed,
    required this.wordsMastered,
    required this.recentSessions,
  });

  static const StatsSummary empty = StatsSummary(
    totalAttempts: 0,
    totalCorrect: 0,
    wordsPracticed: 0,
    wordsMastered: 0,
    recentSessions: <QuizSessionResult>[],
  );

  final int totalAttempts;
  final int totalCorrect;
  final int wordsPracticed;
  final int wordsMastered;
  final List<QuizSessionResult> recentSessions;

  double get accuracy => totalAttempts == 0 ? 0 : totalCorrect / totalAttempts;

  bool get isEmpty => totalAttempts == 0;
}
