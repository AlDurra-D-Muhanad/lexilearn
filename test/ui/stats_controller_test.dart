import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/stats_summary.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/stats/stats_controller.dart';

import '../helpers/test_env.dart';

/// Two packs that hold the **same entry ids**.
///
/// That is what makes pack scoping an assertion rather than a naming convention:
/// if a query forgot its `pack_key` filter, `p` and `other` would be
/// indistinguishable, so a test keyed on pack names alone could not tell the two
/// apart. Sharing ids means only the filter separates them.
const _pack = VocabPack(
  schemaVersion: 1,
  packId: 'p',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['ألف']),
    VocabEntry(id: 'b', term: 'beta', translations: <String>['بيتا']),
    VocabEntry(id: 'c', term: 'gamma', translations: <String>['جاما']),
  ],
);

const _otherPack = VocabPack(
  schemaVersion: 1,
  packId: 'other',
  title: 'English to Turkish',
  sourceLanguage: 'en',
  targetLanguage: 'tr',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['alfa']),
    VocabEntry(id: 'b', term: 'beta', translations: <String>['beta']),
    VocabEntry(id: 'c', term: 'gamma', translations: <String>['gama']),
  ],
);

void main() {
  late TestHarness harness;

  /// Two of the tests below close the harness themselves to force a read to
  /// fail, and `tearDown` must not close it a second time.
  var closed = false;

  setUp(() async {
    closed = false;
    harness = await TestHarness.create(packs: <VocabPack>[_pack, _otherPack]);
  });

  tearDown(() async {
    if (!closed) await harness.dispose();
  });

  /// Records one answer per id in [entries], all right.
  Future<void> answerAll(
    String packKey, {
    required List<String> entries,
    bool wasCorrect = true,
  }) async {
    for (final entryId in entries) {
      await harness.repository
          .recordAnswer(packKey: packKey, entryId: entryId, wasCorrect: wasCorrect);
    }
  }

  /// Closes the database underneath the repository, so the next read fails.
  Future<void> closeUnderneath() async {
    closed = true;
    await harness.dispose();
  }

  group('loading', () {
    test('starts empty and loading, then reports what the read found', () async {
      final controller =
          StatsController(repository: harness.repository, packKey: 'p');

      // The first frame the user sees is this one, so it has to be a real state
      // rather than a zeroed summary that reads as "you scored nothing".
      expect(controller.isLoading, isTrue);
      expect(controller.summary, same(StatsSummary.empty));
      expect(controller.error, isNull);

      await answerAll('p', entries: <String>['a', 'b']);
      await harness.repository.finishSession(
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 2,
        correctCount: 2,
      );

      await controller.load();

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.summary.totalAttempts, 2);
      expect(controller.summary.totalCorrect, 2);
      expect(controller.summary.wordsPracticed, 2);
      expect(controller.summary.recentSessions, hasLength(1));
    });

    test('a read that fails records the error rather than throwing', () async {
      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      // Closing the repository's own database is the only honest way to make a
      // read fail here: `VocabRepository` is a concrete class over a real
      // SQLite database, and a fake one would be testing the fake.
      await closeUnderneath();

      await expectLater(controller.load(), completes);

      expect(controller.error, isNotNull,
          reason: 'a failed read must not be indistinguishable from an empty pack');
      expect(controller.summary, same(StatsSummary.empty));
      expect(controller.isLoading, isFalse);
    });

    test('a load that lands after dispose does not throw', () async {
      // The read is fired from `initState`, so it is still in flight when a fast
      // tap on Back tears the route down. `ChangeNotifier` asserts on
      // `notifyListeners()` after `dispose()` rather than ignoring it — the same
      // trap `QuizController` and `SearchController` carry a guard for.
      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      final load = controller.load();
      controller.dispose();

      await expectLater(load, completes);
    });
  });

  group('pack scoping', () {
    test('the summary counts only the pack it was given', () async {
      await answerAll('p', entries: <String>['a']);
      await answerAll('other', entries: <String>['a', 'b', 'c']);
      await harness.repository.finishSession(
        packKey: 'other',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 3,
        correctCount: 3,
      );

      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      await controller.load();

      expect(controller.summary.totalAttempts, 1);
      expect(controller.summary.wordsPracticed, 1);
      // The other pack's session would otherwise sit under tiles that are all
      // counting this pack's one word.
      expect(controller.summary.recentSessions, isEmpty);
    });

    test('a reload after a reset reports the other pack untouched', () async {
      await answerAll('p', entries: <String>['a']);
      await answerAll('other', entries: <String>['a', 'b']);
      await harness.repository.finishSession(
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 1,
        correctCount: 1,
      );

      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      await controller.load();
      expect(controller.summary.isEmpty, isFalse);

      await controller.reset();

      expect(controller.summary.isEmpty, isTrue,
          reason: 'reset must clear this pack\u2019s word progress');
      expect(controller.summary.recentSessions, isEmpty,
          reason: 'reset must clear this pack\u2019s session history too');

      final other = await harness.repository.stats('other');
      expect(other.totalAttempts, 2,
          reason: 'reset cleared a pack it was not asked about');
    });
  });

  group('reset', () {
    test('clears word progress and session history in one call', () async {
      // Ruling 5: `resetProgress` clears *both* tables, because a pack left with
      // zeroed word counts and a full "recent sessions" list reads to the user
      // exactly like Reset did nothing.
      await answerAll('p', entries: <String>['a', 'b', 'c']);
      await harness.repository.finishSession(
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 9),
        totalQuestions: 3,
        correctCount: 2,
      );

      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      await controller.load();
      await controller.reset();

      // Field by field rather than `same(StatsSummary.empty)`: that identity only
      // holds before the *first* read, because `VocabRepository.stats` builds a
      // fresh instance. `isEmpty` and `recentSessions.isEmpty` are the two claims
      // this test is actually making — everything else was asserted before the
      // reset.
      expect(controller.summary.isEmpty, isTrue);
      expect(controller.summary.totalAttempts, 0);
      expect(controller.summary.recentSessions, isEmpty);
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
    });

    test('a reset that fails records the error and leaves the summary alone',
        () async {
      await answerAll('p', entries: <String>['a']);
      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      await controller.load();
      await closeUnderneath();

      await expectLater(controller.reset(), completes);

      expect(controller.error, isNotNull);
      // The last thing the screen rendered is still what it renders: a failed
      // reset must not blank the numbers the user was looking at.
      expect(controller.summary.totalAttempts, 1);
      expect(controller.isLoading, isFalse);
    });
  });
}