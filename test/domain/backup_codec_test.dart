import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/domain/backup_codec.dart';
import 'package:lexilearn/domain/backup_document.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/domain/word_progress.dart';

const VocabPack pack = VocabPack(
  schemaVersion: 1,
  packId: 'p',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['ألف']),
    VocabEntry(
      id: 'b',
      term: 'beta',
      translations: <String>['بيتا', '第二个'],
      note: 'two senses',
      phonetic: '/ˈbiːtə/',
      partOfSpeech: 'noun',
      synonyms: <String>['beta ray'],
      examples: <String>['a beta tester'],
    ),
  ],
);

// NOT `const`: `DateTime.utc` is a factory constructor, not a const one, so
// `const DateTime exportedAt = DateTime.utc(...)` fails to compile and — being
// the one bad `const` — poisons every `const` list literal that mentions it.
// `pack` above stays `const` because `VocabPack` and `VocabEntry` genuinely
// are const-constructible; only the timestamps are not.
final DateTime exportedAt = DateTime.utc(2026, 10, 14, 12);

BackupDocument sample() => BackupDocument(
      exportedAt: exportedAt,
      packs: const <VocabPack>[pack],
      progress: const <WordProgress>[
        WordProgress(entryId: 'a', packKey: 'p', attempts: 5, correct: 4),
      ],
      sessions: const <QuizSessionResult>[],
      favorites: const <BackupFavorite>[
        BackupFavorite(packKey: 'p', entryId: 'a'),
      ],
    );

void main() {
  group('BackupCodec', () {
    test('round-trips packs and progress without loss', () {
      final decoded = BackupCodec.decode(BackupCodec.encode(sample()));

      expect(decoded.packs.single.packId, 'p');
      expect(decoded.packs.single.title, 'English to Arabic');
      expect(decoded.packs.single.sourceLanguage, 'en');
      expect(decoded.packs.single.targetLanguage, 'ar');
      // The plan's fixture pack held ONE entry, so its assertion read
      // `entries.single.term`. This file widened the pack to two entries (to
      // cover the optional fields below), which left that `.single` throwing
      // "Bad state: Too many elements" on a codec that was working. Asserting
      // the whole list instead is also the stronger claim: a codec that dropped
      // an entry would pass `entries.first` but fail this.
      expect(decoded.packs.single.entries.first.term, 'alpha');
      expect(decoded.packs.single.entries, pack.entries);
      expect(decoded.progress.single.attempts, 5);
      expect(decoded.progress.single.correct, 4);
      expect(decoded.progress.single.entryId, 'a');
      expect(decoded.progress.single.packKey, 'p');
      expect(decoded.exportedAt, exportedAt);
    });

    test('round-trips every optional field on an entry', () {
      // The plan's sample entry carries only a term and one translation, so a
      // codec that silently drops `note`, `phonetic`, `partOfSpeech`,
      // `synonyms` or `examples` would pass its own test. The dataset itself
      // never populates those, but a hand-written backup can, and Task 16's
      // word-detail screen reads all five.
      final decoded = BackupCodec.decode(BackupCodec.encode(sample()));

      final beta = decoded.packs.single.entries.last;
      expect(beta.id, 'b');
      expect(beta.term, 'beta');
      expect(beta.translations, <String>['بيتا', '第二个']);
      expect(beta.note, 'two senses');
      expect(beta.phonetic, '/ˈbiːtə/');
      expect(beta.partOfSpeech, 'noun');
      expect(beta.synonyms, <String>['beta ray']);
      expect(beta.examples, <String>['a beta tester']);
    });

    test('round-trips session history and a last-seen timestamp', () {
      final document = BackupDocument(
        exportedAt: exportedAt,
        packs: const <VocabPack>[pack],
        progress: <WordProgress>[
          WordProgress(
            entryId: 'a',
            packKey: 'p',
            attempts: 1,
            correct: 1,
            lastSeenAt: DateTime.utc(2026, 10, 13, 7, 5),
          ),
        ],
        sessions: <QuizSessionResult>[
          QuizSessionResult(
            packKey: 'p',
            startedAt: DateTime.utc(2026, 10, 13, 9),
            totalQuestions: 4,
            correctCount: 3,
          ),
        ],
      );

      final decoded = BackupCodec.decode(BackupCodec.encode(document));

      expect(decoded.progress.single.lastSeenAt, DateTime.utc(2026, 10, 13, 7, 5));
      final session = decoded.sessions.single;
      expect(session.packKey, 'p');
      expect(session.startedAt, DateTime.utc(2026, 10, 13, 9));
      expect(session.totalQuestions, 4);
      expect(session.correctCount, 3);
    });

    test('marks the document as a backup so pack import can reject it', () {
      final json = BackupCodec.encode(sample());

      expect(json.contains('"kind": "backup"'), isTrue,
          reason: 'the marker is what tells the two file kinds apart');
      expect(() => PackCodec.decodePack(json), throwsA(isA<PackDecodeException>()));
    });

    test('rejects a plain pack document, naming the alternative', () {
      final json = PackCodec.encodePack(pack);

      expect(
        () => BackupCodec.decode(json),
        throwsA(isA<PackDecodeException>().having(
          (e) => e.message,
          'message',
          contains('vocabulary pack'),
        )),
      );
    });

    test('rejects malformed JSON', () {
      expect(() => BackupCodec.decode('{oops'), throwsA(isA<PackDecodeException>()));
    });

    test('rejects a document whose root is not an object', () {
      expect(() => BackupCodec.decode('[1,2,3]'), throwsA(isA<PackDecodeException>()));
    });

    test('rejects an unsupported version', () {
      expect(
        () => BackupCodec.decode(
            '{"kind":"backup","schemaVersion":42,"exportedAt":"2026-10-14T00:00:00Z",'
            '"packs":[],"progress":[],"sessions":[]}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('rejects a backup with no exportedAt', () {
      expect(
        () => BackupCodec.decode(
            '{"kind":"backup","schemaVersion":'
            '${BackupDocument.currentSchemaVersion},'
            '"packs":[],"progress":[],"sessions":[],"favorites":[]}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('accepts a backup with no progress and no sessions', () {
      final decoded = BackupCodec.decode(
          '{"kind":"backup","schemaVersion":'
          '${BackupDocument.currentSchemaVersion},'
          '"exportedAt":"2026-10-14T00:00:00Z",'
          '"packs":[],"progress":[],"sessions":[],"favorites":[]}');

      expect(decoded.packs, isEmpty);
      expect(decoded.progress, isEmpty);
      expect(decoded.sessions, isEmpty);
      expect(decoded.favorites, isEmpty);
      expect(decoded.exportedAt, DateTime.utc(2026, 10, 14));
    });

    test('rejects a non-list where a list belongs, for every list key', () {
      // **The one test that distinguishes `_list` from the plan's
      // `(document[key] as List<dynamic>? ?? const [])`, and it was missing.**
      //
      // The plan's version was in place and the whole file stayed 11/11 green
      // with it — so "the codec's three improvements are verified" was a claim
      // about a behaviour nothing tested. Both versions treat an *absent* key as
      // an empty list, and both treat `null` as empty; they differ only on a
      // non-list value, where the plan's version throws a **raw `TypeError`**.
      //
      // That matters because `PacksController` catches `PackDecodeException` and
      // renders `message` verbatim. A raw `TypeError` escapes that handler, so a
      // hand-edited file with `"packs": {}` would reach the user as an
      // unhandled exception instead of a sentence — which is the entire reason
      // `BackupCodec` documents that every failure throws `PackDecodeException`.
      //
      // All four list keys are checked, not just this one, because `_list` is
      // called four times and a fix applied to one call site is not a fix.
      //
      // The document names the malformed key **once**. A hand-written literal
      // that also carried `"packs":[]` would hand `jsonDecode` a duplicate key,
      // and Dart keeps the last one — so the object would parse cleanly as a
      // list and the test would fail for a reason that has nothing to do with
      // `_list`. Measured: that is exactly what the first draft of this test did.
      String documentWith(String malformedKey) {
        final rest = <String>['packs', 'progress', 'sessions', 'favorites']
            .where((key) => key != malformedKey)
            .map((key) => '"$key":[]')
            .join(',');
        return '{"kind":"backup","schemaVersion":'
            '${BackupDocument.currentSchemaVersion},'
            '"exportedAt":"2026-10-14T00:00:00Z",'
            '"$malformedKey":{},$rest}';
      }

      for (final key in <String>['packs', 'progress', 'sessions', 'favorites']) {
        expect(
          () => BackupCodec.decode(documentWith(key)),
          throwsA(isA<PackDecodeException>()),
          reason: 'a non-list "$key" must be a PackDecodeException, not a TypeError',
        );
      }
    });

    test('a decoded document is itself re-encodable without loss', () {
      // Two round trips, not one. `encode(decode(encode(x))) == encode(x)` is
      // what makes a backup that has been through the app's own decoder still
      // readable by the app — the property a user cares about when they restore
      // onto a second phone and export again.
      final once = BackupCodec.encode(sample());
      final twice = BackupCodec.encode(BackupCodec.decode(once));

      expect(BackupCodec.decode(twice).packs.single.entries, pack.entries);
      expect(BackupCodec.decode(twice).progress.single.attempts, 5);
    });

    // --- favourites (Task 14, fix round 1) ---------------------------------------
    //
    // Favourites are the one list a user curates **by hand**. Progress and
    // sessions are the app's own record of what the user did; a favourite is a
    // decision, and losing it is losing something nothing else records. It
    // therefore belongs in the file whose stated job is to put a new phone back
    // where the old one was.

    test('round-trips the saved words', () {
      final decoded = BackupCodec.decode(BackupCodec.encode(sample()));

      expect(decoded.favorites, hasLength(1));
      expect(decoded.favorites.single.packKey, 'p');
      expect(decoded.favorites.single.entryId, 'a');
    });

    test('round-trips several favourites across two packs', () {
      final document = BackupDocument(
        exportedAt: exportedAt,
        packs: const <VocabPack>[pack],
        progress: const <WordProgress>[],
        sessions: const <QuizSessionResult>[],
        favorites: const <BackupFavorite>[
          BackupFavorite(packKey: 'p', entryId: 'a'),
          BackupFavorite(packKey: 'p', entryId: 'b'),
          BackupFavorite(packKey: 'q', entryId: 'a'),
        ],
      );

      final decoded = BackupCodec.decode(BackupCodec.encode(document));

      // The same word id in two packs is the case that matters: `favorites` is
      // keyed `(packKey, entryId)`, so the pair has to survive intact.
      expect(
        decoded.favorites.map((f) => '${f.packKey}/${f.entryId}').toList(),
        <String>['p/a', 'p/b', 'q/a'],
      );
    });

    test('an absent favourites list is an empty one, not an error', () {
      // A hand-written file, or one from a build before the version bump that
      // carried them — except that one is refused by version, so this is about
      // a *current-version* file that simply has nothing saved.
      final decoded = BackupCodec.decode(
          '{"kind":"backup","schemaVersion":'
          '${BackupDocument.currentSchemaVersion},'
          '"exportedAt":"2026-10-14T00:00:00Z",'
          '"packs":[],"progress":[],"sessions":[]}');

      expect(decoded.favorites, isEmpty);
    });

    test('a v1 file is refused by name rather than half-read', () {
      // **The version bump that carried favourites in is inside the backup
      // document only.** `databaseSchemaVersion` stayed 1; this constant moved to
      // 2. A file written by an older build has no `favorites` key, so reading it
      // as "no favourites" would silently wipe the new phone's list on the
      // restore — which is the exact data loss this change exists to stop,
      // reintroduced from the other direction. Refuse it, and say what version
      // the app reads.
      expect(
        () => BackupCodec.decode(
            '{"kind":"backup","schemaVersion":1,'
            '"exportedAt":"2026-10-14T00:00:00Z",'
            '"packs":[],"progress":[],"sessions":[]}'),
        throwsA(isA<PackDecodeException>()
            .having((e) => e.message, 'message', contains('version'))
            .having((e) => e.message, 'message',
                contains('${BackupDocument.currentSchemaVersion}'))),
      );
    });

    test('the current version is 2, and it is not the database schema version',
        () {
      // Two different numbers with two different meanings, and the second one is
      // the one a future task is most likely to confuse with the first.
      expect(BackupDocument.currentSchemaVersion, 2);
      expect(databaseSchemaVersion, 1,
          reason: 'the app database ships as v1; only the backup file moved');
    });
  });
}
