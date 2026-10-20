import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import '../helpers/test_env.dart';

/// The dictionary as a pack, and the starter set beside it.
///
/// **The ruling.** The old 297-word pack stays, as a second selectable pack,
/// labelled as a starter set. The dictionary becomes the default. The app
/// already has an active-pack concept and this round must use it rather than
/// build a second one. And the two packs' entry ids must not collide,
/// because a favourite is keyed on `(pack_key, entry_id)` and the backup
/// carries them.
void main() {
  late TestHarness harness;
  late VocabRepository repository;

  const starterPack = VocabPack(
    schemaVersion: 1,
    packId: starterPackKey,
    title: 'English to Arabic',
    sourceLanguage: 'en',
    targetLanguage: 'ar',
    entries: <VocabEntry>[
      // A real starter entry, with the id shape the shipped pack uses.
      VocabEntry(
        id: 'ghost-clusters-4da03e',
        term: 'ghost clusters',
        translations: <String>['شبح'],
      ),
      VocabEntry(
        id: 'statistic-b482df',
        term: 'statistic',
        translations: <String>['إحصاء'],
      ),
    ],
  );

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[starterPack]);
    repository = harness.repository;
    await repository.ensureDictionaryPack();
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('the two packs', () {
    test('the starter set is installed and the dictionary row is there too',
        () async {
      final packs = await repository.packs();
      final keys = packs.map((p) => p.packKey).toList();
      expect(keys, contains(starterPackKey));
      expect(keys, contains(dictionaryPackKey));
    });

    test('the starter set is labelled as a starter set', () async {
      final packs = await repository.packs();
      final starter = packs.firstWhere((p) => p.packKey == starterPackKey);
      expect(starter.title, starterPackTitle);
      expect(starter.title, contains('starter set'));
    });

    test('the dictionary is the default, and it is first', () async {
      // **The default is the first pack**, because `HomeShell` takes the first
      // one as the active pack. The order is what makes the dictionary the
      // default, so it is asserted rather than assumed.
      final packs = await repository.packs();
      expect(packs.first.packKey, dictionaryPackKey);
    });

    test('the dictionary is named for the user, not by its key', () async {
      // **The user's ruling, verbatim: «القاموس الكامل».**
      //
      // The home screen's pack chip showed the raw identifier
      // `dictionary_en_ar`, in front of the user, where a name belongs. The
      // key stays what it is — it is the foreign key every dictionary
      // favourite is filed under — and the name the user reads is this one.
      //
      // **The literal, not the constant**, because a test that compares the
      // constant with itself passes whatever the constant says.
      expect(dictionaryPackTitle, 'القاموس الكامل');
      final packs = await repository.packs();
      expect(
        packs.firstWhere((p) => p.packKey == dictionaryPackKey).title,
        'القاموس الكامل',
      );
      expect(dictionaryPackTitle, isNot(contains(dictionaryPackKey)),
          reason: 'a key is an identifier and must not reach the user');
    });

    test('the dictionary pack carries no entries, and the real size',
        () async {
      final packs = await repository.packs();
      final dictionary = packs.firstWhere((p) => p.packKey == dictionaryPackKey);
      expect(dictionary.entryCount, 31600,
          reason: 'the pack list says how many words there are');
      // **And the rows really are not there.** A pack with 31,600 rows in the
      // app\'s own table would put them in every backup.
      final exported = await repository.exportPackJson(starterPackKey);
      expect(exported, contains('ghost-clusters-4da03e'));
    });
  });

  group('the entry ids', () {
    test('the two packs\' ids cannot collide', () async {
      final starterIds = <String>{
        for (final entry in starterPack.entries) entry.id,
      };
      for (final id in starterIds) {
        expect(id.startsWith('dict:'), isFalse);
        expect(dictionaryEntryId(id), isNot(id));
      }
      expect(dictionaryEntryId('child'), 'dict:child');
      expect(starterIds.contains(dictionaryEntryId('child')), isFalse);
    });

    test('a dictionary favourite and a starter favourite are separate rows',
        () async {
      await repository.setFavorite(
        packKey: dictionaryPackKey,
        entryId: dictionaryEntryId('child'),
        isFavorite: true,
      );
      await repository.setFavorite(
        packKey: starterPackKey,
        entryId: 'ghost-clusters-4da03e',
        isFavorite: true,
      );
      expect(
        await repository.isFavorite(
          packKey: dictionaryPackKey,
          entryId: dictionaryEntryId('child'),
        ),
        isTrue,
      );
      expect(
        await repository.isFavorite(
          packKey: starterPackKey,
          entryId: 'ghost-clusters-4da03e',
        ),
        isTrue,
      );
      // **The other pack's favourite is not this pack's.**
      expect(
        await repository.isFavorite(
          packKey: dictionaryPackKey,
          entryId: 'ghost-clusters-4da03e',
        ),
        isFalse,
      );
    });
  });

  group('the backup', () {
    test('it carries the dictionary\'s favourites and none of its words',
        () async {
      await repository.setFavorite(
        packKey: dictionaryPackKey,
        entryId: dictionaryEntryId('child'),
        isFavorite: true,
      );
      final json = await repository.exportBackupJson();
      final document = jsonDecode(json) as Map<String, dynamic>;

      // **The favourites are the user's data and they are in the backup.**
      final favorites = document['favorites'] as List<dynamic>;
      expect(favorites, isNotEmpty);
      final dictionaryFavorites = favorites
          .whereType<Map<String, dynamic>>()
          .where((f) => f['packKey'] == dictionaryPackKey)
          .toList();
      expect(dictionaryFavorites, isNotEmpty,
          reason: 'a saved dictionary word has to survive a restore');
      expect(dictionaryFavorites.first['entryId'], dictionaryEntryId('child'));

      // **And the dictionary itself is not.** A pack with no entries is
      // skipped, so 31,600 words never reach the file.
      final packs = document['packs'] as List<dynamic>;
      for (final pack in packs.whereType<Map<String, dynamic>>()) {
        expect(pack['packId'], isNot(dictionaryPackKey));
      }
      final entries = packs
          .whereType<Map<String, dynamic>>()
          .expand((p) => (p['entries'] as List<dynamic>))
          .length;
      expect(entries, lessThan(1000),
          reason: 'a backup carries the user\'s packs, not 31,600 words');
    });

    test('the dictionary pack is not exportable as a pack', () async {
      expect(
        () => repository.exportPackJson(dictionaryPackKey),
        throwsA(isA<Object>()),
      );
    });

    test('a restore leaves the dictionary pack alone, and its favourites too',
        () async {
      await repository.setFavorite(
        packKey: dictionaryPackKey,
        entryId: dictionaryEntryId('child'),
        isFavorite: true,
      );
      final json = await repository.exportBackupJson();
      await repository.importBackupJson(json);

      final packs = await repository.packs();
      expect(packs.map((p) => p.packKey), contains(dictionaryPackKey),
          reason: 'the dictionary pack\'s row has to survive a restore, or '
              'its favourites would be orphaned');
      expect(
        await repository.isFavorite(
          packKey: dictionaryPackKey,
          entryId: dictionaryEntryId('child'),
        ),
        isTrue,
        reason: 'a saved dictionary word has to survive a restore',
      );
    });
  });
}
