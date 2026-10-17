import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/backup_codec.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import '../helpers/test_env.dart';

/// Everything the repository exposes, flattened to plain values that two
/// snapshots can be compared with `expect`.
///
/// The fields are projected explicitly rather than comparing the objects
/// directly, because `PackSummary` does not implement `operator ==` — two
/// identical summaries compare unequal by identity, which would make this
/// helper report a change on every single call.
///
/// Takes the harness rather than a `VocabRepository` so this file needs no
/// import of the type under test.
Future<List<Object?>> _snapshot(TestHarness harness) async {
  final seen = <Object?>[];
  for (final summary in await harness.repository.packs()) {
    seen.add(<Object?>[
      'pack',
      summary.packKey,
      summary.title,
      summary.sourceLanguage,
      summary.targetLanguage,
      summary.entryCount,
      summary.isBundled,
      summary.importedAt.toUtc().toIso8601String(),
    ]);
    for (final entry in await harness.repository.entries(summary.packKey)) {
      seen.add(<Object?>[
        'entry',
        entry.id,
        entry.term,
        entry.translations,
        entry.note,
        entry.phonetic,
        entry.partOfSpeech,
        entry.synonyms,
        entry.examples,
      ]);
    }
  }
  return seen;
}

/// The raw `word_progress` rows.
///
/// Read directly rather than through `stats`, because the rollback test below
/// drops the `quiz_sessions` table and `stats()` reads sessions on its way to
/// building `StatsSummary` — asking it afterwards would fail on the missing
/// table instead of reporting what the restore did. The plan's version of that
/// test did exactly this and failed with `no such table: quiz_sessions`.
///
/// Taking the harness rather than the repository keeps this file free of an
/// import of the type under test, like [_snapshot].
Future<List<Map<String, Object?>>> _progressRows(TestHarness harness) =>
    harness.database.query('word_progress');

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[
      VocabPack(
        schemaVersion: 1,
        packId: 'en_ar',
        title: 'English to Arabic',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: const <VocabEntry>[
          VocabEntry(id: 'fever-1', term: 'fever', translations: <String>['حمى']),
          VocabEntry(
              id: 'buried-1', term: 'Buried', translations: <String>['دفن', 'مدفون']),
          VocabEntry(id: 'checkup-1', term: 'checkup', translations: <String>['فحص']),
          VocabEntry(
              id: 'multi-1', term: 'multi   space', translations: <String>['مسافة']),
        ],
      ),
    ]);
  });

  tearDown(() => harness.dispose());

  test('returns every entry for an empty query', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: '   ');
    expect(results, hasLength(4));
  });

  test('matches an English term case-insensitively', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: 'BURI');
    expect(results.single.term, 'Buried');
  });

  test('matches a substring in the middle of a term', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: 'heck');
    expect(results.single.term, 'checkup');
  });

  test('matches an Arabic translation', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: 'مدفون');
    expect(results.single.term, 'Buried');
  });

  test('matches across a run of internal whitespace in the term', () async {
    // 'multi   space' is stored verbatim. Both a single-space query and a
    // differently-cased multi-space query must reach it, which only holds if
    // whitespace is collapsed on both sides before comparison.
    expect(
        await harness.repository.search(packKey: 'en_ar', query: 'multi space'),
        hasLength(1));
    expect(
        await harness.repository
            .search(packKey: 'en_ar', query: 'MULTI   SPACE'),
        hasLength(1));
  });

  test('returns nothing when no entry matches', () async {
    expect(await harness.repository.search(packKey: 'en_ar', query: 'zzzz'), isEmpty);
  });

  test('imports a pack and makes it searchable', () async {
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'imported',
      title: 'Imported',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'extra-1', term: 'lantern', translations: <String>['فانوس']),
      ],
    ));

    final pack = await harness.repository.importPack(json);
    expect(pack.packId, 'imported');
    expect((await harness.repository.packs()).map((p) => p.packKey),
        contains('imported'));
    expect(await harness.repository.search(packKey: 'imported', query: 'lant'),
        hasLength(1));
  });

  test('every rejected document leaves the database byte-for-byte unchanged',
      () async {
    // Every one of these parses as JSON and is rejected only by the *strict*
    // pack decode. That is the point: a document that dies inside jsonDecode
    // proves nothing about ordering, because no implementation could have
    // written anything before it failed. These fail after parsing, so an
    // implementation that writes a placeholder row before the strict decode
    // gets caught here.
    const rejected = <String, String>{
      'not JSON at all': '{ not json',
      'unsupported schemaVersion':
          '{"schemaVersion":99,"packId":"ghost","title":"t","entries":[]}',
      'a backup document':
          '{"kind":"backup","schemaVersion":1,"packId":"ghost","title":"t","entries":[]}',
      'a missing entries list': '{"schemaVersion":1,"packId":"ghost","title":"t"}',
      'two entries sharing an id':
          '{"schemaVersion":1,"packId":"ghost","title":"t","entries":['
              '{"id":"dup","term":"A","translations":["x"]},'
              '{"id":"dup","term":"B","translations":["y"]}]}',
      'an empty term':
          '{"schemaVersion":1,"packId":"ghost","title":"t","entries":['
              '{"id":"g1","term":"  ","translations":["x"]}]}',
      'a non-string translation':
          '{"schemaVersion":1,"packId":"ghost","title":"t","entries":['
              '{"id":"g1","term":"A","translations":[7]}]}',
    };

    // The fixture pack has four entries, so the entries half of the snapshot is
    // non-empty and a clobbered entry row would actually be visible.
    expect(await harness.repository.entries('en_ar'), hasLength(4));

    for (final document in rejected.entries) {
      final before = await _snapshot(harness);

      await expectLater(
        harness.repository.importPack(document.value),
        throwsA(isA<PackDecodeException>()),
        reason: '"${document.key}" must be rejected',
      );

      expect(await _snapshot(harness), before,
          reason: 'a failed import of "${document.key}" changed the database');
    }
  });

  test('exportPackJson round-trips through importPack', () async {
    final json = await harness.repository.exportPackJson('en_ar');
    await harness.repository.importPack(json);
    expect(await harness.repository.entries('en_ar'), hasLength(4));
  });

  test('exportPackJson throws a readable error for an unknown pack', () async {
    await expectLater(harness.repository.exportPackJson('nope'),
        throwsA(isA<PackDecodeException>()));
  });

  test('deletePack removes the pack and its entries', () async {
    await harness.repository.deletePack('en_ar');
    expect(await harness.repository.packs(), isEmpty);
    expect(await harness.repository.entries('en_ar'), isEmpty);
  });

  // --- Beyond the brief: interface surface the brief's tests do not reach. ---

  test('a bidi control character on either side does not block a match', () async {
    // The source dataset really does contain bidi marks, and the plan's global
    // rule strips them on ingest. Either way a user pasting text out of a
    // rich-text editor must still find the word.
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'bidi',
      title: 'Bidi',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'bidi-1', term: 'serenity', translations: <String>['الهدوء\u200f']),
      ],
    ));
    await harness.repository.importPack(json);

    expect(await harness.repository.search(packKey: 'bidi', query: 'الهدوء'),
        hasLength(1));
    expect(
        await harness.repository.search(packKey: 'bidi', query: 'الهدوء\u200e'),
        hasLength(1));
  });

  test('invisible marks never block a match on either side', () async {
    // U+061C ARABIC LETTER MARK is the one most likely to appear in Arabic text
    // pasted out of a rich-text editor; the zero-width family rides with it.
    // Each mark is embedded in its own entry, so every entry normalises to the
    // same clean text and a clean query must reach all of them.
    const marks = <String>['\u061c', '\u200b', '\u200c', '\u200d', '\ufeff'];
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'marks',
      title: 'Marks',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: <VocabEntry>[
        for (var i = 0; i < marks.length; i++)
          VocabEntry(
            id: 'mark-$i',
            term: 'mark${marks[i]}ed',
            translations: <String>['تع${marks[i]}ريب'],
          ),
      ],
    ));
    await harness.repository.importPack(json);

    for (final mark in marks) {
      final label = 'U+${mark.codeUnitAt(0).toRadixString(16).toUpperCase()}';
      expect(await harness.repository.search(packKey: 'marks', query: 'marked'),
          hasLength(marks.length), reason: '$label inside the term');
      expect(await harness.repository.search(packKey: 'marks', query: 'تعريب'),
          hasLength(marks.length), reason: '$label inside the translation');
    }
  });

  test('importPack stamps importedAt from the injected clock, not the wall',
      () async {
    // Task 7 records progress against the same clock. If importPack ever falls
    // back to DateTime.now(), that pinning breaks silently.
    final pinned = DateTime.utc(2031, 3, 4, 5, 6, 7);
    final fresh = await TestHarness.create(now: pinned);
    addTearDown(fresh.dispose);

    await fresh.repository.importPack(PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'timed',
      title: 'Timed',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'timed-1', term: 'a', translations: <String>['b']),
      ],
    )));

    expect((await fresh.repository.packs()).single.importedAt, pinned);
  });

  test('three harnesses live at the same time do not share a database',
      () async {
    // Guards the harness itself: the harnesses open `:memory:` with
    // `singleInstance: false`. Left at the default, sqflite keys its
    // open-database helper by path and would hand every harness in this isolate
    // the *same* database — each one created successfully and silently wrong.
    final second = await TestHarness.create();
    addTearDown(second.dispose);
    final third = await TestHarness.create();
    addTearDown(third.dispose);

    for (final empty in <TestHarness>[second, third]) {
      expect(await empty.repository.packs(), isEmpty);
      expect(await empty.repository.entries('en_ar'), isEmpty);
    }

    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'only_in_second',
      title: 'Only In Second',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'only-1', term: 'lantern', translations: <String>['فانوس']),
      ],
    ));
    await second.repository.importPack(json);

    expect((await second.repository.packs()).map((p) => p.packKey),
        <String>['only_in_second']);
    expect((await third.repository.packs()), isEmpty);
    expect((await harness.repository.packs()).map((p) => p.packKey),
        <String>['en_ar']);
  });

  test('seedBundledPack installs the bundled pack once and marks it bundled',
      () async {
    // Pinned far from the wall clock: the default harness clock sits close to
    // real time, which is exactly why a seeding path that ignored it went
    // unnoticed.
    final pinned = DateTime.utc(2031, 3, 4, 5, 6, 7);
    final fresh = await TestHarness.create(now: pinned);
    addTearDown(fresh.dispose);
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'english_ar_v1',
      title: 'English to Arabic',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'x-1', term: 'fever', translations: <String>['حمى']),
        VocabEntry(id: 'x-2', term: 'checkup', translations: <String>['فحص']),
      ],
    ));

    expect(await fresh.repository.seedBundledPack(json), isTrue);
    expect(await fresh.repository.seedBundledPack(json), isFalse);

    final summary = (await fresh.repository.packs()).single;
    expect(summary.packKey, 'english_ar_v1');
    expect(summary.isBundled, isTrue);
    expect(summary.entryCount, 2);
    expect(summary.importedAt, pinned);
  });

  test('seedBundledPack rejects a corrupt asset without writing anything',
      () async {
    final before = await _snapshot(harness);
    await expectLater(
        harness.repository.seedBundledPack('{"schemaVersion":99,"packId":"g",'
            '"title":"t","entries":[]}'),
        throwsA(isA<PackDecodeException>()));
    expect(await _snapshot(harness), before);
  });

  // --- backup: export, restore, and the transaction that has to be real -------

  /// A second pack, so "every pack" is a claim the tests can actually make.
  ///
  /// It holds the **same entry ids** as `en_ar`, which is the only thing that
  /// can tell two packs' progress rows apart once they are in the same file.
  const VocabPack secondPack = VocabPack(
    schemaVersion: 1,
    packId: 'en_tr',
    title: 'English to Turkish',
    sourceLanguage: 'en',
    targetLanguage: 'tr',
    entries: <VocabEntry>[
      VocabEntry(id: 'fever-1', term: 'fever', translations: <String>['ateş']),
      VocabEntry(
        id: 'buried-1',
        term: 'Buried',
        translations: <String>['gömülü'],
        note: 'a note the brief never writes',
        phonetic: '/ˈbʌrid/',
        partOfSpeech: 'adjective',
        synonyms: <String>['interred'],
        examples: <String>['a buried city'],
      ),
    ],
  );

  Future<TestHarness> twoPackHarness() async {
    final two = await TestHarness.create(packs: const <VocabPack>[
      VocabPack(
        schemaVersion: 1,
        packId: 'en_ar',
        title: 'English to Arabic',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: <VocabEntry>[
          VocabEntry(id: 'fever-1', term: 'fever', translations: <String>['حمى']),
        ],
      ),
      secondPack,
    ]);
    addTearDown(two.dispose);
    return two;
  }

  test('a backup round-trips every pack and its progress', () async {
    await harness.repository.recordAnswer(
        packKey: 'en_ar', entryId: 'fever-1', wasCorrect: true);
    final json = await harness.repository.exportBackupJson();

    final fresh = await TestHarness.create();
    addTearDown(fresh.dispose);
    final restored = await fresh.repository.importBackupJson(json);

    expect(restored, 1);
    expect((await fresh.repository.packs()).map((p) => p.packKey), <String>['en_ar']);
    final stats = await fresh.repository.stats('en_ar');
    expect(stats.totalAttempts, 1);
    expect(stats.totalCorrect, 1);
  });

  test('a backup carries every pack, not only the one the shell is showing',
      () async {
    // `word_progress` is keyed on `(pack_key, entry_id)` and the repository has
    // no notion of an "active" pack, so a backup that gathered one pack's rows
    // and stopped would restore a second phone with one pack and no way to tell.
    final two = await twoPackHarness();
    await two.repository.recordAnswer(
        packKey: 'en_tr', entryId: 'fever-1', wasCorrect: true);

    final json = await two.repository.exportBackupJson();
    final fresh = await TestHarness.create();
    addTearDown(fresh.dispose);
    expect(await fresh.repository.importBackupJson(json), 2);

    expect((await fresh.repository.packs()).map((p) => p.packKey),
        containsAll(<String>['en_ar', 'en_tr']));
    // The entry ids are identical across the two packs, so only the `pack_key`
    // filter can attribute this row.
    expect((await fresh.repository.stats('en_tr')).totalAttempts, 1);
    expect((await fresh.repository.stats('en_ar')).totalAttempts, 0);
  });

  test('a restored entry keeps the fields a hand-written backup can carry',
      () async {
    // `en_tr` is built with a note, a phonetic, a part of speech, a synonym and
    // an example — none of which the bundled dataset populates. They survive the
    // SQLite columns only if the codec wrote them, the DAO stored them and the
    // restore put them back.
    final two = await twoPackHarness();
    final json = await two.repository.exportBackupJson();
    final fresh = await TestHarness.create();
    addTearDown(fresh.dispose);
    await fresh.repository.importBackupJson(json);

    final entries = await fresh.repository.entries('en_tr');
    final buried = entries.firstWhere((entry) => entry.id == 'buried-1');
    expect(buried.term, 'Buried');
    expect(buried.translations, <String>['gömülü']);
    expect(buried.note, 'a note the brief never writes');
    expect(buried.phonetic, '/ˈbʌrid/');
    expect(buried.partOfSpeech, 'adjective');
    expect(buried.synonyms, <String>['interred']);
    expect(buried.examples, <String>['a buried city']);
  });

  test('a backup round-trips the session history', () async {
    await harness.repository.recordAnswer(
        packKey: 'en_ar', entryId: 'fever-1', wasCorrect: true);
    await harness.repository.finishSession(
      packKey: 'en_ar',
      startedAt: DateTime.utc(2026, 10, 14, 9),
      totalQuestions: 4,
      correctCount: 3,
    );

    final json = await harness.repository.exportBackupJson();
    final fresh = await TestHarness.create();
    addTearDown(fresh.dispose);
    await fresh.repository.importBackupJson(json);

    final sessions = (await fresh.repository.stats('en_ar')).recentSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.totalQuestions, 4);
    expect(sessions.single.correctCount, 3);
    expect(sessions.single.startedAt.toUtc(), DateTime.utc(2026, 10, 14, 9));
  });

  test('importing a backup replaces progress rather than doubling it',
      () async {
    await harness.repository.recordAnswer(
        packKey: 'en_ar', entryId: 'fever-1', wasCorrect: true);
    final json = await harness.repository.exportBackupJson();

    await harness.repository.importBackupJson(json);
    expect((await harness.repository.stats('en_ar')).totalAttempts, 1);

    // And again, because `replace` writes an absolute value while `record`
    // increments: restoring twice must be idempotent, or a user who restores
    // onto a phone that already has the data watches their accuracy halve.
    await harness.repository.importBackupJson(json);
    expect((await harness.repository.stats('en_ar')).totalAttempts, 1);
  });

  test('restore removes the packs that were on the device but not in the file',
      () async {
    final two = await twoPackHarness();
    final json = await two.repository.exportPackJson('en_ar');
    // A file carrying only `en_ar`: `en_tr` is on the device and not in the
    // backup, so restoring must not silently keep it alongside a document that
    // does not mention it.
    final backup = '{"kind":"backup","schemaVersion":1,'
        '"exportedAt":"2026-10-14T12:00:00.000Z","packs":[$json],'
        '"progress":[],"sessions":[]}';

    expect(await two.repository.importBackupJson(backup), 1);
    expect((await two.repository.packs()).map((p) => p.packKey), <String>['en_ar']);
  });

  test('a malformed backup is rejected and changes nothing', () async {
    final before = await _snapshot(harness);
    await expectLater(
        harness.repository.importBackupJson('nope'), throwsA(isA<PackDecodeException>()));
    expect(await _snapshot(harness), before);
  });

  test('a plain pack document is refused by the restore path too', () async {
    // The mirror image of `importPack refuses a backup document`: both files are
    // `.json` and a user may hand either one to either action, so each has to
    // refuse the other's shape with a sentence that names the alternative.
    final before = await _snapshot(harness);
    await expectLater(
      harness.repository.importBackupJson(await harness.repository.exportPackJson('en_ar')),
      throwsA(isA<PackDecodeException>().having(
        (e) => e.message,
        'message',
        contains('vocabulary pack'),
      )),
    );
    expect(await _snapshot(harness), before);
  });

  test('importPack refuses a backup document', () async {
    final json = await harness.repository.exportBackupJson();
    await expectLater(
        harness.repository.importPack(json), throwsA(isA<PackDecodeException>()));
  });

  test('a failure mid-restore rolls back rather than half-applying', () async {
    // Proves the transaction is real: drop the table the SECOND delete in the
    // loop targets, so the failure happens *after* `_progress.reset` has already
    // run inside the transaction. If `_progress.reset` had not been on the same
    // transaction it would not have committed early either — it would have
    // **waited**, on the lock `transaction()` holds (`database_mixin.dart:496`,
    // waited on at `:549-592`), so the restore would have hung and failed the
    // guard-timeout test instead of rolling back. The half-applied device this
    // test rules out is the other ordering: `deletePack` alone, committing its
    // deletes with no transaction around them. See
    // `docs/engineering-standards.md` §3.
    await harness.repository.recordAnswer(
        packKey: 'en_ar', entryId: 'fever-1', wasCorrect: true);
    final packsBefore = await _snapshot(harness);
    final progressBefore = await _progressRows(harness);
    expect(progressBefore, hasLength(1));

    final json = await harness.repository.exportBackupJson();
    await harness.database.execute('DROP TABLE quiz_sessions');

    await expectLater(
        harness.repository.importBackupJson(json), throwsA(anything));

    expect(await _progressRows(harness), progressBefore,
        reason: 'the progress rows the restore had already deleted were restored');
    expect(await _snapshot(harness), packsBefore,
        reason: 'the pack the restore had already deleted is back');
  });

  test('a backup of a device with no packs at all restores to no packs',
      () async {
    final empty = await TestHarness.create();
    addTearDown(empty.dispose);

    final json = await empty.repository.exportBackupJson();
    expect(await empty.repository.importBackupJson(json), 0);
    expect(await empty.repository.packs(), isEmpty);
  });

  test('exportBackupJson stamps the injected clock, not the wall', () async {
    // Same pinning as `importPack stamps importedAt from the injected clock`.
    // Without it a golden or a diff of two exports would be unreproducible.
    final pinned = DateTime.utc(2031, 3, 4, 5, 6, 7);
    final fresh = await TestHarness.create(now: pinned);
    addTearDown(fresh.dispose);

    final document = BackupCodec.decode(await fresh.repository.exportBackupJson());
    expect(document.exportedAt, pinned);
  });

  test('restore completes inside five seconds — the executor: txn guard',
      () async {
    // **This is the guard for `docs/engineering-standards.md` §3, and it exists
    // because the failure it catches is a hang, not an error.**
    //
    // `importBackupJson` makes seven DAO calls inside one `transaction()`. A call
    // made **without** that transaction's handle does not fail and does not
    // return: it waits. Read out of `sqflite_common-2.5.14`, not assumed:
    //
    // * `database_mixin.dart:894-902` — `transaction()` wraps its whole body in
    //   `txnWriteSynchronized`, which takes `_rawLock`, a **Dart-side
    //   non-reentrant `Lock` declared at `:496`**.
    // * `database_mixin.dart:549-592` — `txnSynchronized` runs immediately when
    //   `txn != null`; otherwise it queues on `_rawLock.synchronized(…)`. The
    //   comment above it reads *"synchronized call to the database / not
    //   re-entrant"*.
    // * after `utils.lockWarningDuration` — **10 seconds**,
    //   `constant.dart:174` — `utils.dart:43-49` prints
    //   `Warning database has been locked for … Make sure you always use the
    //   transaction object for database operations during a transaction`.
    // * `sqflite_common_ffi-2.4.4/lib/src/sqflite_ffi_impl.dart:275-315` —
    //   `handleTransactionId`, whose own doc comment is *"If a transaction is in
    //   progress and we are not in it, queue for later"*: a statement issued with
    //   no transaction id is parked in `_noTransactionHandlerQueue` and only run
    //   by `_runQueuedHandlers()` once the transaction closes.
    //
    // **It is the same `Database` object, not a second connection, and nothing
    // here is about SQLite taking a file lock.** `database_mixin.dart:423` opens
    // with `BEGIN IMMEDIATE`, not a deferred `BEGIN`, and the block does not
    // depend on whether any rows exist — the *first* call inside the transaction
    // blocks whether it reads or writes and whether the table is empty. (Both of
    // those were the wrong story in the first draft of this comment; see §Fix
    // round 1 of the report.)
    //
    // So an ordinary `expectLater(…, completes)` would sit there until the
    // ten-minute test timeout and CI would report a suite that simply stopped,
    // with nothing pointing at the cause. Bounding the future with `.timeout`
    // converts the hang into a red test naming the restore. Measured by dropping
    // one argument at a time: every one of the seven fails at exactly 5.0 s with
    // `TimeoutException after 0:00:05.000000: Future not completed`, and sqflite
    // prints its own `Warning database has been locked` twice behind it.
    //
    // **What the fixture is actually for, measured rather than asserted.** Three
    // of the seven are only *reached* at all if the file carries what they
    // iterate, and reaching them is the whole point — an unreached call is
    // silently uncovered, not red. Dropping each argument against a fixture with
    // **zero** progress rows and **zero** sessions gives:
    //
    // | site | reached by | caught with an empty fixture? |
    // |---|---|---|
    // | 1 `listPacks` | the device having ≥1 pack | yes |
    // | 2 `progress.reset` | the device having ≥1 pack | yes |
    // | 3 `sessions.deleteForPack` | the device having ≥1 pack | yes |
    // | 4 `packs.deletePack` | the device having ≥1 pack | yes |
    // | 5 `packs.insertPack` | the file having ≥1 pack | yes (1 is enough) |
    // | 6 `progress.replace` | the file having ≥1 **progress row** | **no — missed** |
    // | 7 `sessions.insert` | the file having ≥1 **session** | **no — missed** |
    //
    // So the progress row and the session are load-bearing and the second pack
    // is not: one pack is enough for sites 1–5. Two are seeded anyway so each
    // of the three loops runs its body more than once. The progress row and the
    // session are the two that must not be removed without noticing — with them
    // gone the guard still passes, at 5/7.
    //
    // The bound is 5 s against an in-memory sqflite round trip measured in
    // milliseconds, so it is slack rather than a tuning target: far below any
    // plausible suite timeout, far above a healthy restore.
    final two = await twoPackHarness();
    await two.repository.recordAnswer(
        packKey: 'en_ar', entryId: 'fever-1', wasCorrect: true);
    await two.repository.recordAnswer(
        packKey: 'en_tr', entryId: 'fever-1', wasCorrect: true);
    // A finished session as well, because `_sessions.insert` is the seventh
    // call and it is only *reached* if the file carries one: with no sessions in
    // the backup the loop body never runs, and dropping its `executor: txn` left
    // this test **green**. Measured, not assumed — see the table above.
    await two.repository.finishSession(
      packKey: 'en_ar',
      startedAt: DateTime.utc(2026, 10, 14, 9),
      totalQuestions: 4,
      correctCount: 3,
    );
    final json = await two.repository.exportBackupJson();

    await expectLater(
      two.repository.importBackupJson(json).timeout(const Duration(seconds: 5)),
      completes,
    );

    // Not a tautology: the restore really happened, so a green run is not a
    // hung future being abandoned rather than the work being done.
    expect((await two.repository.packs()).map((p) => p.packKey),
        containsAll(<String>['en_ar', 'en_tr']));
    expect((await two.repository.stats('en_ar')).totalAttempts, 1);
    expect((await two.repository.stats('en_ar')).recentSessions, hasLength(1));
  });
}