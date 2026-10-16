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

/// How many seeds the nested-translation pair is driven across.
///
/// Two is the minimum that can draw both orders; the range is wider than that on
/// purpose, because it also has to keep drawing *questions* and not start
/// repeating one entry forever. Eight is comfortably inside both.
const int _nestedSeeds = 8;

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

  test('the progress row is written against the answer, not the option picked',
      () async {
    final controller = build(count: 1);
    await controller.start();
    final question = controller.question!;
    final picked = _firstWrongIndex(controller);

    await controller.answer(picked);

    // **Which entry the row is keyed on is the entire content of the guarantee.**
    // `recordAnswer` keys progress on `entryId`, so writing the *picked* option's
    // id instead of the answer's files a wrong answer against the distractor's
    // word — crediting the user's mistake to a word they were never asked about,
    // and leaving the word that was asked unmarked. Every other test in this
    // file passes under that mutation, because `StatsSummary.totalAttempts` and
    // `totalCorrect` are aggregates over the pack and cannot tell the two ids
    // apart. So this reads the row itself.
    final rows = await harness.database.query(
      'word_progress',
      where: 'pack_key = ?',
      whereArgs: <Object?>['p'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['entry_id'], question.answer.id);
    expect(rows.single['entry_id'], isNot(question.options[picked].entryId));
    // And it is a miss, which is the other half of what that row says.
    expect(rows.single['correct_count'], 0);
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

  test('every method is safe to call after dispose()', () async {
    final controller = build(count: 2);
    await controller.start();
    final correct = controller.question!.correctIndex;
    controller.dispose();

    // `ChangeNotifier.notifyListeners()` after `dispose()` throws a
    // `FlutterError` in debug rather than doing nothing, and this controller
    // issues database reads that can land after the route owning it is popped.
    // All four notifying methods are therefore routed through one guard.
    //
    // Every method is called, not just the ones that look risky: `answer()` was
    // the one left unguarded while `start()`, `next()` and `_finish()` were
    // fixed, and it was caught by reading the four call sites, not by any test.
    //
    // **This calls three of the four notifying sites, not all four, and the
    // comment used to say otherwise.** `answer`, `next` and `start` are the
    // three public ones; the fourth is the private `_finish()`, which this test
    // never reaches — it answers question 0 of a 2-question quiz, so `next()`
    // advances off the answer rather than consuming the last question and
    // finishing. Deleting the guard from `_finish()` alone would leave this
    // green. It is a canary against a fifth *public* method going in
    // unguarded, not a guarantee about the class, and a comment cannot fail.
    //
    // In this order, because each one has to *reach* a notification to prove
    // anything: `answer` commits and notifies, `next` advances off that answer
    // and notifies again, and `start` re-reads the pack and notifies last. Called
    // the other way round, `start` would reset the selection and `next` would
    // return early — passing while touching nothing.
    await expectLater(controller.answer(correct), completes);
    await expectLater(controller.next(), completes);
    await expectLater(controller.start(), completes);

    // Suppressing the *notification* does not suppress the write, deliberately.
    // An answer that was really given is worth more on disk than it is lost in
    // memory, and making the controller inert after dispose would drop it — the
    // opposite of what ruling 1 of this task asks for.
    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
    expect(stats.totalCorrect, 1);
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

  test('a wrong option whose text shares characters with the right one is wrong',
      () async {
    // The whole point of the port. Every other test here passes under a
    // substring grader too; this one cannot.
    //
    // **Every seed, not one.** `سكينة` is a prefix of `سكينة وهدوء`, so the
    // generator can draw the pair either way round — the long phrase as the
    // answer with the short prefix as the distractor, or the reverse. The two
    // orders are exactly what the two directions of a substring grader disagree
    // about: `answerText.contains(picked)` rejects one and accepts the other, and
    // so does `picked.contains(answerText)`. Pinning a single seed therefore
    // pins one mutant blind: with `Random(3)` the long phrase is always the
    // answer, which catches the first direction and leaves the flipped one — the
    // literal shape of the Python original's `Final_answer.__contains__` — green
    // across the whole suite.
    //
    // Searching the seeds rather than conditioning on a lucky one is the shape
    // `test/domain/quiz_generator_test.dart` uses for the orphan entry, and for
    // the same reason: a silent skip is a green test that asserts nothing.
    final nested = await TestHarness.create(packs: <VocabPack>[_nestedPack]);
    addTearDown(nested.dispose);
    final answerIdsSeen = <String>{};

    for (var seed = 0; seed < _nestedSeeds; seed++) {
      final controller = QuizController(
        repository: nested.repository,
        packKey: 'nested',
        questionCount: 1,
        random: Random(seed),
        clock: () => _pinnedNow,
      );
      await controller.start();

      final question = controller.question!;
      expect(question.options, hasLength(2), reason: 'seed $seed');
      answerIdsSeen.add(question.answer.id);

      // The fixture, not the grader: assert the two strings really are nested,
      // so that editing the pack cannot quietly turn this into a test that
      // passes for the wrong reason.
      final byLength = question.options.map((option) => option.text).toList()
        ..sort((a, b) => a.length.compareTo(b.length));
      expect(byLength.first.length, lessThan(byLength.last.length),
          reason: 'seed $seed');
      expect(byLength.last, contains(byLength.first), reason: 'seed $seed');

      final wrong = _firstWrongIndex(controller);
      await controller.answer(wrong);

      expect(controller.correctCount, 0,
          reason: 'seed $seed: the wrong option scored correct');
      expect(controller.lastSelectedWasCorrect, isFalse, reason: 'seed $seed');

      final stats = await nested.repository.stats('nested');
      expect(stats.totalCorrect, 0,
          reason: 'seed $seed: a wrong answer was written to the database');
      expect(stats.totalAttempts, seed + 1, reason: 'seed $seed');
    }

    // The assertion that makes the loop mean anything: both entries were asked
    // as the answer, so both nesting directions really were exercised. Without
    // it a seed range that happened to draw one order would still pass.
    expect(answerIdsSeen, containsAll(<String>['a', 'b']),
        reason: 'the seed range never drew both nesting orders, so one direction '
            'of a substring grader is untested');
  });

  test('the right option still scores on the nested pack', () async {
    // The other half of the pair: a grader that rejects every answer would pass
    // the test above too. Seeded the same way, and for the same reason.
    final nested = await TestHarness.create(packs: <VocabPack>[_nestedPack]);
    addTearDown(nested.dispose);
    final answerIdsSeen = <String>{};

    for (var seed = 0; seed < _nestedSeeds; seed++) {
      final controller = QuizController(
        repository: nested.repository,
        packKey: 'nested',
        questionCount: 1,
        random: Random(seed),
        clock: () => _pinnedNow,
      );
      await controller.start();

      answerIdsSeen.add(controller.question!.answer.id);
      await controller.answer(controller.question!.correctIndex);

      expect(controller.correctCount, 1, reason: 'seed $seed');
      expect(controller.lastSelectedWasCorrect, isTrue, reason: 'seed $seed');

      final stats = await nested.repository.stats('nested');
      expect(stats.totalCorrect, seed + 1, reason: 'seed $seed');
    }

    expect(answerIdsSeen, containsAll(<String>['a', 'b']),
        reason: 'the seed range never drew both nesting orders, so one direction '
            'of a substring grader is untested');
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
