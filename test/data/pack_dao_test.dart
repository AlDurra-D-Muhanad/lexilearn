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
    expect(stored!.entryCount, 2);
    expect(stored.entries.first.term, 'alpha');
    expect(stored.entries.first.translations, <String>['t-alpha']);
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
    await dao.insertPack(packNamed('p1', <String>['a', 'b']),
        isBundled: true, importedAt: when);
    await dao.insertPack(packNamed('p2', <String>['a']),
        isBundled: false, importedAt: when);

    final packs = await dao.listPacks();
    expect(packs.map((p) => p.packKey), <String>['p1', 'p2']);
    expect(packs.first.entryCount, 2);
    expect(packs.first.isBundled, isTrue);
    expect(packs.last.isBundled, isFalse);
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