import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/word_progress.dart';

void main() {
  WordProgress fresh() => const WordProgress(entryId: 'a', packKey: 'p');

  test('a word with no attempts has zero accuracy and is not mastered', () {
    expect(fresh().accuracy, 0);
    expect(fresh().isMastered, isFalse);
  });

  test('recording a correct answer increments attempts and correct', () {
    final at = DateTime.utc(2026, 10, 14);
    final updated = fresh().recordAnswer(wasCorrect: true, at: at);

    expect(updated.attempts, 1);
    expect(updated.correct, 1);
    expect(updated.accuracy, 1);
    expect(updated.lastSeenAt, at);
  });

  test('recording a wrong answer increments attempts only', () {
    final updated = fresh().recordAnswer(
        wasCorrect: false, at: DateTime.utc(2026, 10, 14));
    expect(updated.attempts, 1);
    expect(updated.correct, 0);
  });

  test('is not mastered below the attempt floor', () {
    var progress = fresh();
    for (var i = 0; i < 4; i++) {
      progress = progress.recordAnswer(
          wasCorrect: true, at: DateTime.utc(2026, 10, 14));
    }
    expect(progress.attempts, 4);
    expect(progress.isMastered, isFalse);
  });

  test('is mastered at the attempt floor with full accuracy', () {
    var progress = fresh();
    for (var i = 0; i < 5; i++) {
      progress = progress.recordAnswer(
          wasCorrect: true, at: DateTime.utc(2026, 10, 14));
    }
    expect(progress.isMastered, isTrue);
  });

  test('many attempts at poor accuracy is not mastery', () {
    var progress = fresh();
    for (var i = 0; i < 20; i++) {
      progress = progress.recordAnswer(
          wasCorrect: i % 5 == 0, at: DateTime.utc(2026, 10, 14));
    }
    expect(progress.attempts, 20);
    expect(progress.isMastered, isFalse);
  });
}
