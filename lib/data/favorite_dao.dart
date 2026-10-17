import 'package:lexilearn/domain/backup_document.dart';
import 'package:sqflite/sqflite.dart';

/// The saved words, scoped to the pack they were saved from.
///
/// **[`replace`](replace) takes an `executor` and the other two do not, and the
/// reason is a caller that arrived.** Round 1 of this DAO shipped with no
/// `executor` anywhere, on the reasoning - recorded here, and correct at the time
/// - that no call site reached it from inside a transaction.
/// `docs/engineering-standards.md` section 3 asks for one on every such DAO
/// because a call made without the handle does not fail, it **waits**. Then Task
/// 14's fix round added favourites to the backup, and
/// `VocabRepository.importBackupJson` reached this DAO from inside the
/// transaction it already had. **That is the moment this comment said to add
/// it.** Adding it to one method rather than to all three is deliberate: only
/// [replace] is called from inside a transaction, and a parameter nobody
/// exercises is untested surface pretending to be a guarantee.
///
/// **What the cascade destroys, stated here rather than only implied.** The
/// `ON DELETE CASCADE` on `favorites.pack_key` means *deleting a pack deletes its
/// favourites*. That is right when the user deletes a pack. It was a data-loss
/// bug when `importBackupJson` deleted every `packs` row inside its transaction
/// with no way to write them back - a user restoring a backup lost the whole
/// list, silently. The fix is not to weaken the cascade; it is that
/// `BackupDocument` now carries the favourites and [replace] puts them back
/// inside the same transaction. Pinned by
/// `test/data/vocab_repository_test.dart` -> *a backup carries the user's
/// favourites, and restores them*.
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

  /// Writes one saved word absolutely, used only by backup restore.
  ///
  /// **[executor] is NOT optional-by-omission here.** `importBackupJson` calls
  /// this inside a transaction, and an insert made without the transaction's
  /// handle does not fail - it **waits**, on the Dart-side `_rawLock` that
  /// `transaction()` holds for its whole body. See
  /// `docs/engineering-standards.md` section 3, and the class doc for why the
  /// other two methods deliberately do not take one.
  ///
  /// **`addedAt` is passed in rather than stamped here**, for the same reason
  /// `PackDao.insertPack` takes `importedAt`: every write in this repository
  /// honours the injected `Clock`, so a restored favourite carries the harness's
  /// timestamp instead of the wall clock. `toggle` stamps `DateTime.now()`
  /// internally and does not - an inconsistency recorded in round 1 and left
  /// alone here, because fixing it would change `toggle`'s published signature.
  ///
  /// The backup does **not** carry `added_at`. Nothing reads it: `favoritesIn`
  /// hands back a `Set`, so the list's order comes from the pack's own
  /// `sort_index`. Carrying a timestamp nothing consumes would be a second
  /// source of truth for "when did the user save this" that nothing keeps honest.
  Future<void> replace(
    BackupFavorite favorite, {
    required DateTime addedAt,
    DatabaseExecutor? executor,
  }) =>
      (executor ?? _db).insert(
        'favorites',
        <String, Object?>{
          'pack_key': favorite.packKey,
          'entry_id': favorite.entryId,
          'added_at': addedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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