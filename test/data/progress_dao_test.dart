import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/progress_dao.dart';
import 'package:lexilearn/data/session_dao.dart';
import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ProgressDao progress;
  late SessionDao sessions;
  final first = DateTime.utc(2026, 10, 14, 9);
  final second = DateTime.utc(2026, 10, 14, 10);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await openAppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    progress = ProgressDao(db);
    sessions = SessionDao(db);
  });

  tearDown(() => db.close());

  test('first answer creates a row', () async {
    await progress.record(
        packKey: 'p', entryId: 'a', wasCorrect: true, at: first);
    final stored = await progress.get(packKey: 'p', entryId: 'a');
    expect(stored!.attempts, 1);
    expect(stored.correct, 1);
    expect(stored.lastSeenAt, first);
  });

  test('later answers accumulate on the same row', () async {
    await progress.record(packKey: 'p', entryId: 'a', wasCorrect: true, at: first);
    await progress.record(packKey: 'p', entryId: 'a', wasCorrect: false, at: second);

    // Parenthesised on purpose. Written as `await progress.get(...)!` the `!`
    // binds to the non-nullable Future, not to the awaited `WordProgress?`, so
    // the four assertions below fail to compile.
    final stored = (await progress.get(packKey: 'p', entryId: 'a'))!;
    expect(stored.attempts, 2);
    expect(stored.correct, 1);
    expect(stored.accuracy, 0.5);
    expect(stored.lastSeenAt, second);
  });

  test('progress is scoped per pack for the same entry id', () async {
    await progress.record(packKey: 'p1', entryId: 'a', wasCorrect: true, at: first);
    await progress.record(packKey: 'p2', entryId: 'a', wasCorrect: false, at: first);

    expect((await progress.get(packKey: 'p1', entryId: 'a'))!.correct, 1);
    expect((await progress.get(packKey: 'p2', entryId: 'a'))!.correct, 0);
  });

  test('get returns null for an unanswered word', () async {
    expect(await progress.get(packKey: 'p', entryId: 'zzz'), isNull);
  });

  test('reset clears a pack and leaves other packs alone', () async {
    await progress.record(packKey: 'p1', entryId: 'a', wasCorrect: true, at: first);
    await progress.record(packKey: 'p2', entryId: 'a', wasCorrect: true, at: first);

    expect(await progress.reset('p1'), 1);
    expect(await progress.allForPack('p1'), isEmpty);
    expect(await progress.allForPack('p2'), hasLength(1));
  });

  test('concurrent records never lose an attempt', () async {
    // Guards the atomicity claim on `ProgressDao.record`. Rewritten as
    // get-then-write, these twenty interleaved calls leave `attempts` short of
    // 20 — silently, and with every other test in the suite still green.
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 20; i++)
        progress.record(packKey: 'p', entryId: 'a', wasCorrect: i.isEven, at: first),
    ]);
    final stored = (await progress.get(packKey: 'p', entryId: 'a'))!;
    expect(stored.attempts, 20);
    expect(stored.correct, 10);
  });

  test('sessions are stored newest first and limited', () async {
    for (var i = 0; i < 15; i++) {
      await sessions.insert(QuizSessionResult(
        packKey: 'p',
        startedAt: first.add(Duration(minutes: i)),
        totalQuestions: 10,
        correctCount: i,
      ));
    }

    final recent = await sessions.recent(limit: 5);
    expect(recent, hasLength(5));
    expect(recent.first.correctCount, 14);
    expect(recent.last.correctCount, 10);
  });

  test('recent with no limit argument caps at ten and spans every pack',
      () async {
    // A bare `recent()` is the backup's call: a backup legitimately carries
    // every session, so no `packKey` must mean "do not filter".
    for (var i = 0; i < 12; i++) {
      await sessions.insert(QuizSessionResult(
        packKey: i.isEven ? 'p1' : 'p2',
        startedAt: first.add(Duration(minutes: i)),
        totalQuestions: 10,
        correctCount: i,
      ));
    }

    final byDefault = await sessions.recent();
    expect(byDefault, hasLength(10));
    expect(byDefault.first.correctCount, 11);
    expect(byDefault.last.correctCount, 2);
    expect(byDefault.map((s) => s.packKey).toSet(), <String>{'p1', 'p2'});
  });
}
