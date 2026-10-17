import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/favorite_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A pack row, which a favourite cannot exist without.
///
/// `favorites.pack_key` carries a foreign key onto `packs(pack_key)` and
/// `_onConfigure` runs `PRAGMA foreign_keys = ON`, so a favourite for a pack that
/// was never installed is rejected outright.
///
/// **The plan's fixture for three of these five tests did not insert one.**
/// Measured: `marking a word stores it` failed with
/// `SqliteException(787): FOREIGN KEY constraint failed` on
/// `INSERT OR REPLACE INTO favorites … parameters: p, a, …`, and so did
/// *un-marking removes it…* and *favourites are scoped per pack*. The defect is in
/// the fixture, not in the schema — the key is what makes the cascade work — so
/// every test that stores a favourite now installs the pack it stores it under.
Future<void> _insertPack(
  Database db, {
  required String packKey,
}) =>
    db.insert('packs', <String, Object?>{
      'pack_key': packKey,
      'title': 'P',
      'source_language': 'en',
      'target_language': 'ar',
      'schema_version': 1,
      'entry_count': 1,
      'is_bundled': 0,
      'imported_at': DateTime.utc(2026, 10, 15).toIso8601String(),
    });

void main() {
  late Database db;
  late FavoriteDao dao;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await openAppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    dao = FavoriteDao(db);
  });

  tearDown(() => db.close());

  test('nothing is a favourite by default', () async {
    expect(await dao.favoritesIn('p'), isEmpty);
  });

  test('marking a word stores it', () async {
    await _insertPack(db, packKey: 'p');
    await dao.toggle(packKey: 'p', entryId: 'a', isFavorite: true);
    expect(await dao.favoritesIn('p'), <String>{'a'});
  });

  test('un-marking removes it, and marking twice is idempotent', () async {
    await _insertPack(db, packKey: 'p');
    await dao.toggle(packKey: 'p', entryId: 'a', isFavorite: true);
    await dao.toggle(packKey: 'p', entryId: 'a', isFavorite: true);
    expect(await dao.favoritesIn('p'), <String>{'a'});

    await dao.toggle(packKey: 'p', entryId: 'a', isFavorite: false);
    expect(await dao.favoritesIn('p'), isEmpty);
  });

  test('favourites are scoped per pack', () async {
    await _insertPack(db, packKey: 'p1');
    await _insertPack(db, packKey: 'p2');
    await dao.toggle(packKey: 'p1', entryId: 'a', isFavorite: true);
    expect(await dao.favoritesIn('p2'), isEmpty);
    // And the row is under the pack it was saved from, not merely absent from the
    // other one — a `WHERE` that ignored its argument would satisfy the line
    // above while returning everything from everywhere.
    expect(await dao.favoritesIn('p1'), <String>{'a'});
  });

  test('favourites are removed when the pack is deleted', () async {
    await _insertPack(db, packKey: 'p');
    await dao.toggle(packKey: 'p', entryId: 'a', isFavorite: true);
    expect(await dao.favoritesIn('p'), <String>{'a'},
        reason: 'the cascade only removes something that was there');

    await db.delete('packs', where: 'pack_key = ?', whereArgs: <Object?>['p']);
    expect(await dao.favoritesIn('p'), isEmpty);
  });

  // The foreign key is declared ON DELETE CASCADE and `_onConfigure` already runs
  // `PRAGMA foreign_keys = ON`, so the cascade needs no extra work — but only if
  // that pragma is really on for this connection. SQLite ships with foreign keys
  // OFF, and a test that deleted the pack with the pragma off would pass the
  // assertion above for the wrong reason: no favourites would be found either.
  // This one fails if the pragma is ever dropped, which the delete test cannot.
  test('the foreign key is enforced, not merely declared', () async {
    await _insertPack(db, packKey: 'p');
    await expectLater(
      dao.toggle(packKey: 'missing', entryId: 'a', isFavorite: true),
      throwsA(isA<DatabaseException>()),
      reason: 'a favourite for a pack that does not exist must be rejected',
    );
  });
}