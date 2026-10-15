import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/pack_dao.dart';
import 'package:lexilearn/data/pack_seeder.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

VocabEntry _entry(String id, String term, List<String> translations) =>
    VocabEntry(id: id, term: term, translations: translations);

VocabPack packNamed(String id, List<String> terms) => VocabPack(
      schemaVersion: 1,
      packId: id,
      title: id,
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: <VocabEntry>[
        for (final term in terms)
          _entry('$id-$term', term, <String>['t-$term']),
      ],
    );

void main() {
  late Database db;
  late PackDao dao;
  final when = DateTime.utc(2026, 10, 14, 12);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await openAppDatabase(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    dao = PackDao(db);
  });

  tearDown(() => db.close());

  test('inserts a pack and reads it back intact', () async {
    final pack = packNamed('p1', <String>['alpha', 'beta']);
    await dao.insertPack(pack, isBundled: true, importedAt: when);

    final stored = await dao.getPack('p1');
    expect(stored, isNotNull);
    expect(stored!.packId, 'p1');
    expect(stored.title, 'p1');
    expect(stored.sourceLanguage, 'en');
    expect(stored.targetLanguage, 'ar');
    expect(stored.entryCount, 2);
    expect(stored.entries.map((e) => e.id), <String>['p1-alpha', 'p1-beta']);
    expect(stored.entries.first.term, 'alpha');
    expect(stored.entries.first.translations, <String>['t-alpha']);
    expect(stored.entries.map((e) => e.note), <String>['', '']);
  });

  test('re-inserting the same pack replaces entries without duplicating them',
      () async {
    await dao.insertPack(packNamed('p1', <String>['a', 'b', 'c']),
        isBundled: true, importedAt: when);
    await dao.insertPack(packNamed('p1', <String>['a']),
        isBundled: true, importedAt: when);

    expect(await dao.countEntries('p1'), 1);
    expect((await dao.getPack('p1'))!.entryCount, 1);
  });

  test('listPacks reports entry counts and the bundled flag', () async {
    // Key order and bundled order deliberately disagree, and the two imported
    // packs disagree on imported_at, so no wrong ORDER BY can pass by luck.
    final older = DateTime.utc(2026, 10, 14, 12);
    final middle = DateTime.utc(2026, 10, 14, 14);
    final newer = DateTime.utc(2026, 10, 14, 18);
    await dao.insertPack(packNamed('zzz_bundled', <String>['a', 'b']),
        isBundled: true, importedAt: older);
    await dao.insertPack(packNamed('aaa_imported', <String>['a']),
        isBundled: false, importedAt: newer);
    await dao.insertPack(packNamed('mmm_imported', <String>['a', 'b', 'c']),
        isBundled: false, importedAt: middle);

    final packs = await dao.listPacks();
    expect(packs.map((p) => p.packKey),
        <String>['zzz_bundled', 'aaa_imported', 'mmm_imported']);
    expect(packs.first.entryCount, 2);
    expect(packs.first.isBundled, isTrue);
    expect(packs.last.isBundled, isFalse);
  });

  test('a rich entry round-trips through the database with every field intact',
      () async {
    final rich = VocabEntry(
      id: 'serenity-9f2b1c',
      term: 'serenity',
      translations: <String>['hudaa', 'sukoon'],
      note: 'noun; state of being calm',
      phonetic: '/səˈrenɪti/',
      partOfSpeech: 'noun',
      synonyms: <String>['calm', 'tranquillity'],
      examples: <String>['a moment of serenity', 'the serenity of the lake'],
    );
    await dao.insertPack(
      VocabPack(
        schemaVersion: 1,
        packId: 'rich_pack',
        title: 'Rich Pack',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: <VocabEntry>[rich],
      ),
      isBundled: false,
      importedAt: when,
    );

    final readBacks = <String, VocabEntry>{
      'getPack': (await dao.getPack('rich_pack'))!.entries.single,
      'entriesOf': (await dao.entriesOf('rich_pack')).single,
    };

    for (final path in readBacks.keys) {
      final entry = readBacks[path]!;
      expect(entry.id, 'serenity-9f2b1c', reason: '$path lost id');
      expect(entry.term, 'serenity', reason: '$path lost term');
      expect(entry.translations, <String>['hudaa', 'sukoon'],
          reason: '$path lost translations');
      expect(entry.note, 'noun; state of being calm', reason: '$path lost note');
      expect(entry.phonetic, '/səˈrenɪti/', reason: '$path lost phonetic');
      expect(entry.partOfSpeech, 'noun', reason: '$path lost partOfSpeech');
      expect(entry.synonyms, <String>['calm', 'tranquillity'],
          reason: '$path lost synonyms');
      expect(entry.examples,
          <String>['a moment of serenity', 'the serenity of the lake'],
          reason: '$path lost examples');
    }
  });

  test('an entry with no extra fields reads back with empty defaults',
      () async {
    await dao.insertPack(packNamed('p1', <String>['a']),
        isBundled: true, importedAt: when);

    final entry = (await dao.entriesOf('p1')).single;
    expect(entry.phonetic, isEmpty);
    expect(entry.partOfSpeech, isEmpty);
    expect(entry.synonyms, isEmpty);
    expect(entry.examples, isEmpty);

    // The columns themselves are never null: absent lists are stored as "[]".
    final row = (await db.query('entries',
            where: 'pack_key = ?', whereArgs: <Object?>['p1']))
        .single;
    expect(row['phonetic'], '');
    expect(row['part_of_speech'], '');
    expect(row['synonyms'], '[]');
    expect(row['examples'], '[]');
  });

  test('getPack returns null for an unknown key', () async {
    expect(await dao.getPack('nope'), isNull);
  });

  test('deleting a pack cascades its entries', () async {
    await dao.insertPack(packNamed('p1', <String>['a', 'b']),
        isBundled: true, importedAt: when);
    await dao.deletePack('p1');
    expect(await dao.countEntries('p1'), 0);
    expect(await dao.listPacks(), isEmpty);
  });

  test('deleting a pack leaves no dangling progress rows', () async {
    await dao.insertPack(
        packNamed('p1', <String>['a']), isBundled: true, importedAt: when);
    await db.insert('word_progress', <String, Object?>{
      'entry_id': 'p1-a',
      'pack_key': 'p1',
      'attempts': 3,
      'correct_count': 2,
      'last_seen_at': when.toIso8601String(),
    });
    await dao.deletePack('p1');

    final rows = await db.query('word_progress',
        where: 'pack_key = ?', whereArgs: <Object?>['p1']);
    expect(rows, isEmpty);
  });

  test('progress survives a pack re-import because ids are stable', () async {
    await dao.insertPack(
        packNamed('p1', <String>['a']), isBundled: true, importedAt: when);
    await db.insert('word_progress', <String, Object?>{
      'entry_id': 'p1-a',
      'pack_key': 'p1',
      'attempts': 3,
      'correct_count': 2,
      'last_seen_at': when.toIso8601String(),
    });
    await dao.insertPack(packNamed('p1', <String>['a', 'b']),
        isBundled: true, importedAt: when);

    final rows = await db.query('word_progress',
        where: 'pack_key = ?', whereArgs: <Object?>['p1']);
    expect(rows.single['attempts'], 3);
  });

  test('seeder inserts the bundled pack once and is a no-op afterwards',
      () async {
    final seeder = PackSeeder(db);
    final json = PackCodec.encodePack(
        packNamed('bundled', <String>['one', 'two']));

    expect(await seeder.seedIfMissing(json), isTrue);
    expect(await seeder.seedIfMissing(json), isFalse);
    expect(await dao.countEntries('bundled'), 2);
    expect((await dao.listPacks()).single.isBundled, isTrue);
  });
}
