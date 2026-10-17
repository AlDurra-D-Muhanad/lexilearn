import 'package:sqflite/sqflite.dart';

/// The saved words, scoped to the pack they were saved from.
///
/// **No `executor` parameter, and that is a decision rather than an oversight.**
/// `docs/engineering-standards.md` §3 asks that every DAO reachable from inside
/// a transaction accept one, and the reason it asks is real: a DAO call made
/// without the transaction's handle does not fail, it **waits**. But no caller
/// reaches this DAO from a transaction today — checked by reading every call
/// site in `lib/`, not by assuming.
///
/// The one transaction that deletes packs, `VocabRepository.importBackupJson`,
/// clears their favourites through SQLite's own `ON DELETE CASCADE` rather than
/// through a call here, so it has no `FavoriteDao` call to miss an argument on.
/// Adding an unused parameter would be untested surface pretending to be a
/// guarantee, and a guarantee nobody exercises is the thing §3 is about. The
/// caller that needs one is the moment to add it.
class FavoriteDao {
  const FavoriteDao(this._db);

  final Database _db;

  /// Saves the word when [isFavorite], and removes it otherwise.
  ///
  /// **Named `toggle` and shaped as a set, not an inversion.** The caller passes
  /// the state it wants rather than "flip whatever is there", so a tap that
  /// arrives twice — or a rebuild that replays one — cannot un-save a word that
  /// was never saved. Idempotence is a property of this method, not of whoever
  /// sequences the calls, and `favorite_dao_test.dart` pins it: marking twice
  /// leaves one row.
  ///
  /// `ConflictAlgorithm.replace` is what makes marking twice idempotent; the
  /// primary key is `(pack_key, entry_id)`.
  Future<void> toggle({
    required String packKey,
    required String entryId,
    required bool isFavorite,
  }) async {
    if (!isFavorite) {
      await _db.delete(
        'favorites',
        where: 'pack_key = ? AND entry_id = ?',
        whereArgs: <Object?>[packKey, entryId],
      );
      return;
    }
    await _db.insert(
      'favorites',
      <String, Object?>{
        'pack_key': packKey,
        'entry_id': entryId,
        'added_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Whether one word in [packKey] is saved.
  ///
  /// **`limit: 1` and no `Set`**, because the only caller is the word detail
  /// screen's start-up read, which asks about a single word. Reading
  /// [favoritesIn] and testing membership would be correct and would scan every
  /// favourite on the device to answer a yes/no question about one of them.
  Future<bool> isFavorite({
    required String packKey,
    required String entryId,
  }) async {
    final rows = await _db.query(
      'favorites',
      columns: <String>['entry_id'],
      where: 'pack_key = ? AND entry_id = ?',
      whereArgs: <Object?>[packKey, entryId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Every saved word's id in [packKey].
  ///
  /// A `Set`, so **the order of the favourites is not decided here** and no
  /// caller may read one out of it. The screen's order is the pack's own
  /// `sort_index`, which `PackDao.entriesOf` already applies — that is the order
  /// a search result and the flashcards deck use, and a favourites list that
  /// ordered itself differently from the rest of the app would be the odd one
  /// out. `added_at` is stored but not sorted on; nothing on screen claims a
  /// "newest first" order, so sorting would invent one.
  ///
  /// Ids rather than entries on purpose: this is the only question the
  /// favourites *table* can answer, and `VocabRepository.favorites` is where the
  /// ids are resolved against the pack's rows. A join here would make this DAO
  /// know about `entries`, which it has no other reason to.
  Future<Set<String>> favoritesIn(String packKey) async {
    final rows = await _db.query(
      'favorites',
      columns: <String>['entry_id'],
      where: 'pack_key = ?',
      whereArgs: <Object?>[packKey],
    );
    return rows.map((row) => row['entry_id']! as String).toSet();
  }
}