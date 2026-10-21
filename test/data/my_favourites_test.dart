import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/backup_codec.dart';
import 'package:lexilearn/domain/backup_document.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/domain/my_favourites_pack.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/domain/word_progress.dart';

import '../helpers/test_env.dart';
import 'dictionary/dictionary_test_env.dart';

/// The "My Favourites" pack: derived, never stored.
///
/// **The user's own words:** «حزمة مفضلتي يجب ان تكون مستقلة تزداد كلماتها و
/// تنقص كلما اضاف المستخدم كلمة الى المفضلة او ازال كلمة اي اي بكل بساطة هي
/// حزمة جديدة يتم ملؤها و تفريغها من قبل المستخدم عبر اضافة كلمة او ازالة
/// كلمة من اي من الحزمتين المدمجتين حاليا».
///
/// The specification is `docs/my-favourites-pack.md`.
void main() {
  late TestHarness harness;
  late VocabRepository repository;

  /// The 297-word starter set, as the app ships it: `term-slug-hash` ids.
  ///
  /// **Two words with the same spelling as a dictionary headword**, so the
  /// "the same English word in both packs" case is a fixture rather than a
  /// thought experiment.
  const starterPack = VocabPack(
    schemaVersion: 1,
    packId: starterPackKey,
    title: 'English to Arabic',
    sourceLanguage: 'en',
    targetLanguage: 'ar',
    entries: <VocabEntry>[
      VocabEntry(
        id: 'ghost-clusters-4da03e',
        term: 'ghost clusters',
        translations: <String>['شبح'],
      ),
      VocabEntry(
        id: 'child-9f21c4',
        term: 'child',
        translations: <String>['طفل'],
      ),
    ],
  );

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[starterPack]);
    repository = harness.repository;
    // The dictionary's **row**, so a favourite filed under its key can be
    // written at all: `favorites.pack_key` is a foreign key onto `packs`.
    await repository.ensureDictionaryPack();
  });

  tearDown(() async {
    await harness.dispose();
  });

  /// The derived pack's entry ids, in order.
  Future<List<String>> derivedIds() async =>
      (await repository.myFavourites()).map((entry) => entry.id).toList();

  group('the whole feature in one assertion', () {
    test('a favourite added to either pack appears in the derived pack, and '
        'removing it takes it out — and the ids stay the same across a rebuild',
        () async {
      // **Nothing in it to begin with.** A pack with no words in it is not a
      // pack.
      expect(await repository.myFavourites(), isEmpty);

      // **A word from the starter set.**
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );

      final first = await repository.myFavourites();
      expect(first, hasLength(1));
      // **The literal id, not the constant.** A test that compares the
      // constant with itself passes whatever the constant says; this one says
      // what the id is.
      expect(first.single.id, 'myfav:english_ar_v1:ghost-clusters-4da03e');
      // **The word itself is the source's**, not a copy of it: the derived
      // entry is a view of the starter pack's entry.
      expect(first.single.term, 'ghost clusters');
      expect(first.single.translations, <String>['شبح']);

      // **The ids are the same on every derivation.** This is what makes the
      // progress recorded against a favourite survive a rebuild.
      expect(await derivedIds(), first.map((entry) => entry.id).toList());
      expect(await derivedIds(), await derivedIds());

      // **Removing it takes it out.**
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: false,
      );
      expect(await repository.myFavourites(), isEmpty);
    });

    test('the derived pack holds a favourite from each of the two packs',
        () async {
      // **The dictionary's own engine**, because the dictionary's words are in
      // a read-only file of their own and not in this database at all.
      final dictionary = await DictionaryFixture.open();
      addTearDown(dictionary.close);
      repository.attachDictionary(dictionary.engine);

      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      await repository.setFavorite(
        packKey: dictionaryPackKey,
        entryId: dictionaryEntryId('child'),
        isFavorite: true,
      );

      final ids = await derivedIds();
      expect(ids, hasLength(2));
      expect(ids, contains('myfav:english_ar_v1:ghost-clusters-4da03e'));
      // **The dictionary's own namespaced id, kept whole**, so the origin is
      // readable in the id.
      expect(ids, contains('myfav:dictionary_en_ar:dict:child'));

      // **And the dictionary's entry is the dictionary's**, resolved through
      // the engine rather than out of this database's `entries` table.
      final child = (await repository.myFavourites())
          .firstWhere((entry) => entry.id == 'myfav:dictionary_en_ar:dict:child');
      expect(child.term, 'child');
      expect(child.translations, isNotEmpty);
    });

    test('the same English word in both packs is two entries under two ids',
        () async {
      final dictionary = await DictionaryFixture.open();
      addTearDown(dictionary.close);
      repository.attachDictionary(dictionary.engine);

      // "child" in the starter set, and "child" in the dictionary.
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'child-9f21c4',
        isFavorite: true,
      );
      await repository.setFavorite(
        packKey: dictionaryPackKey,
        entryId: dictionaryEntryId('child'),
        isFavorite: true,
      );

      final entries = await repository.myFavourites();
      expect(entries, hasLength(2));
      // **Two entries, one spelling.**
      expect(entries.map((entry) => entry.term).toSet(), <String>{'child'});
      // **Two ids, because the two are different entries in two different
      // sources.** A hash of the word would have collided here.
      expect(entries.map((entry) => entry.id).toSet(), hasLength(2));
      expect(
        entries.map((entry) => entry.id),
        containsAll(<String>[
          'myfav:english_ar_v1:child-9f21c4',
          'myfav:dictionary_en_ar:dict:child',
        ]),
      );
    });
  });

  group('the pack list', () {
    test('the derived pack is in the list only once it has a word in it',
        () async {
      expect(
        (await repository.packs()).map((pack) => pack.packKey),
        isNot(contains(myFavouritesPackKey)),
        reason: 'a pack with nothing in it is not a pack',
      );

      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );

      final packs = await repository.packs();
      final derived =
          packs.firstWhere((pack) => pack.packKey == myFavouritesPackKey);
      // **The literal title, not the constant.**
      expect(derived.title, 'مفضلتي');
      expect(derived.entryCount, 1);
    });

    test('the derived pack never becomes the active pack by accident',
        () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );

      final packs = await repository.packs();
      // **The active pack is `packs.first`** — `HomeShell` takes the first one
      // — and the active pack is what the word of the day and the flashcards
      // draw from. A derived pack that sorted first would take the app over
      // the moment a user saved one word.
      expect(packs.first.packKey, dictionaryPackKey);
      // **And it is last**, so choosing it is a deliberate act.
      expect(packs.last.packKey, myFavouritesPackKey);
    });

    test('the derived pack is named for the user, not by its key', () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      expect(await repository.packTitle(myFavouritesPackKey), 'مفضلتي');
      expect(await repository.packTitle(myFavouritesPackKey),
          isNot(contains(myFavouritesPackKey)),
          reason: 'a key is an identifier and must not reach the user');
    });
  });

  group('the reserved key', () {
    test('no imported pack may claim it', () async {
      final json = PackCodec.encodePack(const VocabPack(
        schemaVersion: 1,
        packId: 'my_favourites',
        title: 'Not mine',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: <VocabEntry>[
          VocabEntry(id: 'x-1', term: 'x', translations: <String>['س']),
        ],
      ));

      expect(
        () => repository.importPack(json),
        throwsA(isA<PackDecodeException>()),
        reason: 'the key is reserved, and a reservation that can be claimed is '
            'not a reservation',
      );
      // **And nothing was written.**
      expect(
        (await repository.packs()).map((pack) => pack.packKey),
        isNot(contains(myFavouritesPackKey)),
      );
    });

    test('a backup that carries a pack claiming it is refused', () async {
      final document = BackupCodec.decode(await repository.exportBackupJson());
      final json = BackupCodec.encode(BackupDocument(
        exportedAt: document.exportedAt,
        packs: <VocabPack>[
          const VocabPack(
            schemaVersion: 1,
            packId: 'my_favourites',
            title: 'Not mine',
            sourceLanguage: 'en',
            targetLanguage: 'ar',
            entries: <VocabEntry>[
              VocabEntry(id: 'x-1', term: 'x', translations: <String>['س']),
            ],
          ),
        ],
        progress: document.progress,
        favorites: document.favorites,
        sessions: document.sessions,
      ));

      expect(
        () => repository.importBackupJson(json),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('the derived pack cannot be deleted, and cannot be exported', () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      expect(
        () => repository.deletePack(myFavouritesPackKey),
        throwsA(isA<PackDecodeException>()),
      );
      expect(
        () => repository.exportPackJson(myFavouritesPackKey),
        throwsA(isA<PackDecodeException>()),
      );
      // **And the user's saved word survived the attempt.**
      expect(
        await repository.isFavorite(
          packKey: starterPackKey,
          entryId: 'ghost-clusters-4da03e',
        ),
        isTrue,
      );
    });
  });

  group('the derived pack is a second view of the same truth', () {
    test('unsaving through it removes the word from the pack it came from',
        () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      final derived = (await repository.myFavourites()).single;

      await repository.setFavorite(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        isFavorite: false,
      );

      expect(
        await repository.isFavorite(
          packKey: starterPackKey,
          entryId: 'ghost-clusters-4da03e',
        ),
        isFalse,
        reason: 'the write went to the row the word really belongs to',
      );
      expect(await repository.myFavourites(), isEmpty);
    });

    test('the heart on a word reached through it reads as saved', () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      final derived = (await repository.myFavourites()).single;

      expect(
        await repository.isFavorite(
          packKey: myFavouritesPackKey,
          entryId: derived.id,
        ),
        isTrue,
      );
      // **And a word that is not a favourite of any pack is not one here.**
      expect(
        await repository.isFavorite(
          packKey: myFavouritesPackKey,
          entryId: 'myfav:english_ar_v1:not-saved-1',
        ),
        isFalse,
      );
    });

    test('the favourites list and the derived pack show the same words',
        () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'child-9f21c4',
        isFavorite: true,
      );

      final listed = await repository.favorites(starterPackKey);
      final derived = await repository.myFavourites();
      expect(listed.map((entry) => entry.term),
          derived.map((entry) => entry.term));
      // **The derived pack's ids are namespaced; the favourites list's are the
      // pack's own.** Same words, different keys — and that is the point.
      expect(listed.map((entry) => entry.id),
          isNot(derived.map((entry) => entry.id)));
    });

    test('the dictionary\'s saved words are in the favourites list too',
        () async {
      // **A defect this round found.** The favourites list used to answer with
      // nothing for the dictionary, because it resolved the ids against this
      // database's `entries` table and the dictionary has no rows there — so
      // the derived pack, which resolves the same rows against the right
      // source, showed the words the favourites list did not. Two views of one
      // truth must agree.
      final dictionary = await DictionaryFixture.open();
      addTearDown(dictionary.close);
      repository.attachDictionary(dictionary.engine);

      await repository.setFavorite(
        packKey: dictionaryPackKey,
        entryId: dictionaryEntryId('child'),
        isFavorite: true,
      );

      final listed = await repository.favorites(dictionaryPackKey);
      expect(listed, hasLength(1));
      expect(listed.single.term, 'child');
      expect(listed.single.id, dictionaryEntryId('child'));
    });
  });

  group('the backup', () {
    test('the derived pack adds no rows to it', () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      final document = BackupCodec.decode(await repository.exportBackupJson());

      // **No pack row under the derived key.**
      expect(
        document.packs.map((pack) => pack.packId),
        isNot(contains(myFavouritesPackKey)),
      );
      // **And no favourite filed under it** — the word is filed under the pack
      // it really came from, which is what makes the derived pack rebuild
      // itself from a restored backup.
      expect(
        document.favorites.where((favourite) =>
            favourite.packKey == myFavouritesPackKey),
        isEmpty,
      );
      // **And the word itself is in the file**, under its own pack.
      expect(
        document.favorites
            .where((favourite) => favourite.entryId == 'ghost-clusters-4da03e')
            .map((favourite) => favourite.packKey),
        <String>[starterPackKey],
      );
    });

    test('the derived pack is rebuilt from a restored backup', () async {
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      final json = await repository.exportBackupJson();

      // **A device that has never heard of the word.**
      final other = await TestHarness.create(packs: <VocabPack>[starterPack]);
      addTearDown(other.dispose);
      expect(await other.repository.myFavourites(), isEmpty);

      await other.repository.importBackupJson(json);

      final rebuilt = await other.repository.myFavourites();
      expect(rebuilt, hasLength(1));
      expect(
        rebuilt.single.id,
        'myfav:english_ar_v1:ghost-clusters-4da03e',
        reason: 'the id is the same on the other device, because it is derived '
            'from the pack and the word rather than from a counter',
      );
    });

    test('a restore clears the derived pack\'s own progress', () async {
      // The derived pack has no row in `packs`, so the restore's loop over the
      // stored packs never reaches it — and a restore that left its rows
      // behind would carry the previous device's progress and sessions into a
      // pack whose contents are about to be somebody else's.
      //
      // **And the derived pack holds no progress rows of its own**, so what a
      // restore has to clear is the progress of the pack its words came from —
      // a file that carries no progress must leave none behind, whichever
      // pack the answers were given through.
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      final derived = (await repository.myFavourites()).single;
      await repository.recordAnswer(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        wasCorrect: true,
      );
      expect((await repository.stats(myFavouritesPackKey)).totalAttempts, 1);

      // **A file that carries the packs and the favourites, and no progress.**
      final document = BackupCodec.decode(await repository.exportBackupJson());
      final withoutProgress = BackupCodec.encode(BackupDocument(
        exportedAt: document.exportedAt,
        packs: document.packs,
        progress: const <WordProgress>[],
        favorites: document.favorites,
        sessions: document.sessions,
      ));

      await repository.importBackupJson(withoutProgress);

      expect((await repository.stats(myFavouritesPackKey)).totalAttempts, 0);
      expect((await repository.stats(starterPackKey)).totalAttempts, 0);
      // **And no row is left under the derived pack's own key**, which is the
      // one thing a restore must never leave behind: a duplicate of a record
      // that already lives in the pack the word came from.
      final rows = await harness.database.query('word_progress');
      expect(
        rows.where((row) => row['pack_key'] == myFavouritesPackKey),
        isEmpty,
      );
    });
  });

  group('the progress of a word', () {
    /// The starter set's word, saved.
    Future<void> saveGhost() => repository.setFavorite(
          packKey: starterPackKey,
          entryId: 'ghost-clusters-4da03e',
          isFavorite: true,
        );

    test('a word studied through the derived pack is recorded in the pack it '
        'came from, and under no other key', () async {
      await saveGhost();
      final derived = (await repository.myFavourites()).single;

      await repository.recordAnswer(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        wasCorrect: true,
      );

      // **The row itself, read out of the table.** The statistics are a
      // summary of this table; the table is the record, and a record filed
      // under the derived pack's key would be a second one of the same work.
      final rows = await harness.database.query('word_progress');
      expect(rows, hasLength(1));
      expect(rows.single['pack_key'], starterPackKey);
      // **The source's own entry id**, not the derived one: the row belongs to
      // the word, and the word belongs to the pack it came from.
      expect(rows.single['entry_id'], 'ghost-clusters-4da03e');
    });

    test('the statistics count such a word once, not twice', () async {
      await saveGhost();
      final derived = (await repository.myFavourites()).single;

      // **Five answers, so the word crosses the mastery floor** and the
      // mastery count has something to be wrong about.
      for (var i = 0; i < 5; i++) {
        await repository.recordAnswer(
          packKey: myFavouritesPackKey,
          entryId: derived.id,
          wasCorrect: true,
        );
      }

      final derivedStats = await repository.stats(myFavouritesPackKey);
      expect(derivedStats.totalAttempts, 5);
      expect(derivedStats.totalCorrect, 5);
      expect(derivedStats.wordsPracticed, 1);
      expect(derivedStats.wordsMastered, 1);
      expect(derivedStats.accuracy, 1.0);

      // **The source pack's figures are the same record seen from the pack it
      // belongs to** — the same numbers, and not more of them.
      final sourceStats = await repository.stats(starterPackKey);
      expect(sourceStats.totalAttempts, 5);
      expect(sourceStats.totalCorrect, 5);
      expect(sourceStats.wordsPracticed, 1);
      expect(sourceStats.wordsMastered, 1);
      expect(sourceStats.accuracy, 1.0);

      // **And there is one row behind both sets of figures.** Two rows would
      // mean two records of the same five answers, and the figures would be
      // counting the word twice.
      final rows = await harness.database.query('word_progress');
      expect(rows, hasLength(1));

      // **And a row filed under the derived pack's own key is not counted.**
      // A row like that is what an earlier version of the app wrote: the same
      // work, recorded a second time. Reading it here would count the word
      // twice — once from each side — and the figures would be telling the
      // user they had done twice what they had done.
      await harness.database.insert('word_progress', <String, Object?>{
        'entry_id': derived.id,
        'pack_key': myFavouritesPackKey,
        'attempts': 3,
        'correct_count': 1,
        'last_seen_at': DateTime.utc(2026, 10, 14, 12).toIso8601String(),
      });

      expect((await repository.stats(myFavouritesPackKey)).totalAttempts, 5);
      expect((await repository.stats(starterPackKey)).totalAttempts, 5);
    });

    test('the progress of a word studied through the derived pack survives an '
        'export and a restore', () async {
      await saveGhost();
      final derived = (await repository.myFavourites()).single;
      await repository.recordAnswer(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        wasCorrect: true,
      );
      await repository.finishSession(
        packKey: myFavouritesPackKey,
        startedAt: DateTime.utc(2026, 10, 14, 9),
        totalQuestions: 10,
        correctCount: 7,
      );

      final json = await repository.exportBackupJson();

      // **The wipe.** Without it the restore would prove nothing: the file
      // carries the progress, so restoring it onto a device that still had it
      // would look the same whether the progress had travelled or not.
      await repository.resetProgress(starterPackKey);
      await repository.resetProgress(myFavouritesPackKey);
      expect((await repository.stats(starterPackKey)).totalAttempts, 0);
      expect((await repository.stats(myFavouritesPackKey)).totalAttempts, 0);
      expect((await repository.stats(myFavouritesPackKey)).recentSessions, isEmpty);

      await repository.importBackupJson(json);

      // **It is back**, in the pack the word came from — the file carries no
      // pack key of its own for the derived pack, and needs none.
      final stats = await repository.stats(starterPackKey);
      expect(stats.totalAttempts, 1);
      expect(stats.totalCorrect, 1);
      expect(stats.wordsPracticed, 1);
      // **And the derived pack sees the same record**, because it is the same
      // record and not a copy of it.
      expect((await repository.stats(myFavouritesPackKey)).totalAttempts, 1);
      // **And the quiz that was played in it is back too.**
      expect((await repository.stats(myFavouritesPackKey)).recentSessions,
          hasLength(1));
    });

    test('resetting the derived pack clears the progress of its words, and '
        'no other word\'s', () async {
      await saveGhost();
      final derived = (await repository.myFavourites()).single;

      // **A saved word and an unsaved one**, both answered: the reset may
      // clear the first, because it is in the pack, and must not clear the
      // second, because it is not.
      await repository.recordAnswer(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        wasCorrect: true,
      );
      await repository.recordAnswer(
        packKey: starterPackKey,
        entryId: 'child-9f21c4',
        wasCorrect: true,
      );

      expect(await repository.resetProgress(myFavouritesPackKey), 1);

      expect((await repository.stats(starterPackKey)).wordsPracticed, 1);
      expect((await repository.stats(myFavouritesPackKey)).wordsPracticed, 0);
    });

    test('an answer about a word that is no longer saved is not recorded',
        () async {
      await saveGhost();
      final derived = (await repository.myFavourites()).single;

      // **The word leaves the pack** — unsaved through the derived pack, so
      // the row it really belongs to is the one that goes.
      await repository.setFavorite(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        isFavorite: false,
      );

      // **And the answer that was already on screen is given anyway.**
      await repository.recordAnswer(
        packKey: myFavouritesPackKey,
        entryId: derived.id,
        wasCorrect: true,
      );

      // **Nothing is recorded**, because there is no pack to record it in: a
      // row under the derived pack's own key would be the duplicate this
      // resolution exists to prevent.
      final rows = await harness.database.query('word_progress');
      expect(rows, isEmpty);
    });
  });
}
