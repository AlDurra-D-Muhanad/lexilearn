// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

import 'package:lexilearn/domain/quiz_option.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

/// One question plus the options it was generated from.
///
/// Grading is identity-based: the selected index is resolved to a
/// [QuizOption] and compared by [VocabEntry.id]. No code path anywhere
/// compares, contains, or trims option text, because that is exactly how the
/// Python original accepted `e` for any answer containing an `e`.
@immutable
class QuizQuestion {
  const QuizQuestion({required this.answer, required this.options});

  final VocabEntry answer;
  final List<QuizOption> options;

  /// Never -1: the generator always includes the answer.
  int get correctIndex => options.indexWhere((option) => option.entryId == answer.id);

  /// An out-of-range selection is simply wrong; it never throws, because a tap
  /// that lands on a removed widget must not crash a session.
  bool isCorrect(int selectedIndex) {
    if (selectedIndex < 0 || selectedIndex >= options.length) return false;
    return options[selectedIndex].entryId == answer.id;
  }
}