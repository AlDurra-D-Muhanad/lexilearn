import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/backup_codec.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import '../helpers/test_env.dart';

/// The user's own dictionary, in the data layer.
///
/// The user's words: *«ان يستطيع المستخدم انشاء قاموسه الخاص و جعل امكانية اختيار
/// هذا القاموس كحزمة مستقلة عن باقي الحزم ليستطيع المستخدم البحث و اجراء
/// الاختبارات من قاموسه الخاص»* — create it, choose it as a pack of its own,
/// and search and quiz from it.
///
/// **Stored, not derived.** Every other user-made view in this app is computed
/// from data that already exists; these words exist nowhere else, so they are
/// `packs` and `entries` rows, backed up and restored like an imported pack.
void main() {
  late TestHarness harness;
  late VocabRepository repository;

  setUp(() async {
    harness = await TestHarness.create();
    repository = harness.repository;
  });

  tearDown(() async {
    await harness.dispose();
  });

  /// The custom pack's stored row, read straight from the table.
  Future<List<Map<String, Object?>>> customPackRows() => harness.database.query(
        'packs',
        where: 'pack_key = ?',
        whereArgs: <Object?>[customDictionaryPackKey],
      );

  group('the pack appears only when it has words', () {
    test('an empty dictionary is not a pack, the first word makes it one, and '
        'the last deletion hides it again without deleting its row', () async {
      expect(await repository.packs(), isEmpty,
          reason: 'an empty pack is a promise of words the user has not saved');

      final word = await repository.addCustomWord(
        term: 'serendipity',
        meaning: 'صدفة سعيدة',
      );
      expect(word.term, 'serendipity');
      expect(word.id, 'mine:serendipity-bd6a3f');

      final packs = await repository.packs();
      expect(packs, hasLength(1));
      final pack = packs.single;
      expect(pack.packKey, customDictionaryPackKey);
      expect(pack.title, customDictionaryTitle);
      expect(pack.entryCount, 1);
      // The pack is the user's data, and the backup walks the packs to find it.
      expect(pack.isBundled, isFalse);

      // **It is a pack like any other for the two things the brief names.**
      expect(
        (await repository.search(
          packKey: customDictionaryPackKey,
          query: 'seren',
        ))
            .map((entry) => entry.id),
        <String>[word.id],
      );
      expect(
        (await repository.search(
          packKey: customDictionaryPackKey,
          query: 'صدفة',
        ))
            .map((entry) => entry.id),
        <String>[word.id],
        reason: 'the meaning is searchable too',
      );
      expect(
        (await repository.entries(customDictionaryPackKey)).map((e) => e.id),
        <String>[word.id],
      );

      // **The last word goes; the row stays.** The row is the parent of the
      // pack's sessions and progress, and deleting it would take the user's
      // quiz history with it.
      await repository.deleteCustomWord(word.id);
      expect(await repository.customWords(), isEmpty);
      expect(await repository.packs(), isEmpty,
          reason: 'a pack with no words is not offered for study');
      final rows = await customPackRows();
      expect(rows, hasLength(1),
          reason: 'the row survives so history is not wiped with the last word');
      expect((rows.single['entry_count']! as num).toInt(), 0);
      expect(await repository.packTitle(customDictionaryPackKey),
          customDictionaryTitle);
    });

    test('the words are listed in the order they were typed', () async {
      await repository.addCustomWord(term: 'first', meaning: 'أول');
      await repository.addCustomWord(term: 'second', meaning: 'ثانٍ');
      await repository.addCustomWord(term: 'third', meaning: 'ثالث');

      expect(
        (await repository.customWords()).map((entry) => entry.term),
        <String>['first', 'second', 'third'],
      );
      expect((await repository.packs()).single.entryCount, 3);
    });
  });

  group('both fields are required', () {
    test('a word with no meaning is refused, and nothing is written', () async {
      await expectLater(
        repository.addCustomWord(term: 'serendipity', meaning: '   '),
        throwsA(isA<CustomDictionaryException>().having(
          (error) => error.message,
          'message',
          'اكتب معنى الكلمة أولاً.',
        )),
      );
      expect(await repository.customWords(), isEmpty);
      expect(await harness.database.query('packs'), isEmpty,
          reason: 'a refused save must not create the pack row either');
    });

    test('a meaning with no word is refused, and nothing is written', () async {
      await expectLater(
        repository.addCustomWord(term: ' \t ', meaning: 'صدفة سعيدة'),
        throwsA(isA<CustomDictionaryException>().having(
          (error) => error.message,
          'message',
          'اكتب الكلمة أولاً.',
        )),
      );
      expect(await repository.customWords(), isEmpty);
      expect(await harness.database.query('packs'), isEmpty);
    });

    test('the field bounds are enforced on save', () async {
      final longestWord = List<String>.filled(customWordMaxLength, 'a').join();
      final longestMeaning =
          List<String>.filled(customMeaningMaxLength, 'م').join();

      // Exactly at the bound: accepted.
      await repository.addCustomWord(
        term: longestWord,
        meaning: longestMeaning,
      );
      expect(await repository.customWords(), hasLength(1));

      await expectLater(
        repository.addCustomWord(
          term: '${longestWord}a',
          meaning: 'معنى',
        ),
        throwsA(isA<CustomDictionaryException>().having(
          (error) => error.message,
          'message',
          'الكلمة أطول من الحد المسموح به.',
        )),
      );
      await expectLater(
        repository.addCustomWord(
          term: 'another',
          meaning: '$longestMeaning\u0645',
        ),
        throwsA(isA<CustomDictionaryException>().having(
          (error) => error.message,
          'message',
          'المعنى أطول من 500 حرف.',
        )),
      );
      expect(await repository.customWords(), hasLength(1));
    });
  });

  group('a duplicate is refused', () {
    test('the same word in different case or spacing is the same word',
        () async {
      await repository.addCustomWord(
        term: 'Serendipity',
        meaning: 'صدفة سعيدة',
      );
      await expectLater(
        repository.addCustomWord(
          term: '  serendipity ',
          meaning: 'معنى آخر',
        ),
        throwsA(isA<CustomDictionaryException>().having(
          (error) => error.message,
          'message',
          'هذه الكلمة موجودة في قاموسك بالفعل.',
        )),
      );

      final words = await repository.customWords();
      expect(words, hasLength(1));
      expect(words.single.term, 'Serendipity',
          reason: 'the first spelling is the one the user typed');
      expect(words.single.translations, <String>['صدفة سعيدة'],
          reason: 'the refused save did not overwrite the meaning');
      expect((await repository.packs()).single.entryCount, 1);
    });

    test('`check up` and `check-up` are two different words', () async {
      // The slug collapses both to `check-up`; the digest is what keeps them
      // apart, and they are different English words.
      await repository.addCustomWord(term: 'check up', meaning: 'يتحقق');
      await repository.addCustomWord(term: 'check-up', meaning: 'فحص');

      expect(
        (await repository.customWords()).map((entry) => entry.id).toSet(),
        hasLength(2),
      );
      expect((await repository.packs()).single.entryCount, 2);
    });
  });

  group('deleting a word', () {
    test('removes its favourite and its progress, and leaves the other words '
        'alone', () async {
      final kept = await repository.addCustomWord(
        term: 'kept',
        meaning: 'محفوظة',
      );
      final removed = await repository.addCustomWord(
        term: 'removed',
        meaning: 'محذوفة',
      );

      for (final word in <VocabEntry>[kept, removed]) {
        await repository.setFavorite(
          packKey: customDictionaryPackKey,
          entryId: word.id,
          isFavorite: true,
        );
        await repository.recordAnswer(
          packKey: customDictionaryPackKey,
          entryId: word.id,
          wasCorrect: true,
        );
      }
      expect(await repository.favorites(customDictionaryPackKey), hasLength(2));

      await repository.deleteCustomWord(removed.id);

      expect(
        (await repository.customWords()).map((entry) => entry.id),
        <String>[kept.id],
      );
      expect(
        (await repository.favorites(customDictionaryPackKey))
            .map((entry) => entry.id),
        <String>[kept.id],
        reason: 'a favourite of a word that no longer exists can never resolve',
      );
      final progress = await harness.database.query(
        'word_progress',
        where: 'pack_key = ?',
        whereArgs: <Object?>[customDictionaryPackKey],
        orderBy: 'entry_id ASC',
      );
      expect(
        progress.map((row) => row['entry_id']),
        <String>[kept.id],
        reason: 'history of a word the user deleted is not history of anything',
      );
      // `packs()` also carries «مفضلتي» while a favourite exists, so the
      // custom pack is found by key rather than by being the only one.
      expect(
        (await repository.packs())
            .firstWhere((pack) => pack.packKey == customDictionaryPackKey)
            .entryCount,
        1,
      );
    });

    test('a deleted word can be typed again, and it is a new word with the '
        'same id', () async {
      final first = await repository.addCustomWord(
        term: 'serendipity',
        meaning: 'صدفة',
      );
      await repository.setFavorite(
        packKey: customDictionaryPackKey,
        entryId: first.id,
        isFavorite: true,
      );
      await repository.deleteCustomWord(first.id);

      final again = await repository.addCustomWord(
        term: 'serendipity',
        meaning: 'حسن الحظ',
      );
      expect(again.id, first.id,
          reason: 'the id is stable, so the favourite key would be the same');
      expect(await repository.favorites(customDictionaryPackKey), isEmpty,
          reason: 'but the deletion removed the old favourite, not just the '
              'word: a deleted word does not come back pre-starred');
    });
  });

  group('the dictionary is the user\'s data', () {
    test('a backup carries the words, the favourite and the progress, and a '
        'restore puts them back', () async {
      final first = await repository.addCustomWord(
        term: 'serendipity',
        meaning: 'صدفة سعيدة',
      );
      final second = await repository.addCustomWord(
        term: 'resilience',
        meaning: 'مرونة',
      );
      await repository.setFavorite(
        packKey: customDictionaryPackKey,
        entryId: first.id,
        isFavorite: true,
      );
      await repository.recordAnswer(
        packKey: customDictionaryPackKey,
        entryId: second.id,
        wasCorrect: true,
      );

      final json = await repository.exportBackupJson();
      final document = BackupCodec.decode(json);
      expect(
        document.packs.map((pack) => pack.packId),
        contains(customDictionaryPackKey),
        reason: 'the one pack the user wrote by hand is the one pack a restore '
            'must not lose',
      );

      final restored = await repository.importBackupJson(json);
      expect(restored, document.packs.length);

      expect(
        (await repository.customWords()).map((entry) => entry.term),
        <String>['serendipity', 'resilience'],
        reason: 'a restore replaces everything, and the words come back in '
            'the order they were typed',
      );
      expect(
        await repository.isFavorite(
          packKey: customDictionaryPackKey,
          entryId: first.id,
        ),
        isTrue,
      );
      final progress = await harness.database.query(
        'word_progress',
        where: 'pack_key = ? AND entry_id = ?',
        whereArgs: <Object?>[customDictionaryPackKey, second.id],
      );
      expect(progress, hasLength(1));
      expect((progress.single['correct_count']! as num).toInt(), 1);

      final pack = (await repository.packs())
          .firstWhere((summary) => summary.packKey == customDictionaryPackKey);
      expect(pack.title, customDictionaryTitle,
          reason: 'the title is the app\'s name for the pack, not whatever '
              'another device stored');
      expect(pack.entryCount, 2);
    });

    test('a pack file cannot claim the custom dictionary\'s key', () async {
      await repository.addCustomWord(term: 'kept', meaning: 'محفوظة');
      final intruder = PackCodec.encodePack(const VocabPack(
        schemaVersion: 1,
        packId: customDictionaryPackKey,
        title: 'Somebody else\'s words',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: <VocabEntry>[
          VocabEntry(id: 'x-1', term: 'intruder', translations: <String>['دخيل']),
        ],
      ));

      await expectLater(
        repository.importPack(intruder),
        throwsA(isA<PackDecodeException>()),
      );
      expect(
        (await repository.customWords()).map((entry) => entry.term),
        <String>['kept'],
        reason: 'a refused import leaves the device exactly as it was',
      );
    });

    test('a quiz session played in the custom pack survives its last word '
        'being deleted', () async {
      final word = await repository.addCustomWord(
        term: 'serendipity',
        meaning: 'صدفة سعيدة',
      );
      await repository.finishSession(
        packKey: customDictionaryPackKey,
        startedAt: DateTime.utc(2026, 10, 29, 18),
        totalQuestions: 4,
        correctCount: 3,
      );

      await repository.deleteCustomWord(word.id);

      final sessions = await harness.database.query(
        'quiz_sessions',
        where: 'pack_key = ?',
        whereArgs: <Object?>[customDictionaryPackKey],
      );
      expect(sessions, hasLength(1),
          reason: 'the pack row survived, so the session row did too');
    });
  });

  group('it survives a restart', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('lexilearn-custom-dictionary');
      path = '${dir.path}/lexilearn.db';
    });

    tearDown(() {
      // Swallowed on purpose: the FFI side can still hold the file when the
      // tear-down runs, and that is a failure of the cleanup, not of the
      // thing under test.
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left behind under the OS temp root.
      }
    });

    test('the words are still there when the app is closed and opened again, '
        'and writing the pack row for a second word does not take the first '
        'word\'s favourite with it', () async {
      final before = await TestHarness.create(path: path);
      final first = await before.repository.addCustomWord(
        term: 'serendipity',
        meaning: 'صدفة سعيدة',
      );
      await before.repository.setFavorite(
        packKey: customDictionaryPackKey,
        entryId: first.id,
        isFavorite: true,
      );
      // **This second save rewrites the pack row**, which is the write that
      // used to delete every favourite under the pack through the cascade.
      await before.repository.addCustomWord(
        term: 'resilience',
        meaning: 'مرونة',
      );
      await before.dispose();

      final after = await TestHarness.create(path: path);
      expect(
        (await after.repository.customWords()).map((entry) => entry.term),
        <String>['serendipity', 'resilience'],
      );
      expect(
        await after.repository.isFavorite(
          packKey: customDictionaryPackKey,
          entryId: first.id,
        ),
        isTrue,
        reason: 'the user\'s own words are the one dataset a restart cannot '
            're-seed, so nothing may take them',
      );
      expect(
        (await after.repository.packs())
            .firstWhere((pack) => pack.packKey == customDictionaryPackKey)
            .entryCount,
        2,
      );

      // And the dictionary still grows after the restart.
      await after.repository.addCustomWord(
        term: 'third',
        meaning: 'ثالث',
      );
      expect(
        (await after.repository.packs())
            .firstWhere((pack) => pack.packKey == customDictionaryPackKey)
            .entryCount,
        3,
      );
      await after.dispose();
    });
  });
}
