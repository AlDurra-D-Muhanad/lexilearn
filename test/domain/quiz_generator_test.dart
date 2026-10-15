import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/quiz_generator.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

VocabEntry entry(String id, String term, String translation) =>
    VocabEntry(id: id, term: term, translations: <String>[translation]);

List<VocabEntry> poolOf(int n) => <VocabEntry>[
      for (var i = 0; i < n; i++) entry('id-$i', 'term $i', 'translation $i'),
    ];

void main() {
  group('QuizGenerator', () {
    test('produces a question whose correct option is the asked entry', () {
      final generator = QuizGenerator(entries: poolOf(10), random: Random(7));
      final question = generator.next()!;

      expect(question.options, hasLength(4));
      expect(question.options[question.correctIndex].entryId, question.answer.id);
      expect(question.correctIndex, greaterThanOrEqualTo(0));
    });

    test('isCorrect compares entry identity, so typing a character cannot pass',
        () {
      final generator = QuizGenerator(entries: poolOf(10), random: Random(7));
      final question = generator.next()!;

      for (var i = 0; i < question.options.length; i++) {
        expect(question.isCorrect(i), i == question.correctIndex);
      }
      expect(() => question.isCorrect(99), returnsNormally);
      expect(question.isCorrect(99), isFalse);
    });

    test('options are distinct entries', () {
      final generator = QuizGenerator(entries: poolOf(20), random: Random(3));
      for (var i = 0; i < 50; i++) {
        final ids = generator.next()!.options.map((o) => o.entryId).toSet();
        expect(ids, hasLength(4));
      }
    });

    test('the answer is not always in the same position', () {
      final generator = QuizGenerator(entries: poolOf(10), random: Random(11));
      final positions = <int>{
        for (var i = 0; i < 40; i++) generator.next()!.correctIndex,
      };
      expect(positions.length, greaterThan(1));
    });

    test('shrinks options for a one-word pack', () {
      final generator = QuizGenerator(entries: poolOf(1), random: Random(1));
      final question = generator.next()!;
      expect(question.options, hasLength(1));
      expect(question.correctIndex, 0);
      expect(question.isCorrect(0), isTrue);
    });

    test('shrinks options for a two-word pack', () {
      final generator = QuizGenerator(entries: poolOf(2), random: Random(1));
      expect(generator.next()!.options, hasLength(2));
    });

    test('shrinks options for a three-word pack', () {
      final generator = QuizGenerator(entries: poolOf(3), random: Random(1));
      expect(generator.next()!.options, hasLength(3));
    });

    test('never offers a distractor with the answer\'s own text', () {
      final entries = <VocabEntry>[
        entry('a', 'multiplexer', 'معدد'),
        entry('b', 'switch', 'معدد'),
        entry('c', 'router', 'موجه'),
        entry('d', 'gateway', 'بوابة'),
        entry('e', 'bridge', 'جسر'),
      ];
      final generator = QuizGenerator(entries: entries, random: Random(5));

      for (var i = 0; i < 40; i++) {
        final question = generator.next()!;
        final correctText = question.options[question.correctIndex].text;
        final texts = question.options.map((o) => o.text).toList();
        expect(texts.where((t) => t == correctText), hasLength(1),
            reason: 'duplicate option text in $texts');
      }
    });

    test('cycles through every entry before repeating one', () {
      final generator = QuizGenerator(entries: poolOf(5), random: Random(2));
      final asked = <String>{
        for (var i = 0; i < 5; i++) generator.next()!.answer.id,
      };
      expect(asked, hasLength(5));
    });

    test('returns null for an empty pack', () {
      final generator =
          QuizGenerator(entries: const <VocabEntry>[], random: Random(1));
      expect(generator.canGenerate, isFalse);
      expect(generator.next(), isNull);
    });

    test('is reproducible for a given seed', () {
      List<int> run() {
        final generator = QuizGenerator(entries: poolOf(10), random: Random(42));
        return <int>[
          for (var i = 0; i < 10; i++) generator.next()!.correctIndex,
        ];
      }

      expect(run(), run());
    });

    test('falls back to the term when an entry has no translation', () {
      final generator = QuizGenerator(
        entries: <VocabEntry>[
          const VocabEntry(id: 'a', term: 'orphan', translations: <String>[]),
          entry('b', 'x', 'y'),
        ],
        random: Random(1),
      );
      final question = generator.next()!;
      if (question.answer.id == 'a') {
        expect(question.options[question.correctIndex].text, 'orphan');
      }
    });
  });
}