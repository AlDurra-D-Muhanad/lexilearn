import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/favorite_dao.dart';
import 'package:lexilearn/data/pack_dao.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The starter set, as the asset the app ships would decode it.
const VocabPack _starter = VocabPack(
  schemaVersion: 1,
  packId: starterPackKey,
  title: starterPackTitle,
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'child-1', term: 'child', translations: <String>['طفل']),
    VocabEntry(id: 'calm-1', term: 'calm', translations: <String>['هادئ']),
  ],
);

/// The dictionary's own headword id, in the namespace the dictionary uses.
const String _dictionaryChildId = 'dict:child';

/// **THE FATAL DEFECT, and the test that pins it.**
///
/// The user reported: «كلما اخرج من التطبيق تمسح حزمة المفضلة كليا» — every
/// time I leave the app, the favourites pack is wiped entirely.
///
/// The mechanism was in the data layer and not in the UI: `packs` rows were
/// written with `ConflictAlgorithm.replace`, and **`INSERT OR REPLACE` is a
/// DELETE followed by an INSERT**. The delete fired
/// `favorites.pack_key`'s `ON DELETE CASCADE`, so every favourite filed under
/// that pack key went with it. The dictionary's row is rewritten on **every
/// launch** (`main()` → `ensureDictionaryPack` → `PackDao.insertPackRow`), so
/// every time the user opened the app their saved words were gone.
///
/// **A restart here is a real restart.** `:memory:` cannot express it — a
/// second database at the same `:memory:` path is a *different, empty*
/// database, which is a fresh install rather than a restart. So these tests
/// run against a file on disk, and a restart means: **close the database, open
/// a brand-new `Database` over the same file, and run the app's launch path
/// again.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String path;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexilearn-restart');
    path = '${dir.path}/lexilearn.db';
  });

  tearDown(() {
    // Swallowed on purpose: the sqflite FFI side can still hold the file when
    // the tear-down runs, so the delete intermittently throws — a failure of
    // the *cleanup*, not of the thing under test. The directory lives under the
    // OS temp root and costs nothing if it lives.
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Left behind on purpose rather than failing a green test.
    }
  });

  /// Opens a **fresh** database over the file, with the launch path run.
  ///
  /// `singleInstance: false` is what makes the second open a genuinely new
  /// connection rather than the one sqflite cached by path — the same reason
  /// `TestHarness.create` passes it.
  Future<VocabRepository> launch() async {
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    final repository = VocabRepository(database: db);
    // **The app's launch path, in the order `main()` runs it.**
    await repository.seedBundledPack(PackCodec.encodePack(_starter));
    await repository.ensureDictionaryPack();
    return repository;
  }

  test(
      'a favourite survives the app being closed and opened again — '
      'the dictionary pack', () async {
    // --- the first session ---
    final before = await launch();
    await before.setFavorite(
      packKey: dictionaryPackKey,
      entryId: _dictionaryChildId,
      isFavorite: true,
    );
    expect(
      await before.isFavorite(
        packKey: dictionaryPackKey,
        entryId: _dictionaryChildId,
      ),
      isTrue,
      reason: 'the favourite was saved before the app was closed',
    );

    // --- the restart: the database is closed and a brand-new one is opened ---
    await before.close();

    final after = await launch();

    expect(
      await after.isFavorite(
        packKey: dictionaryPackKey,
        entryId: _dictionaryChildId,
      ),
      isTrue,
      reason: 'the favourite was still there when the app was closed, and the '
          'app writes the dictionary pack row on every launch — writing that '
          'row must not delete the words the user saved',
    );
    await after.close();
  });

  test(
      'a favourite survives the app being closed and opened again — '
      'the starter pack', () async {
    final before = await launch();
    await before.setFavorite(
      packKey: starterPackKey,
      entryId: 'child-1',
      isFavorite: true,
    );
    expect(await before.favorites(starterPackKey), hasLength(1));

    await before.close();

    final after = await launch();

    expect(
      (await after.favorites(starterPackKey)).map((entry) => entry.id),
      <String>['child-1'],
      reason: 'the starter pack is re-seeded on every launch, and a re-seed '
          'must not take the user\'s saved words with it',
    );
    await after.close();
  });

  test('writing the pack row twice does not delete the favourites under it',
      () async {
    // **The DAO-level statement of the same defect**, with no repository and
    // no launch path in the way: the row is written once, a favourite is
    // filed under it, the row is written again, and the favourite is still
    // there.
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    final dao = PackDao(db);
    final favourites = FavoriteDao(db);

    Future<void> writeRow() => dao.insertPackRow(
          PackSummary(
            packKey: dictionaryPackKey,
            title: dictionaryPackTitle,
            sourceLanguage: 'en',
            targetLanguage: 'ar',
            entryCount: 31600,
            isBundled: true,
            importedAt: DateTime.utc(2026, 10, 14, 12),
          ),
        );

    await writeRow();
    await favourites.toggle(
      packKey: dictionaryPackKey,
      entryId: _dictionaryChildId,
      isFavorite: true,
    );
    await writeRow();

    expect(
      await favourites.favoritesIn(dictionaryPackKey),
      <String>{_dictionaryChildId},
      reason: 'rewriting a pack row must not delete the favourites filed '
          'under it — that is what the cascade did, and it is the fatal '
          'defect',
    );
    await db.close();
  });

  test('re-importing a pack does not delete the favourites filed under it',
      () async {
    // **The other replace.** `PackDao.insertPack` used to write the pack's row
    // with `ConflictAlgorithm.replace` as well, so importing an updated copy of
    // a pack the user had favourites in took those favourites with it.
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    final dao = PackDao(db);
    final favourites = FavoriteDao(db);

    await dao.insertPack(_starter, isBundled: true, importedAt: DateTime.now());
    await favourites.toggle(
      packKey: starterPackKey,
      entryId: 'child-1',
      isFavorite: true,
    );
    await dao.insertPack(_starter, isBundled: true, importedAt: DateTime.now());

    expect(
      await favourites.favoritesIn(starterPackKey),
      <String>{'child-1'},
      reason: 're-importing a pack replaces its words, not the user\'s saved '
          'words',
    );
    await db.close();
  });

  test('deleting the pack still deletes its favourites', () async {
    // **The other half of the rule.** The fix is not to weaken the cascade:
    // deleting a pack is the one action that is *meant* to take its
    // favourites with it.
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    final dao = PackDao(db);
    final favourites = FavoriteDao(db);

    await dao.insertPack(_starter, isBundled: true, importedAt: DateTime.now());
    await favourites.toggle(
      packKey: starterPackKey,
      entryId: 'child-1',
      isFavorite: true,
    );
    await dao.deletePack(starterPackKey);

    expect(
      await favourites.favoritesIn(starterPackKey),
      isEmpty,
      reason: 'the cascade is still there: deleting a pack deletes the words '
          'the user saved from it',
    );
    await db.close();
  });

  test('re-importing a pack replaces its words and keeps its progress',
      () async {
    // **The behaviour the explicit delete replaced.** The pack's old entries
    // used to go because the pack's row was deleted and `entries` cascades
    // from `packs`. The row is no longer deleted, so the removal is explicit
    // now — and it has to remove exactly the same rows.
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    final dao = PackDao(db);

    await dao.insertPack(_starter, isBundled: true, importedAt: DateTime.now());
    expect(await dao.countEntries(starterPackKey), 2);

    await dao.insertPack(
      const VocabPack(
        schemaVersion: 1,
        packId: starterPackKey,
        title: starterPackTitle,
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: <VocabEntry>[
          VocabEntry(id: 'child-1', term: 'child', translations: <String>['طفل']),
        ],
      ),
      isBundled: true,
      importedAt: DateTime.now(),
    );

    expect(
      await dao.countEntries(starterPackKey),
      1,
      reason: 'a word the new pack no longer has must not survive the import',
    );
    await db.close();
  });
}
