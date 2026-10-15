import 'dart:math';

import 'package:lexilearn/domain/quiz_option.dart';
import 'package:lexilearn/domain/quiz_question.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

class QuizGenerator {
  QuizGenerator({required List<VocabEntry> entries, Random? random})
      : _entries = List<VocabEntry>.unmodifiable(entries),
        _random = random ?? Random();

  /// The Python original always drew four options with `random.choice`, which
  /// could repeat the same word twice. Sampling without replacement can only
  /// reach `min(4, poolSize)` options.
  static const int desiredOptionCount = 4;

  final List<VocabEntry> _entries;
  final Random _random;
  final Set<String> _askedIds = <String>{};

  int get poolSize => _entries.length;
  bool get canGenerate => _entries.isNotEmpty;

  QuizQuestion? next() {
    if (_entries.isEmpty) return null;
    final answer = _pickNextEntry();
    final optionCount =
        desiredOptionCount < _entries.length ? desiredOptionCount : _entries.length;
    final distractors = _pickDistractors(answer, optionCount - 1);

    final options = <QuizOption>[
      QuizOption(entryId: answer.id, text: answer.displayText),
      for (final distractor in distractors)
        QuizOption(entryId: distractor.id, text: distractor.displayText),
    ]..shuffle(_random);

    return QuizQuestion(answer: answer, options: options);
  }

  /// Prefers words the user has not been asked about yet; resets once the pool
  /// is exhausted so a 40-question session from a 10-word pack still works.
  VocabEntry _pickNextEntry() {
    if (_askedIds.length >= _entries.length) _askedIds.clear();
    final unseen =
        _entries.where((entry) => !_askedIds.contains(entry.id)).toList();
    final chosen = unseen[_random.nextInt(unseen.length)];
    _askedIds.add(chosen.id);
    return chosen;
  }

  /// Excludes the answer itself, any entry whose display text matches the
  /// answer's, and any entry whose text a distractor already claimed, so two
  /// English words sharing one Arabic translation can never produce an
  /// ambiguous question and no question can render the same option twice.
  /// Returns whatever survives, even when that is fewer than `count`: a short
  /// question beats a duplicated option text.
  List<VocabEntry> _pickDistractors(VocabEntry answer, int count) {
    if (count <= 0) return const <VocabEntry>[];
    final answerText = answer.displayText.toLowerCase();
    final candidates = _entries
        .where((entry) => entry.id != answer.id)
        .where((entry) => entry.displayText.toLowerCase() != answerText)
        .toList();
    final shuffled = List<VocabEntry>.of(candidates)..shuffle(_random);

    final taken = <String>{answerText};
    final picked = <VocabEntry>[];
    for (final candidate in shuffled) {
      if (taken.add(candidate.displayText.toLowerCase())) {
        picked.add(candidate);
        if (picked.length == count) break;
      }
    }
    return picked;
  }
}
