import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/quiz_question.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/quiz/quiz_controller.dart';

import '../helpers/test_env.dart';

/// The instant every timestamp in this file is pinned to, so a session's
/// `startedAt` can be asserted rather than merely counted.
final DateTime _pinnedNow = DateTime.utc(2026, 10, 14, 12);

/// Five distinct words, so a question can always offer three distractors.
const VocabPack _pack = VocabPack(
  schemaVersion: 1,
  packId: 'p',
  title: 'P',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['ألف']),
    VocabEntry(id: 'b', term: 'beta', translations: <String>['بيتا']),
    VocabEntry(id: 'c', term: 'gamma', translations: <String>['جاما']),
    VocabEntry(id: 'd', term: 'delta', translations: <String>['دلتا']),
    VocabEntry(id: 'e', term: 'epsilon', translations: <String>['إبسيلون']),
  ],
);

/// Two words whose Arabic translations are **nested**: one is a prefix of the
/// other. This is the shape that breaks a substring grader and nothing else.
///
/// The Python original graded with `Final_answer.__contains__(My_answer)`, so
/// on this pack any substring grader scores both questions right no matter which
/// of the two the user picks. The generator is unaffected — it only rejects
/// options whose text is *equal* — so the fixture produces a real, unanswerable-
/// by-text question rather than a degenerate one.
const VocabPack _nestedPack = VocabPack(
  schemaVersion: 1,
  packId: 'nested',
  title: 'Nested',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'serenity', translations: <String>['سكينة']),
    VocabEntry(id: 'b', term: 'calm', translations: <String>['سكينة وهدوء']),
  ],
);

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[_pack]);
  });

  tearDown(() => harness.dispose());

  QuizController build({int count = 3, Random? random}) => QuizController(
        repository: harness.repository,
        packKey: 'p',
        questionCount: count,
        random: random ?? Random(9),
        clock: () => _pinnedNow,
      );

  test('starts with no question until start() is called', () {
    final controller = build();

    expect(controller.question, isNull);
    // Not finished: nothing has been asked yet. `question == null` alone cannot
    // say that, because it is also what "the session is over" looks like — the
    // result screen is reached the moment this is true, so a controller that had
    // not asked anything yet would render as a finished session.
    expect(controller.isFinished, isFalse);
    expect(controller.answeredCount, 0);
    expect(controller.progress, 0);
  });

  test('start() loads a question and answering advances the session', () async {
    final controller = build(count: 3);
    await controller.start();

    expect(controller.question, isNotNull);
    expect(controller.answeredCount, 0);

    await controller.answer(controller.question!.correctIndex);
    expect(controller.answeredCount, 1);
    expect(controller.correctCount, 1);
    expect(controller.isAnswered(controller.question!.correctIndex), isTrue);
    expect(controller.canAdvance, isTrue);
  });

  test('a wrong answer still advances and is not counted', () async {
    final controller = build(count: 2);
    await controller.start();

    await controller.answer(_firstWrongIndex(controller));
    expect(controller.correctCount, 0);
    expect(controller.answeredCount, 1);
  });

  test('answering twice for the same question is ignored', () async {
    final controller = build(count: 3);
    await controller.start();
    final question = controller.question!;

    await controller.answer(question.correctIndex);
    await controller.answer(_firstWrongIndex(controller));

    // The Python original re-read the file on every keystroke, so a double tap
    // scored the same question twice. The guard is the whole point: one tap,
    // one answer, one row in the database.
    expect(controller.answeredCount, 1);
    expect(controller.correctCount, 1);

    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
  });

  test('the session ends after exactly questionCount questions', () async {
    final controller = build(count: 3);
    await controller.start();

    for (var i = 0; i < 3; i++) {
      await controller.answer(controller.question!.correctIndex);
      await controller.next();
    }

    expect(controller.isFinished, isTrue);
    expect(controller.answeredCount, 3);
    expect(controller.question, isNull);
  });

  test('progress runs from 0 to 1', () async {
    final controller = build(count: 4);
    await controller.start();
    expect(controller.progress, 0);

    await controller.answer(controller.question!.correctIndex);
    await controller.next();
    expect(controller.progress, closeTo(0.25, 0.001));

    expect(controller.isLastQuestion, isFalse);
  });

  test('the last question is flagged so the button can say so', () async {
    final controller = build(count: 2);
    await controller.start();
    expect(controller.isLastQuestion, isFalse);

    await controller.answer(controller.question!.correctIndex);
    await controller.next();
    expect(controller.isLastQuestion, isTrue);
  });

  test('accuracy is correct over answered, not over the session length', () async {
    final controller = build(count: 4);
    await controller.start();

    await controller.answer(controller.question!.correctIndex);
    expect(controller.accuracy, 1);
    expect(controller.progress, closeTo(0.25, 0.001));

    await controller.next();
    await controller.answer(_firstWrongIndex(controller));
    await controller.next();

    // Half of the two answered questions. `progress * 100` — what the plan's
    // result screen printed — is the fraction of the session *completed*, which
    // on the final question is always 100% however many were wrong.
    expect(controller.accuracy, closeTo(0.5, 0.001));
    expect(controller.progress, closeTo(0.5, 0.001));
  });

  test('a count larger than the pack still produces questions by cycling', () async {
    final controller = build(count: 20);
    await controller.start();
    expect(controller.question, isNotNull);

    await controller.answer(controller.question!.correctIndex);
    await controller.next();
    expect(controller.question, isNotNull);
    expect(controller.isFinished, isFalse);
  });

  test('a count of zero is clamped to one instead of running nothing', () async {
    // The original accepted `0` through its `isdigit()` check and silently ran
    // no questions at all.
    final controller = build(count: 0);
    expect(controller.questionCount, 1);

    await controller.start();
    await controller.answer(controller.question!.correctIndex);
    await controller.next();

    expect(controller.isFinished, isTrue);
    expect(controller.answeredCount, 1);
  });

  test('an empty pack finishes immediately instead of throwing', () async {
    await harness.repository.importPack(PackCodec.encodePack(
      const VocabPack(
        schemaVersion: 1,
        packId: 'empty',
        title: 'Empty',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: <VocabEntry>[],
      ),
    ));
    final controller = QuizController(
      repository: harness.repository,
      packKey: 'empty',
      questionCount: 5,
      random: Random(1),
      clock: () => _pinnedNow,
    );

    await controller.start();
    expect(controller.isFinished, isTrue);
    expect(controller.question, isNull);
  });

  test('answers are persisted so stats survive the screen', () async {
    final controller = build(count: 1);
    await controller.start();
    await controller.answer(controller.question!.correctIndex);
    await controller.next();

    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
    expect(stats.totalCorrect, 1);
  });

  test('a wrong answer is persisted as a wrong one', () async {
    final controller = build(count: 1);
    await controller.start();
    await controller.answer(_firstWrongIndex(controller));
    await controller.next();

    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
    expect(stats.totalCorrect, 0);
  });

  test('finishing a session records it in history', () async {
    final controller = build(count: 1);
    await controller.start();
    await controller.answer(controller.question!.correctIndex);
    await controller.next();

    final stats = await harness.repository.stats('p');
    expect(stats.recentSessions, hasLength(1));
    expect(stats.recentSessions.single.totalQuestions, 1);
    expect(stats.recentSessions.single.correctCount, 1);
    // From the injected clock, not the wall clock: every other timestamp this
    // controller causes is stamped by the repository's own clock, and a session
    // row that disagreed with the progress rows it summarises would sort wrong.
    expect(stats.recentSessions.single.startedAt, _pinnedNow);
  });

  test('the session is recorded once however often next() is called', () async {
    final controller = build(count: 1);
    await controller.start();
    await controller.answer(controller.question!.correctIndex);
    await controller.next();
    await controller.next();
    await controller.next();

    final stats = await harness.repository.stats('p');
    expect(stats.recentSessions, hasLength(1));
  });

  test('next() does nothing once the session is finished', () async {
    final controller = build(count: 1);
    await controller.start();
    await controller.answer(controller.question!.correctIndex);
    await controller.next();
    await controller.next();
    expect(controller.answeredCount, 1);
  });

  test('next() does nothing before an answer is chosen', () async {
    final controller = build(count: 3);
    await controller.start();
    final first = controller.question;

    await controller.next();

    // Otherwise the very first tap on a disabled button would silently skip a
    // question the user never saw.
    expect(controller.question, same(first));
    expect(controller.isFinished, isFalse);
  });

  test('answerCorrectness is null until an answer is chosen', () async {
    final controller = build(count: 2);
    await controller.start();
    final question = controller.question!;

    expect(controller.answerCorrectness(question.correctIndex), isNull);
    expect(controller.isSelectedOption(question.correctIndex), isFalse);
    expect(controller.lastAnswerText, question.answer.displayText);

    await controller.answer(question.correctIndex);

    expect(controller.answerCorrectness(question.correctIndex), isTrue);
    expect(controller.lastSelectedWasCorrect, isTrue);
    // Every other option reads false — including the wrong one, which is not
    // what makes it wrong.
    for (var i = 0; i < question.options.length; i++) {
      if (i == question.correctIndex) continue;
      expect(controller.answerCorrectness(i), isFalse);
      expect(controller.isSelectedOption(i), isFalse);
    }
  });

  test('a wrong pick is the selected option and reads false', () async {
    final controller = build(count: 2);
    await controller.start();
    final question = controller.question!;
    final wrong = _firstWrongIndex(controller);

    await controller.answer(wrong);

    expect(controller.isSelectedOption(wrong), isTrue);
    expect(controller.answerCorrectness(wrong), isFalse);
    expect(controller.lastSelectedWasCorrect, isFalse);
    expect(controller.answerCorrectness(question.correctIndex), isFalse);
  });

  test('an out-of-range tap is refused instead of crashing the session', () async {
    final controller = build(count: 2);
    await controller.start();

    await controller.answer(-1);
    expect(controller.answeredCount, 0);
    await controller.answer(controller.question!.options.length);
    expect(controller.answeredCount, 0);

    // And the session is still playable afterwards.
    await controller.answer(controller.question!.correctIndex);
    expect(controller.answeredCount, 1);
  });

  test('a wrong option whose text shares characters with the right one is wrong', () async {
    // The whole point of the port. Every other test here passes under a
    // substring grader too; this one cannot.
    final nested = await TestHarness.create(packs: <VocabPack>[_nestedPack]);
    addTearDown(nested.dispose);
    final controller = QuizController(
      repository: nested.repository,
      packKey: 'nested',
      questionCount: 1,
      random: Random(3),
      clock: () => _pinnedNow,
    );
    await controller.start();

    final question = controller.question!;
    expect(question.options, hasLength(2));

    // The fixture, not the grader: assert the two strings really are nested, so
    // that editing the pack cannot quietly turn this into a test that passes for
    // the wrong reason.
    final byLength = question.options.map((option) => option.text).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    expect(byLength.first.length, lessThan(byLength.last.length));
    expect(byLength.last, contains(byLength.first));

    final wrong = _firstWrongIndex(controller);
    await controller.answer(wrong);

    expect(controller.correctCount, 0, reason: 'the wrong option scored correct');
    expect(controller.lastSelectedWasCorrect, isFalse);
    final stats = await nested.repository.stats('nested');
    expect(stats.totalCorrect, 0);
    expect(stats.totalAttempts, 1);
  });

  test('the right option still scores on the nested pack', () async {
    // The other half of the pair: a grader that rejects every answer would pass
    // the test above too.
    final nested = await TestHarness.create(packs: <VocabPack>[_nestedPack]);
    addTearDown(nested.dispose);
    final controller = QuizController(
      repository: nested.repository,
      packKey: 'nested',
      questionCount: 1,
      random: Random(3),
      clock: () => _pinnedNow,
    );
    await controller.start();

    await controller.answer(controller.question!.correctIndex);
    expect(controller.correctCount, 1);
    expect(controller.lastSelectedWasCorrect, isTrue);

    final stats = await nested.repository.stats('nested');
    expect(stats.totalCorrect, 1);
  });
}

/// The index of an option that is not the answer.
///
/// Identity, from [QuizQuestion.isCorrect] — never by comparing text, which is
/// the bug this task exists to keep fixed.
int _firstWrongIndex(QuizController controller) {
  final question = controller.question!;
  for (var i = 0; i < question.options.length; i++) {
    if (!question.isCorrect(i)) return i;
  }
  throw StateError('the generated question had no wrong option');
}
