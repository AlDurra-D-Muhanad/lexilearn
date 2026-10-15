// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Per-word history. Keyed by `(packKey, entryId)` so two packs can hold the
/// same term without sharing progress.
@immutable
class WordProgress {
  const WordProgress({
    required this.entryId,
    required this.packKey,
    this.attempts = 0,
    this.correct = 0,
    this.lastSeenAt,
  });

  final String entryId;
  final String packKey;
  final int attempts;
  final int correct;
  final DateTime? lastSeenAt;

  /// A word is "mastered" once it has been seen enough times, and been answered
  /// correctly often enough. Both thresholds are constants, not settings: an
  /// offline app has nowhere sensible to put a settings screen yet.
  static const int masteryAttemptFloor = 5;
  static const double masteryAccuracyFloor = 0.8;

  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  bool get isMastered =>
      attempts >= masteryAttemptFloor && accuracy >= masteryAccuracyFloor;

  WordProgress recordAnswer({required bool wasCorrect, required DateTime at}) =>
      WordProgress(
        entryId: entryId,
        packKey: packKey,
        attempts: attempts + 1,
        correct: wasCorrect ? correct + 1 : correct,
        lastSeenAt: at,
      );
}
