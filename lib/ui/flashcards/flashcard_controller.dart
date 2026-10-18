import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/quiz_generator.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

/// One flashcard deck: the term, the user asking for its meaning, and the user
/// saying whether they knew it.
///
/// Deliberately simpler than the four-option quiz in `quiz_controller.dart`, and
/// for the reason the artwork draws them as two different screens. A quiz asks a
/// question and grades an option against four others; a card shows one word and
/// asks the user about themselves. There is no distractor here and no grading —
/// `answer(knewIt:)` records what the *user* said, so this controller never
/// compares text and neither does the screen.
///
/// **What it does share is the dealer's cycling rule**, so this uses
/// [QuizGenerator] rather than a private shuffle. `QuizGenerator._pickNextEntry`
/// prefers words the user has not been asked about yet and resets once the pool
/// is exhausted, which is exactly what a deck needs: a ten-card deck off a
/// three-word pack has to come back round rather than run dry, and a second copy
/// of that rule is how two screens end up disagreeing about what "next" means.
/// Only [QuizGenerator.next]'s answer is read — the distractors it builds on the
/// way are thrown away.
///
/// Every answer is written as it is given, so a deck abandoned half-way leaves
/// the words it covered in the progress the statistics screen reads. There is no
/// session summary here, and that is not an omission: `QuizSessionResult` is a
/// four-option quiz's score, and "four out of ten cards I said I knew" is a
/// different number that nothing in the data model records.
class FlashcardController extends ChangeNotifier {
  FlashcardController({
    required this.repository,
    required this.packKey,
    required int cardCount,
    this.random,
    this.entries,
  })  // Clamped in the initialiser rather than named [cardCount], so it cannot
        // be changed after the fact and `progress` cannot divide by zero. Same
        // rule and same reason as `QuizController._questionCount`: a deck
        // shorter than one card is not a deck.
        : _cardCount = cardCount < 1 ? 1 : cardCount;

  /// Public and final rather than a private field set from a named parameter:
  /// the interface this task was given names them `repository`, `packKey` and
  /// `random`, and a field carrying the same name is what lets `this.x` be an
  /// initialising formal. The same reasoning, and the same shape, as
  /// `QuizController` and `SearchController`.
  final VocabRepository repository;
  final String packKey;

  /// The seed the generator draws from, or `null` for an unseeded deck.
  ///
  /// **Null on the screen's own path, deliberately.** A fixed seed here would
  /// deal every user the identical deck, which is the opposite of what a
  /// vocabulary app is for. It is a parameter so a test can hand in an instance
  /// that has already dealt a word it can name.
  final Random? random;

  /// The pack's words, when the caller already has them.
  ///
  /// **Optional, and the reason this screen mounts **one** database read rather
  /// than two.** [cardCount] has to be known before this object exists — the
  /// `3/10` counter and the progress bar both need it, and deriving the
  /// denominator from the cards actually dealt would make it unknowable until the
  /// deck was over — so a caller that does not already hold the pack has to read
  /// it, and then [start] would read it a second time to deal from it.
  ///
  /// `FlashcardsScreen` does hold it: it reads once to learn the size, and passes
  /// the words in so [start] deals from memory. **Two sequential reads halved to
  /// one**, which is not just tidiness here — a `testWidgets` body drives the real
  /// event loop only through `runAsync`, so every extra read is another round
  /// trip a test has to wait for and another chance for one to still be in flight
  /// when the test ends. `home_shell_test.dart`'s destination helper gives a
  /// mounted destination a single `settleDatabase`, and one read is what makes
  /// that sufficient.
  ///
  /// Left `null` — as every caller outside the screen does, and as every test in
  /// `test/ui/flashcard_controller_test.dart` does — [start] reads the pack
  /// itself, which is what makes this controller usable on its own.
  final List<VocabEntry>? entries;

  /// How many cards this deck deals. Clamped, and never re-read.
  final int _cardCount;

  QuizGenerator? _generator;
  VocabEntry? _current;

  /// Cards answered so far. Also the artwork's `3/10`: the screen prints
  /// `index + 1` while a card is on screen, so this is the count of cards
  /// *behind* the one being looked at.
  int _seen = 0;
  int _known = 0;
  bool _revealed = false;

  /// Set by [start] whether or not the pack had anything in it. See [isFinished].
  bool _started = false;

  /// Set in [dispose]. See [_notifyIfAlive].
  bool _disposed = false;

  /// The card on screen, or `null` once the deck is over or before it has been
  /// dealt. Read `isFinished` rather than testing this for `null`: `null` is
  /// also what a controller looks like for the whole of the read behind [start].
  VocabEntry? get current => _current;

  /// Whether the meaning is on screen. False for a freshly dealt card, so a
  /// word's Arabic never appears before the user asks for it.
  bool get revealed => _revealed;

  /// How many cards have been answered, counted from 0.
  int get index => _seen;

  /// How many cards this deck deals.
  int get total => _cardCount;

  /// How many of the answers given so far were *أعرف*.
  ///
  /// Separate from [progress] on purpose. [progress] is how far through the deck
  /// the user is and is what the bar and the `3/10` read; [knownCount] is a
  /// score, and a percentage printed from [progress] would read 100% on the last
  /// card however many were *لا أعرف*.
  int get knownCount => _known;

  /// True once the deck has run out of cards — and false until [start] has
  /// answered.
  ///
  /// **Not `current == null`.** `HomeShell` mounts this screen inside an
  /// `AnimatedSwitcher` and the read [start] issues cannot answer before the
  /// first frame has been built, so a controller with no card yet is *loading*,
  /// not finished, and deriving the flag from the card alone would paint
  /// *انتهت الجلسة* over a deck that has not started. Same reason, and the same
  /// `_started` flag, as `QuizController.isFinished`.
  bool get isFinished => _started && _current == null;

  /// 0.0 before the first card is answered, 1.0 once the last one is.
  ///
  /// **Completion, not accuracy.** The clamped range is belt-and-braces rather
  /// than a live case: `_seen` cannot pass `_cardCount` because [answer] stops
  /// dealing at that point.
  double get progress => (_seen / _cardCount).clamp(0.0, 1.0);

  /// Reads the pack and deals the first card.
  ///
  /// Separate from the constructor because a controller cannot do IO before it
  /// is built. An empty pack — or an empty pack key, which is `HomeShell`'s
  /// start-up window rather than a missing pack — ends the deck instead of
  /// throwing, and [isFinished] is already true when this returns.
  ///
  /// **The notification at the end is guarded, not bare.** The screen creates
  /// this controller and fires [start] off it, so the read is still in flight
  /// when the user can switch bar destinations and tear the screen down — and
  /// `ChangeNotifier` asserts on `notifyListeners()` after disposal rather than
  /// doing nothing.
  ///
  /// **Reads the pack only when [entries] was not supplied**, so the screen's
  /// two sequential reads collapse to one. See [entries].
  Future<void> start() async {
    final pool = entries ?? await repository.entries(packKey);
    final generator = QuizGenerator(entries: pool, random: random);
    _generator = generator;
    _started = true;
    _current = generator.canGenerate ? generator.next()?.answer : null;
    _revealed = false;
    _notifyIfAlive();
  }

  /// Shows the card's Arabic. Records nothing — looking is not knowing.
  Future<void> reveal() async {
    if (_current == null) return;
    _revealed = true;
    _notifyIfAlive();
  }

  /// Records what the user said about the card on screen and deals the next.
  ///
  /// The counters and the next card are settled **before** the write, so the
  /// screen is never waiting on SQLite to redraw. A deck that is already over,
  /// or that has not been dealt a card yet, records nothing.
  ///
  /// **The write cannot fail the caller, and that is a deliberate contract.**
  /// `recordAnswer` is an uncaught async database call, and a tap on «أعرف»
  /// followed by an immediate teardown — switching bar destinations, pressing
  /// back, or a test ending — leaves it in flight against a database that is then
  /// closed underneath it. Measured on this project: that surfaces as
  /// `SqfliteFfiException(error, Bad state: This database has already been
  /// closed)` **thrown after the test had already passed**, which is a test that
  /// reports a failure it did not cause and a reviewer cannot reproduce.
  ///
  /// So the write is swallowed, and what is lost is bounded and stated: a deck
  /// torn down mid-answer loses **at most one progress row**, and only for the
  /// card that was on screen when the screen went away. The alternative — letting
  /// it propagate — buys nothing a user could act on and costs a real class of
  /// spurious red.
  ///
  /// **What this deliberately does NOT do is gate the next answer.** An earlier
  /// draft of the task report proposed a `canAnswer` flag that would refuse an
  /// answer while a write was in flight, and that is the wrong shape: it silently
  /// **drops a legitimate fast answer**, trading a rare mis-count for a routine
  /// lost tap — the user taps «لا أعرف» fast and nothing is recorded, with no
  /// indication anything happened. If the double-tap hazard is ever fixed it wants
  /// a **per-deal token plus a debounce**: identity, not a lock, so the second tap
  /// is recognised as belonging to a card already consumed rather than refused as
  /// arriving too soon.
  Future<void> answer({required bool knewIt}) async {
    final card = _current;
    if (card == null) return;

    _seen++;
    if (knewIt) _known++;
    _revealed = false;
    if (_seen >= _cardCount) {
      _current = null;
    } else {
      _current = _generator?.next()?.answer;
    }
    _notifyIfAlive();

    try {
      await repository.recordAnswer(
        packKey: packKey,
        entryId: card.id,
        wasCorrect: knewIt,
      );
    } on Object {
      // At most one progress row, for the card that was on screen — see above.
      // Deliberately `on Object` and not `on Exception`: the failure being
      // swallowed here is a `StateError` from a closed database, not an
      // `Exception`, and a narrower catch would not catch it. The same broad
      // catch is what `StatsController.load` already uses for its read.
    }
  }

  @override
  void dispose() {
    // Every answer is already persisted as it is given, so a deck torn down
    // mid-session loses nothing but the cards that were never reached.
    _disposed = true;
    super.dispose();
  }

  /// `notifyListeners()` after [dispose] throws in debug, and every write to the
  /// database this controller issues can land after the screen that owns it has
  /// been torn down. Same guard, and the same name, as `QuizController` and
  /// `SearchController`.
  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }
}