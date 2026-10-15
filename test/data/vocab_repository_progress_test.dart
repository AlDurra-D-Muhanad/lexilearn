import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/progress_dao.dart';
import 'package:lexilearn/domain/stats_summary.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import '../helpers/test_env.dart';

VocabPack _pack(String id, List<String> terms) => VocabPack(
      schemaVersion: 1,
      packId: id,
      title: id,
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: <VocabEntry>[
        for (final term in terms)
          VocabEntry(id: '$id-$term', term: term, translations: <String>['t']),
      ],
    );

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[
      _pack('en_ar', <String>['alpha', 'beta', 'gamma']),
      _pack('other', <String>['alpha']),
    ]);
  });

  tearDown(() => harness.dispose());

  test('recordAnswer stamps lastSeenAt from the injected clock, not the wall',
      () async {
    // Pinned far from the wall clock, for the reason Task 5 pinned importPack:
    // a progress write that fell back to DateTime.now() would look correct in
    // the app and silently break every timestamp-dependent test here.
    final pinned = DateTime.utc(2031, 3, 4, 5, 6, 7);
    final fresh = await TestHarness.create(now: pinned);
    addTearDown(fresh.dispose);

    await fresh.repository.recordAnswer(
        packKey: 'p', entryId: 'a', wasCorrect: true);

    final stored =
        await ProgressDao(fresh.database).get(packKey: 'p', entryId: 'a');
    expect(stored, isNotNull);
    expect(stored!.lastSeenAt, pinned);
  });

  test('recordAnswer accumulates attempts and correct answers', () async {
    final dao = ProgressDao(harness.database);
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'en_ar-alpha', wasCorrect: true);
    await harness.repository.recordAnswer(
        packKey: 'en_ar', entryId: 'en_ar-alpha', wasCorrect: false);

    final stored = await dao.get(packKey: 'en_ar', entryId: 'en_ar-alpha');
    expect(stored!.attempts, 2);
    expect(stored.correct, 1);
  });

  test('recordAnswer keeps two packs independent for the same entry id',
      () async {
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'shared', wasCorrect: true);
    await harness.repository
        .recordAnswer(packKey: 'other', entryId: 'shared', wasCorrect: false);

    expect((await harness.repository.stats('en_ar')).totalCorrect, 1);
    expect((await harness.repository.stats('other')).totalCorrect, 0);
    expect((await harness.repository.stats('other')).totalAttempts, 1);
  });

  test('finishSession stores the session and stats reports it newest first',
      () async {
    final started = DateTime.utc(2026, 10, 14, 9);
    final id = await harness.repository.finishSession(
      packKey: 'en_ar',
      startedAt: started,
      totalQuestions: 10,
      correctCount: 7,
    );
    await harness.repository.finishSession(
      packKey: 'en_ar',
      startedAt: started.add(const Duration(minutes: 5)),
      totalQuestions: 10,
      correctCount: 4,
    );

    expect(id, greaterThan(0));

    final stats = await harness.repository.stats('en_ar');
    expect(stats.recentSessions, hasLength(2));
    expect(stats.recentSessions.first.correctCount, 4);
    expect(stats.recentSessions.first.startedAt,
        started.add(const Duration(minutes: 5)));
    expect(stats.recentSessions.last.correctCount, 7);
    expect(stats.recentSessions.first.accuracy, 0.4);
  });

  test('stats aggregates attempts, correct, practiced, and mastered words',
      () async {
    // alpha: 5/5 correct -> mastered.
    for (var i = 0; i < 5; i++) {
      await harness.repository.recordAnswer(
          packKey: 'en_ar', entryId: 'en_ar-alpha', wasCorrect: true);
    }
    // beta: 2 attempts, 1 correct -> practiced, not mastered.
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'en_ar-beta', wasCorrect: true);
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'en_ar-beta', wasCorrect: false);

    final stats = await harness.repository.stats('en_ar');
    expect(stats.totalAttempts, 7);
    expect(stats.totalCorrect, 6);
    expect(stats.wordsPracticed, 2);
    expect(stats.wordsMastered, 1);
    expect(stats.accuracy, closeTo(6 / 7, 1e-9));
    expect(stats.isEmpty, isFalse);
  });

  test('stats for a pack with nothing recorded is empty', () async {
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'en_ar-alpha', wasCorrect: true);

    final stats = await harness.repository.stats('other');
    expect(stats.isEmpty, isTrue);
    expect(stats.totalAttempts, 0);
    expect(stats.totalCorrect, 0);
    expect(stats.wordsPracticed, 0);
    expect(stats.wordsMastered, 0);
    expect(stats.accuracy, 0);
  });

  test('StatsSummary.empty is the zeroed summary', () {
    expect(StatsSummary.empty.isEmpty, isTrue);
    expect(StatsSummary.empty.totalAttempts, 0);
    expect(StatsSummary.empty.recentSessions, isEmpty);
  });

  test('resetProgress clears only the named pack', () async {
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'shared', wasCorrect: true);
    await harness.repository
        .recordAnswer(packKey: 'other', entryId: 'shared', wasCorrect: true);

    expect(await harness.repository.resetProgress('en_ar'), 1);
    expect((await harness.repository.stats('en_ar')).isEmpty, isTrue);
    expect((await harness.repository.stats('other')).totalAttempts, 1);
  });

  test('stats for one pack never lists another pack\'s sessions', () async {
    // Every counter in StatsSummary is pack-scoped; the session list has to be
    // too, or the Stats screen shows a user a session they played elsewhere.
    final started = DateTime.utc(2026, 10, 14, 9);
    await harness.repository.finishSession(
      packKey: 'en_ar',
      startedAt: started,
      totalQuestions: 10,
      correctCount: 7,
    );
    await harness.repository.finishSession(
      packKey: 'other',
      startedAt: started,
      totalQuestions: 10,
      correctCount: 4,
    );

    final scoped = await harness.repository.stats('en_ar');
    expect(scoped.recentSessions, hasLength(1));
    expect(scoped.recentSessions.single.packKey, 'en_ar');
    expect(scoped.recentSessions.single.correctCount, 7);
  });

  test('resetProgress clears the pack\'s sessions as well as its progress',
      () async {
    // Otherwise Reset is a lie: the tiles go to zero, the screen says "no
    // answers yet", and the list underneath still shows every old session.
    final started = DateTime.utc(2026, 10, 14, 9);
    await harness.repository
        .recordAnswer(packKey: 'en_ar', entryId: 'shared', wasCorrect: true);
    await harness.repository.finishSession(
      packKey: 'en_ar',
      startedAt: started,
      totalQuestions: 10,
      correctCount: 7,
    );
    await harness.repository.finishSession(
      packKey: 'other',
      startedAt: started,
      totalQuestions: 10,
      correctCount: 4,
    );

    expect(await harness.repository.resetProgress('en_ar'), 1);

    final stats = await harness.repository.stats('en_ar');
    expect(stats.isEmpty, isTrue);
    expect(stats.recentSessions, isEmpty);
    // The other pack's history is untouched.
    expect((await harness.repository.stats('other')).recentSessions,
        hasLength(1));
  });
}
