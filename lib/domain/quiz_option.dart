// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// One selectable answer. Correctness is decided by `entryId` identity, which
/// is what makes the original substring-grading bug impossible to reintroduce.
@immutable
class QuizOption {
  const QuizOption({required this.entryId, required this.text});

  final String entryId;
  final String text;
}