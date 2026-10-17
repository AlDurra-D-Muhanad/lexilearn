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
  // that pragma is really on for this connection, and SQLite ships with foreign
  // keys OFF.
  //
  // **Measured, and the comment this replaces said the opposite.** It claimed the
  // delete test "would still pass" with the pragma off, because no favourite would
  // be found either. That is backwards. With the pragma off the cascade does not
  // run, so the row **survives** the delete of its pack and `favoritesIn('p')`
  // still returns `{a}` — so *favourites are removed when the pack is deleted*
  // **FAILS**, which is exactly what makes it a guard on the pragma. Measured by
  // a throwaway probe against this shipped sequence:
  //
  //   PROBE pragma as opened by _onConfigure: [{foreign_keys: 1}]
  //   PROBE pragma after the explicit OFF:   [{foreign_keys: 0}]
  //   PROBE before delete: {a}
  //   PROBE after delete:  {a}
  //   PROBE shipped assertion `isEmpty` holds: false
  //
  // So the delete test **is** the guard, and this sixth test is not redundant
  // with it: it pins the *other* half — that a favourite for a pack that does
  // not exist is rejected at write time rather than silently queued forever.
  test('the foreign key is enforced, not merely declared', () async {
    await _insertPack(db, packKey: 'p');
    await expectLater(
      dao.toggle(packKey: 'missing', entryId: 'a', isFavorite: true),
      throwsA(isA<DatabaseException>()),
      reason: 'a favourite for a pack that does not exist must be rejected',
    );
  });

  // `isFavorite` is the method Task 14 added *beyond* the plan, and its
  // `pack_key` predicate was untested: mutating
  //   where: 'pack_key = ? AND entry_id = ?'   ->   where: 'entry_id = ?'
  // left the whole suite green. `favoritesIn` above has an explicit scoping test
  // for exactly this dimension; `isFavorite` did not, so
  // `WordDetailRoute.packKey`'s doc comment — "favourites are scoped to a pack,
  // so the heart cannot be answered without it" — was a claim with nothing
  // behind it. Two packs, the **same entry id** in both, so only the pack key can
  // tell them apart.
  test('isFavorite is scoped to its pack, not just to the entry id', () async {
    await _insertPack(db, packKey: 'p1');
    await _insertPack(db, packKey: 'p2');
    await dao.toggle(packKey: 'p1', entryId: 'a', isFavorite: true);

    expect(await dao.isFavorite(packKey: 'p1', entryId: 'a'), isTrue);
    expect(
      await dao.isFavorite(packKey: 'p2', entryId: 'a'),
      isFalse,
      reason: 'p2 holds the same entry id and it is not saved there',
    );
    expect(
      await dao.isFavorite(packKey: 'p1', entryId: 'b'),
      isFalse,
      reason: 'and p1 holds a word that was never saved',
    );

    // And it follows the same write the list reads, both ways.
    await dao.toggle(packKey: 'p2', entryId: 'a', isFavorite: true);
    expect(await dao.isFavorite(packKey: 'p2', entryId: 'a'), isTrue);
    expect(await dao.isFavorite(packKey: 'p1', entryId: 'a'), isTrue,
        reason: 'saving in one pack must not unsave the other');
    await dao.toggle(packKey: 'p1', entryId: 'a', isFavorite: false);
    expect(await dao.isFavorite(packKey: 'p1', entryId: 'a'), isFalse);
    expect(await dao.isFavorite(packKey: 'p2', entryId: 'a'), isTrue);
  });
}