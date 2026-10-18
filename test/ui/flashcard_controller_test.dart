import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/flashcards/flashcard_controller.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../helpers/test_env.dart';

/// Three words, so a three-card deck and a four-card run over the same pack are
/// both reachable: the generator cycles rather than running dry, which is what
/// makes the fourth card of a four-card deck a real thing.
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
  ],
);

/// A repository whose progress writes always fail.
///
/// **Why the guard is pinned this way and not by a teardown race.** The failure
/// the `try`/`on Object` in [FlashcardController.answer] exists for is a database
/// closed *underneath* a write still in flight — a **teardown ordering** race, not
/// a value. A first attempt at a test for it tapped «أعرف», deliberately did not
/// settle, unmounted, and then waited 200 ms of real time for the abandoned write
/// to land. **That test stayed green with the wrapper deleted**, because the
/// 200 ms was enough for the write to finish before anything closed: a weak test
/// rather than a guard, which `docs/engineering-standards.md` §9 puts down to the
/// test's own design. Reproducing the real race needs teardown ordering a unit
/// test does not control.
///
/// So the same code path is exercised with the timing removed: the write fails, and
/// [FlashcardController.answer] must still complete normally. `StateError` is the
/// type the real failure carries — a closed database is a bad *state*, not an
/// `Exception` — so the fixture would not pass against an `on Exception` either.
class _FailingWriteRepository extends VocabRepository {
  _FailingWriteRepository(Database database) : super(database: database);

  @override
  Future<void> recordAnswer({
    required String packKey,
    required String entryId,
    required bool wasCorrect,
  }) async =>
      throw StateError('This database has already been closed.');
}

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: const <VocabPack>[_pack]);
  });

  tearDown(() => harness.dispose());

  FlashcardController build({int count = 3, int seed = 5}) => FlashcardController(
        repository: harness.repository,
        packKey: 'p',
        cardCount: count,
        random: Random(seed),
      );

  test('starts with the first card showing the term only', () async {
    final controller = build();
    await controller.start();

    expect(controller.current, isNotNull);
    // The card is dealt face-down: the artwork's `serenity` sits over its Arabic
    // only once the user has asked to see it.
    expect(controller.revealed, isFalse);
    expect(controller.index, 0);
    expect(controller.total, 3);
    expect(controller.progress, 0);
  });

  /// A controller that has not run [FlashcardController.start] yet has no card
  /// because the read is still in flight, not because the deck is over.
  ///
  /// `HomeShell` mounts this screen inside an `AnimatedSwitcher` and the read
  /// cannot answer before the first frame is built, so `isFinished` derived from
  /// "no current card" alone would paint *انتهت الجلسة* over a deck that is
  /// merely loading. Same reason `QuizController.isFinished` carries a `_started`
  /// flag, and pinned the same way.
  test('a deck that has not started is not finished', () async {
    final controller = build();
    expect(controller.current, isNull);
    expect(controller.isFinished, isFalse);
  });

  test('reveal shows the translation without scoring anything', () async {
    final controller = build();
    await controller.start();
    await controller.reveal();

    expect(controller.revealed, isTrue);
    // Looking is not knowing: an un-answered card must leave no progress row
    // behind, or simply reading a deck would fill the statistics screen.
    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 0);
    expect(stats.wordsPracticed, 0);
    // …and it must not advance the deck either.
    expect(controller.index, 0);
    expect(controller.isFinished, isFalse);
  });

  test('answering records progress for that word', () async {
    final controller = build();
    await controller.start();
    final id = controller.current!.id;
    await controller.answer(knewIt: true);

    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
    expect(stats.wordsPracticed, 1);
    expect(stats.totalCorrect, 1);
    expect(id, isNotEmpty);
  });

  test('answering wrong does not increment correct', () async {
    final controller = build();
    await controller.start();
    await controller.answer(knewIt: false);

    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
    expect(stats.totalCorrect, 0);
    expect(controller.knownCount, 0);
  });

  test('the deck finishes after exactly cardCount cards', () async {
    final controller = build(count: 3);
    await controller.start();
    for (var i = 0; i < 3; i++) {
      await controller.answer(knewIt: i % 2 == 0);
    }

    expect(controller.isFinished, isTrue);
    expect(controller.knownCount, 2);
    expect(controller.index, 3);
    expect(controller.progress, 1);
  });

  test('every answered card leaves exactly one progress row', () async {
    final controller = build(count: 3);
    await controller.start();
    for (var i = 0; i < 3; i++) {
      await controller.answer(knewIt: true);
    }

    final stats = await harness.repository.stats('p');
    // Three cards off a three-word pack, so three rows and three attempts. A
    // deck that re-dealt the same word twice would show fewer rows than
    // attempts, which is the difference this asserts.
    expect(stats.wordsPracticed, 3);
    expect(stats.totalAttempts, 3);
    expect(stats.totalCorrect, 3);
  });

  test('a new card is dealt unrevealed after every answer', () async {
    final controller = build(count: 3);
    await controller.start();
    await controller.reveal();
    expect(controller.revealed, isTrue);

    await controller.answer(knewIt: true);

    // Otherwise the next word's translation would be on screen before the user
    // asked for it, which is the one thing this screen is for.
    expect(controller.revealed, isFalse);
    expect(controller.current, isNotNull);
  });

  test('progress runs from 0 to 1', () async {
    final controller = build(count: 4);
    await controller.start();
    expect(controller.progress, 0);

    await controller.answer(knewIt: true);
    expect(controller.progress, closeTo(0.25, 0.001));

    // A deck asked past its own length must not report more than complete.
    await controller.answer(knewIt: true);
    await controller.answer(knewIt: true);
    await controller.answer(knewIt: true);
    expect(controller.progress, 1);
  });

  test('answering on a finished deck changes nothing', () async {
    final controller = build(count: 1);
    await controller.start();
    await controller.answer(knewIt: true);
    expect(controller.isFinished, isTrue);

    await controller.answer(knewIt: true);

    final stats = await harness.repository.stats('p');
    expect(stats.totalAttempts, 1);
    expect(controller.index, 1);
  });

  /// A card count below one is a deck of one rather than a deck of none.
  ///
  /// Same rule and same reason as `QuizController.questionCount`: a session
  /// shorter than one is not a session, and a division by zero in [progress] is
  /// worse than a single card.
  test('a card count below one is treated as a single card', () async {
    final controller = build(count: 0);
    await controller.start();

    expect(controller.total, 1);
    await controller.answer(knewIt: true);
    expect(controller.isFinished, isTrue);
    expect(controller.progress, 1);
  });

  test('an empty pack finishes immediately instead of throwing', () async {
    await harness.repository.importPack('{"schemaVersion":1,"packId":"empty",'
        '"title":"E","sourceLanguage":"en","targetLanguage":"ar","entries":[]}');
    final controller = FlashcardController(
      repository: harness.repository,
      packKey: 'empty',
      cardCount: 5,
      random: Random(1),
    );

    await controller.start();

    expect(controller.current, isNull);
    expect(controller.isFinished, isTrue);
    expect(controller.progress, 0);
  });

  /// An empty pack key is `HomeShell`'s start-up window, not a missing pack.
  ///
  /// Asking the repository about it would answer "no such pack" and turn a
  /// normal frame into an error state — the same reason `VocabRepository
  /// .favorites` short-circuits on an empty key.
  test('an empty pack key finishes immediately instead of throwing', () async {
    final controller = FlashcardController(
      repository: harness.repository,
      packKey: '',
      cardCount: 3,
      random: Random(1),
    );

    await controller.start();

    expect(controller.current, isNull);
    expect(controller.isFinished, isTrue);
  });

  /// Supplied words are dealt from, and the pack is not read again.
///
/// The screen reads the pack once to learn the deck's size and hands the words
/// in, so [FlashcardController.start] has no round trip left to make. **Half the
/// screen's database cost, and the reason `home_shell_test.dart`'s single
/// `settleDatabase` per destination is enough.**
test('deals from supplied words without reading the pack again', () async {
  final controller = FlashcardController(
    repository: harness.repository,
    packKey: 'p',
    cardCount: 2,
    random: Random(1),
    entries: _pack.entries,
  );

  await controller.start();

  expect(controller.current, isNotNull);
  expect(controller.current!.id, isNotEmpty);
  expect(controller.total, 2);
});

/// The two paths deal the same card from the same seed, so passing `entries`
/// changes the *round trips* and nothing about the deal.
test('supplied words deal exactly what reading the pack would have', () async {
  final fromPack = FlashcardController(
    repository: harness.repository,
    packKey: 'p',
    cardCount: 2,
    random: Random(4),
  );
  final fromEntries = FlashcardController(
    repository: harness.repository,
    packKey: 'p',
    cardCount: 2,
    random: Random(4),
    entries: _pack.entries,
  );

  await fromPack.start();
  await fromEntries.start();

  expect(fromEntries.current, fromPack.current);
  expect(fromEntries.isFinished, fromPack.isFinished);
  expect(fromEntries.progress, fromPack.progress);
});

/// An empty supplied list is an empty pack, not a reason to go and read one.
test('an empty supplied list finishes the deck without reading', () async {
  final controller = FlashcardController(
    repository: harness.repository,
    packKey: 'p',
    cardCount: 5,
    entries: const <VocabEntry>[],
  );

  await controller.start();

  expect(controller.current, isNull);
  expect(controller.isFinished, isTrue);
});

/// The `reveal()` twin of *answering on a finished deck changes nothing*.
///
/// `answer()` was pinned and `reveal()` was not, which left a gap in the one
/// state machine this task exists to get right. Both guards return before
/// mutating anything, and both are reachable: `reveal()` is bound to a `TextButton`
/// in the body, and the body's three cases mean the button is **not** on screen
/// before the first card is dealt or after the last one is answered — so a future
/// edit that leaves the button live in those states gets nothing instead of an
/// exception, and this is what says so.
test('revealing before the first card is dealt changes nothing', () async {
  final controller = build();

  await controller.reveal();

  expect(controller.revealed, isFalse);
  expect(controller.current, isNull);
  expect(controller.isFinished, isFalse);
  final stats = await harness.repository.stats('p');
  expect(stats.totalAttempts, 0);
});

test('revealing on a finished deck changes nothing', () async {
  final controller = build(count: 1);
  await controller.start();
  await controller.reveal();
  expect(controller.revealed, isTrue);

  await controller.answer(knewIt: true);
  expect(controller.isFinished, isTrue);

  await controller.reveal();

  // `_current` is null, so the guard returns without touching `_revealed`. A
  // missing guard here would leave the flag reading `true` on a deck with no
  // card, which is what the finished summary would then have to explain away.
  expect(controller.current, isNull);
  final stats = await harness.repository.stats('p');
  expect(stats.totalAttempts, 1);
});

/// A repository whose progress writes always fail.
///
/// **Why the guard is pinned this way and not by a teardown race.** The failure
/// the `try`/`on Object` in [FlashcardController.answer] exists for is a database
/// closed *underneath* a write still in flight — a **teardown ordering** race,
/// not a value. A first attempt at a test for it tapped «أعرف», deliberately did
/// not settle, unmounted, and then waited 200 ms of real time for the abandoned
/// write to land. **That test stayed green with the wrapper deleted**, because
/// the 200 ms was enough for the write to finish before anything closed: it was
/// a weak test, not a guard, and §9 calls that out as the fault of the test's own
/// design. Reproducing the real race needs teardown ordering this file cannot
/// control.
///
/// So the same code path is exercised with the timing removed: the write fails,
/// and [FlashcardController.answer] must still complete normally. `StateError` is
/// the type the real failure carries — a closed database is a bad *state*, not an
/// `Exception` — so the fixture would not catch an `on Exception` either.
test('a failing progress write does not fail the caller', () async {
  final controller = FlashcardController(
    repository: _FailingWriteRepository(harness.database),
    packKey: 'p',
    cardCount: 2,
    random: Random(1),
    entries: _pack.entries,
  );

  await controller.start();
  await controller.answer(knewIt: true);

  // The counters and the next card are settled *before* the write, so none of this
  // depends on it having succeeded — which is exactly why losing one progress row
  // is the whole of the cost.
  expect(controller.index, 1);
  expect(controller.knownCount, 1);
  expect(controller.current, isNotNull, reason: 'and the next card was dealt');

  // A second answer fails the same way, so the guard is not one-shot.
  await controller.answer(knewIt: false);
  expect(controller.isFinished, isTrue);
  expect(controller.index, 2);
});

test('notifies once per state change and never after dispose', () async {
    final controller = build();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.start();
    expect(notifications, 1, reason: 'the first card dealt');

    await controller.reveal();
    expect(notifications, 2, reason: 'the meaning shown');

    await controller.answer(knewIt: true);
    expect(notifications, 3, reason: 'the next card dealt');

    controller.dispose();
    // A disposed `ChangeNotifier` asserts on `notifyListeners()` in debug rather
    // than doing nothing, and the write behind the last answer is still in
    // flight when the screen is torn down. `docs/engineering-standards.md` §1 is
    // about claims that cannot fail; this is the check that the guard is real.
    await controller.answer(knewIt: true);
  });
}