import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/quiz_generator.dart';
import 'package:lexilearn/domain/quiz_option.dart';
import 'package:lexilearn/domain/quiz_question.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

VocabEntry entry(String id, String term, String translation) =>
    VocabEntry(id: id, term: term, translations: <String>[translation]);

List<VocabEntry> poolOf(int n) => <VocabEntry>[
      for (var i = 0; i < n; i++) entry('id-$i', 'term $i', 'translation $i'),
    ];

/// No two options may render the same string, in any casing. Two identical
/// options are both graded wrong, which is what made the original look broken.
void expectOptionTextsAreDistinct(QuizQuestion question, {String? context}) {
  final texts = question.options.map((option) => option.text).toList();
  final folded = texts.map((text) => text.toLowerCase()).toList();
  expect(folded.toSet(), hasLength(folded.length),
      reason: '${context ?? 'question'} rendered duplicate option text in $texts');
}

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
        expectOptionTextsAreDistinct(question);
      }
    });

    test('never offers two distractors that render the same text', () {
      // The bundled data holds translations that differ only by case as well
      // as exact duplicates, and filtering candidates against the answer alone
      // let both members of such a pair through as distractors.
      final entries = <VocabEntry>[
        entry('a', 'alpha', 'M_u'),
        entry('b', 'beta', 'm_u'),
        entry('c', 'gamma', 'G'),
        entry('d', 'delta', 'D'),
      ];
      final generator = QuizGenerator(entries: entries, random: Random(3));

      for (var i = 0; i < 40; i++) {
        expectOptionTextsAreDistinct(generator.next()!,
            context: 'seed 3 draw $i');
      }
    });

    test('the bundled pack never renders two options with the same text', () {
      final pack = PackCodec.decodePack(
          File('assets/packs/english_ar_v1.json').readAsStringSync());
      expect(pack.entries.length, greaterThan(1));

      // Seven display texts in the bundled data are shared by two entries
      // each, so a duplicate pair is reachable, not theoretical.
      var questionsChecked = 0;
      for (var seed = 0; seed < 20; seed++) {
        final generator =
            QuizGenerator(entries: pack.entries, random: Random(seed));
        for (var i = 0; i < 200; i++) {
          expectOptionTextsAreDistinct(generator.next()!,
              context: 'bundled pack seed $seed draw $i');
          questionsChecked++;
        }
      }
      expect(questionsChecked, 4000);
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
      const orphan = VocabEntry(id: 'a', term: 'orphan', translations: <String>[]);
      const question = QuizQuestion(
        answer: orphan,
        options: <QuizOption>[QuizOption(entryId: 'a', text: 'orphan')],
      );

      expect(question.options[question.correctIndex].text, 'orphan');
      expect(question.isCorrect(0), isTrue);
    });

    test('grades by entry id, so two options that read alike are one answer', () {
      // The generator cannot produce this question: `_pickDistractors` rejects
      // any distractor whose text matches the answer's. It is built by hand for
      // exactly that reason — the guarantee under test is `QuizQuestion`'s, and
      // the generator's dedup only means no *reachable* question currently
      // depends on it. Writing `isCorrect` as normalised text equality instead
      // of an id comparison passes every other test in the suite, so without
      // this one the guarantee has no failing test behind it at all.
      const answer = VocabEntry(
        id: 'b',
        term: 'calm',
        translations: <String>['سكينة'],
      );
      const question = QuizQuestion(
        answer: answer,
        options: <QuizOption>[
          QuizOption(entryId: 'a', text: 'سكينة'),
          QuizOption(entryId: 'b', text: 'سكينة'),
        ],
      );

      expect(question.correctIndex, 1, reason: 'the id match is not the answer');
      expect(question.isCorrect(0), isFalse,
          reason: 'option 0 reads the same as the answer, and is not it');
      expect(question.isCorrect(1), isTrue);
      // And the range guard still applies, so a tap on a removed widget cannot
      // walk off the end of the list on its way to an id comparison.
      expect(question.isCorrect(-1), isFalse);
      expect(question.isCorrect(2), isFalse);
    });

    test('asks the entry with no translation instead of skipping it', () {
      final generator = QuizGenerator(
        entries: <VocabEntry>[
          const VocabEntry(id: 'a', term: 'orphan', translations: <String>[]),
          entry('b', 'x', 'y'),
        ],
        random: Random(1),
      );

      // Search for the orphan across the session rather than conditioning the
      // assertion on one lucky seed: a silent skip is a green test that
      // asserts nothing.
      QuizQuestion? orphanQuestion;
      for (var i = 0; i < 20 && orphanQuestion == null; i++) {
        final question = generator.next()!;
        if (question.answer.id == 'a') orphanQuestion = question;
      }

      expect(orphanQuestion, isNotNull,
          reason: 'the entry with no translation was never asked in 20 questions');
      expect(orphanQuestion!.options[orphanQuestion.correctIndex].text,
          'orphan');
    });
  });
}