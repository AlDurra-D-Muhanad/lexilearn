import 'package:sqflite/sqflite.dart';

/// Key/value rows of app settings — currently only the theme choice.
///
/// **Why SQLite and not `shared_preferences`.** `docs/engineering-standards.md`
/// has no rule that names it, but the ruling behind the theme toggle was
/// explicit: *look at what the repository already uses and follow it, do not
/// invent a second storage mechanism*. The only thing this app has ever written
/// to disk is `lexilearn.db`, and every screen's state already survives a restart
/// because it lives there. A second on-disk store — `shared_preferences`, a JSON
/// file, `dart:io` in the documents directory — would be a second thing to back
/// up, a second thing to migrate and a second thing `docs/engineering-standards.md`
/// §12's privacy review has to reason about. One table and one DAO is cheaper than
/// any of those.
///
/// **No `executor` parameter, deliberately, and this is the same reasoning
/// `FavoriteDao`'s class doc records for `toggle`.** §3 asks for an `executor` on
/// every DAO method that *can* be called from inside a transaction. Nothing calls
/// this one from one: the only callers are `AppSettingsController`, which reads
/// and writes from `initState` and from a menu tap. A parameter nobody
/// exercises is untested surface pretending to be a guarantee — so the two
/// methods take the database and nothing else.
///
/// **Writes are absolute and idempotent.** [write] sets the value rather than
/// appending, so choosing `داكن` twice leaves one row, and `null` from [read] is
/// the honest answer for "the user has never chosen" rather than a guess.
class SettingsDao {
  const SettingsDao(this._db);

  final Database _db;

  /// The stored value for [key], or null when nothing has been written.
  Future<String?> read(String key) async {
    final rows = await _db.query(
      'settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// Stores [value] under [key], replacing whatever was there.
  ///
  /// `ConflictAlgorithm.replace` on a primary key of `key` alone, which is what
  /// makes this idempotent — see the class doc.
  Future<void> write(String key, String value) => _db.insert(
        'settings',
        <String, Object?>{'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}