import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lexilearn/core/clock.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/quiz_generator.dart';
import 'package:lexilearn/domain/quiz_question.dart';

/// State machine for one quiz run.
///
/// Owns the generator and the counters; the repository owns everything that must
/// survive the screen being popped — every answer is written as it happens and
/// the summary line is written when the session ends. The Python original kept
/// nothing at all, which is why a lost session there was a lost session.
///
/// **Nothing in this file compares text.** An answer is graded by asking
/// [QuizQuestion.isCorrect], which resolves the picked index to an option and
/// compares its `entryId` with the answer's. `Search.py` graded with
/// `Final_answer.__contains__(My_answer)`, so a single shared character scored
/// as correct; that rule has no representation here to be reintroduced from.
class QuizController extends ChangeNotifier {
  QuizController({
    required this.repository,
    required this.packKey,
    required int questionCount,
    this.random,
    Clock? clock,
  })  : // The original accepted `0` through its `isdigit()` check and then ran
        // no questions at all, reporting a session of zero. A session of fewer
        // than one question is not a session.
        _questionCount = questionCount < 1 ? 1 : questionCount,
        _clock = clock ?? DateTime.now;

  /// Public and final rather than a private field set from a named parameter:
  /// a private *named* parameter is not legal Dart, so a field carrying the
  /// same name is what lets `this.x` be an initialising formal. The same
  /// reasoning, and the same shape, as `SearchController`.
  final VocabRepository repository;
  final String packKey;

  /// The seed the generator draws from, or `null` for an unseeded run.
  final Random? random;

  /// The number of questions this session will ask. Clamped in the initialiser
  /// rather than named [questionCount], so it cannot be mutated after the fact.
  final int _questionCount;

  /// Stamps the session's `startedAt`. Injected rather than read from the wall
  /// clock so a test can pin it; the repository already owns a `Clock` for every
  /// other timestamp this session causes, and a summary row stamped from a
  /// different clock than its progress rows would sort against them wrongly.
  final Clock _clock;

  QuizGenerator? _generator;
  QuizQuestion? _question;
  int _questionNumber = 0;
  int _answered = 0;
  int _correct = 0;
  int? _selectedIndex;
  bool _started = false;
  bool _sessionSaved = false;
  DateTime? _startedAt;

  /// Set in [dispose]. See [_notifyIfAlive].
  bool _disposed = false;

  QuizQuestion? get question => _question;
  int get answeredCount => _answered;
  int get correctCount => _correct;
  int get questionCount => _questionCount;

  /// Which question is on screen, counted from 1, and 0 when none is.
  ///
  /// Held rather than derived from [answeredCount]: `answered + 1 >= count`
  /// would turn true the moment the *first* of two questions is answered, so the
  /// advance button would offer to finish a session that still had a question
  /// left on it.
  int get questionNumber => _questionNumber;

  /// True once the session has run out of questions.
  ///
  /// Deliberately not `question == null`: that is also what a controller looks
  /// like before [start] has answered its first read, and the quiz screen swaps
  /// to the result screen on this flag — so a controller that had asked nothing
  /// yet would open on "session complete".
  bool get isFinished => _started && _question == null;

  /// Whether an answer has been committed to on the current question, and so
  /// whether the screen's advance button is live.
  bool get canAdvance => _selectedIndex != null;

  /// True on the final question, so the button can say "finish" rather than
  /// "next" on the one tap that ends the session.
  bool get isLastQuestion =>
      _question != null && _questionNumber >= _questionCount;

  /// How far through the session the user is, 0.0 before the first answer and
  /// 1.0 on the last one. This is **completion**, not accuracy.
  double get progress =>
      (_answered / _questionCount).clamp(0.0, 1.0);

  /// How many of the answers given so far were right.
  ///
  /// A separate number from [progress] because the plan's result screen printed
  /// `progress * 100` as a percentage correct, which reads 100% on the last
  /// question however many were wrong.
  double get accuracy => _answered == 0 ? 0 : _correct / _answered;

  /// Whether the current question has been answered.
  ///
  /// [index] is accepted so a tile can ask all three questions about the same
  /// option, but an answer belongs to the question rather than to an option, so
  /// the value is the same for every index.
  bool isAnswered(int index) => _selectedIndex != null;

  /// `null` until an answer is chosen, then `true` only for the option that was
  /// both picked *and* right, and `false` for every other option — including the
  /// right one when the user picked something else.
  bool? answerCorrectness(int index) {
    final selected = _selectedIndex;
    if (selected == null || _question == null) return null;
    return index == selected && _question!.isCorrect(selected);
  }

  /// True only for the option the user actually tapped.
  ///
  /// Separate from [answerCorrectness] because the tile paints two different
  /// things: a wrong pick goes red, and the genuinely right option goes green
  /// even when it is not the one that was picked.
  bool isSelectedOption(int index) =>
      _selectedIndex != null && _selectedIndex == index;

  /// Whether the option the user tapped was the right one.
  bool get lastSelectedWasCorrect {
    final selected = _selectedIndex;
    return selected != null && _question != null && _question!.isCorrect(selected);
  }

  /// The answer to the question on screen — the correct translation, revealed
  /// when it is needed and not before.
  String? get lastAnswerText => _question?.answer.displayText;

  /// Reads the pack and asks the first question.
  ///
  /// Separate from the constructor because a controller cannot do IO before it
  /// is built, and because an empty pack has to end the session rather than
  /// throw: [isFinished] is already true when this returns with no question.
  ///
  /// **The notification at the end is guarded, not bare.** `QuizSetupScreen`
  /// creates this controller inside the pushed route's provider and calls
  /// `start()` off it, so the read this issues is still in flight when the user
  /// can pop that route — and `ChangeNotifier` asserts on `notifyListeners()`
  /// after disposal rather than doing nothing. The route is not cancelling the
  /// read; it is declining to be told about the answer.
  Future<void> start() async {
    _startedAt = _clock();
    final entries = await repository.entries(packKey);
    final generator = QuizGenerator(entries: entries, random: random);
    _generator = generator;
    _started = true;
    _question = generator.canGenerate ? generator.next() : null;
    _questionNumber = _question == null ? 0 : 1;
    _selectedIndex = null;
    _notifyIfAlive();
  }

  /// Commits [index] as the answer to the current question.
  ///
  /// Scoring is by identity — `question.isCorrect(index)` — and never by the
  /// option's text. A second call for a question that has already been answered
  /// is ignored: the Python original re-read its file on every keystroke, so a
  /// double tap scored one question twice.
  Future<void> answer(int index) async {
    final question = _question;
    if (question == null || _selectedIndex != null) return;
    if (index < 0 || index >= question.options.length) return;

    _selectedIndex = index;
    final wasCorrect = question.isCorrect(index);
    _answered++;
    if (wasCorrect) _correct++;
    // Guarded like every other notification here. A tile's `onTap` cannot fire
    // after its route is popped, so this is the one call site where a disposed
    // controller is hard to reach — but "hard to reach" is not "impossible", and
    // an unguarded `notifyListeners()` throws a `FlutterError` rather than doing
    // nothing. All four call sites go through [_notifyIfAlive].
    _notifyIfAlive();

    await repository.recordAnswer(
      packKey: packKey,
      entryId: question.answer.id,
      wasCorrect: wasCorrect,
    );
  }

  /// Moves to the next question, or ends the session.
  ///
  /// Every state change and the notification happen before the database write,
  /// so the screen is never waiting on SQLite to redraw.
  Future<void> next() async {
    if (_selectedIndex == null) return;

    if (_answered >= _questionCount) {
      _finish();
    } else {
      final next = _generator?.next();
      if (next == null) {
        _finish();
      } else {
        _question = next;
        _questionNumber++;
        _selectedIndex = null;
        _notifyIfAlive();
        return;
      }
    }
    await _saveSession();
  }

  void _finish() {
    _question = null;
    _notifyIfAlive();
  }

  /// Writes the session summary, once.
  ///
  /// Skipped for a session in which nothing was answered: a row reading "0 of 0"
  /// in Stats is a session the user had to open and abandon to create.
  Future<void> _saveSession() async {
    if (_sessionSaved || _answered == 0) return;
    _sessionSaved = true;
    await repository.finishSession(
      packKey: packKey,
      startedAt: _startedAt ?? _clock(),
      totalQuestions: _answered,
      correctCount: _correct,
    );
  }

  @override
  void dispose() {
    // Answers are already persisted one at a time and the summary is written the
    // moment the last question is left, so a session torn down mid-question
    // loses nothing but the fact that it was abandoned.
    _disposed = true;
    super.dispose();
  }

  /// `notifyListeners()` after [dispose] throws in debug, and every write to the
  /// database this controller issues can land after the route that owns it has
  /// been popped — [start] is the one that starts before any frame is drawn.
  /// Same guard, and the same name, as `SearchController`.
  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }
}
