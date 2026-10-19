import 'package:lexilearn/core/clock.dart';
import 'package:lexilearn/domain/backup_codec.dart';
import 'package:lexilearn/domain/backup_document.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:lexilearn/domain/search_matcher.dart';
import 'package:lexilearn/domain/stats_summary.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/domain/word_progress.dart';
import 'package:sqflite/sqflite.dart';

import 'favorite_dao.dart';
import 'pack_dao.dart';
import 'progress_dao.dart';
import 'session_dao.dart';
import 'settings_dao.dart';

/// The only class the UI layer is allowed to know about.
class VocabRepository {
  VocabRepository({required Database database, Clock? clock})
      : _db = database,
        _packs = PackDao(database),
        _progress = ProgressDao(database),
        _sessions = SessionDao(database),
        _favorites = FavoriteDao(database),
        _settings = SettingsDao(database),
        _clock = clock ?? DateTime.now;

  final Database _db;
  final PackDao _packs;
  final ProgressDao _progress;
  final SessionDao _sessions;
  final FavoriteDao _favorites;
  final SettingsDao _settings;
  final Clock _clock;

  // --- settings ---------------------------------------------------------------
  //
  // The theme preference and nothing else, so far. Two thin forwarders rather
  // than a `SettingsDao` handed to the UI layer, for the reason every other DAO
  // here is private: `VocabRepository`'s own doc comment says it is the only
  // class the UI layer is allowed to know about, and a screen that reached for
  // `SettingsDao` directly would be the first thing in `lib/ui/` to hold a
  // `Database`.

  /// The stored value for [key], or null when nothing has been written.
  ///
  /// Null is the honest answer for "the user has never chosen" and the only
  /// thing `AppSettingsController` treats as an error-free state.
  Future<String?> setting(String key) => _settings.read(key);

  /// Stores [value] under [key], replacing whatever was there.
  Future<void> setSetting(String key, String value) =>
      _settings.write(key, value);

  Future<List<PackSummary>> packs() => _packs.listPacks();

  Future<List<VocabEntry>> entries(String packKey) => _packs.entriesOf(packKey);

  /// Looks the pack up, then hands the comparison to `SearchMatcher`.
  ///
  /// The matching rule itself lives in `lib/domain/search_matcher.dart` and is
  /// not restated here: two copies of a normalisation rule is how a bidi mark
  /// ends up stripped on one path and not the other.
  Future<List<VocabEntry>> search({
    required String packKey,
    required String query,
  }) async =>
      SearchMatcher.filter(await _packs.entriesOf(packKey), query);

  Future<VocabPack> importPack(String jsonText) async {
    // Decode first: a bad file must never reach the database, so a failed
    // import leaves the previous state exactly as it was.
    final pack = PackCodec.decodePack(jsonText);
    await _packs.insertPack(pack, isBundled: false, importedAt: _clock());
    return pack;
  }

  Future<String> exportPackJson(String packKey) async {
    final pack = await _packs.getPack(packKey);
    if (pack == null) {
      throw PackDecodeException('No vocabulary pack named "$packKey" is installed.');
    }
    return PackCodec.encodePack(pack);
  }

  Future<void> deletePack(String packKey) => _packs.deletePack(packKey);

  /// Saves or removes one word, per [isFavorite].
  ///
  /// Sets the state rather than inverting it; see
  /// [FavoriteDao.toggle] for why that is the shape worth having.
  Future<void> setFavorite({
    required String packKey,
    required String entryId,
    required bool isFavorite,
  }) =>
      _favorites.toggle(
        packKey: packKey,
        entryId: entryId,
        isFavorite: isFavorite,
      );

  /// Whether one word in [packKey] is saved.
  ///
  /// What the word detail screen's heart needs on opening, and the only reason
  /// [FavoriteDao] has a method beyond the two the favourites list itself uses.
  Future<bool> isFavorite({
    required String packKey,
    required String entryId,
  }) =>
      _favorites.isFavorite(packKey: packKey, entryId: entryId);

  /// Every saved word in [packKey], as entries, in the pack's own order.
  ///
  /// **Two round trips, and the second is skipped when there is nothing to
  /// resolve.** `favoritesIn` answers with ids; the entries themselves live in
  /// `entries`, which this repository already reads for search and for the home
  /// screen. Resolving here rather than joining in SQL keeps `FavoriteDao` from
  /// needing to know the `entries` table at all.
  ///
  /// The order is `sort_index` — the same order a search result and the
  /// flashcards deck use — because the loop walks [all] and tests membership,
  /// rather than walking the id set. A favourites list that ordered itself by
  /// `added_at` would be the only list in the app doing so.
  ///
  /// An empty pack key answers with nothing rather than querying for it, for the
  /// reason `HomeScreen._loadPack` gives: an empty key is `HomeShell`'s start-up
  /// window, not a missing pack, and asking would turn a normal frame into an
  /// error state.
  Future<List<VocabEntry>> favorites(String packKey) async {
    if (packKey.isEmpty) return const <VocabEntry>[];
    final ids = await _favorites.favoritesIn(packKey);
    if (ids.isEmpty) return const <VocabEntry>[];
    final all = await _packs.entriesOf(packKey);
    return all.where((entry) => ids.contains(entry.id)).toList();
  }

  /// Installs the bundled asset on first launch, and after the user deletes it.
  /// Returns false when the pack is already present, so it is safe to call on
  /// every start.
  ///
  /// Deliberately does the work here rather than delegating to `PackSeeder`:
  /// `PackSeeder.seedIfMissing` stamps `DateTime.now()` internally and cannot be
  /// given this repository's [Clock], so seeding wrote a wall-clock timestamp
  /// while every other write honoured the injected one.
  Future<bool> seedBundledPack(String assetJson) async {
    // Decode first, same rule as [importPack]: a corrupt asset must never
    // reach the database.
    final pack = PackCodec.decodePack(assetJson);
    final existing = await _packs.listPacks();
    if (existing.any((summary) => summary.packKey == pack.packId)) return false;
    await _packs.insertPack(pack, isBundled: true, importedAt: _clock());
    return true;
  }

  Future<void> close() => _db.close();

  Future<void> recordAnswer({
    required String packKey,
    required String entryId,
    required bool wasCorrect,
  }) =>
      _progress.record(
          packKey: packKey, entryId: entryId, wasCorrect: wasCorrect, at: _clock());

  Future<int> finishSession({
    required String packKey,
    required DateTime startedAt,
    required int totalQuestions,
    required int correctCount,
  }) =>
      _sessions.insert(QuizSessionResult(
        packKey: packKey,
        startedAt: startedAt,
        totalQuestions: totalQuestions,
        correctCount: correctCount,
      ));

  Future<StatsSummary> stats(String packKey) async {
    final progressRows = await _progress.allForPack(packKey);
    return StatsSummary(
      totalAttempts:
          progressRows.fold<int>(0, (sum, row) => sum + row.attempts),
      totalCorrect: progressRows.fold<int>(0, (sum, row) => sum + row.correct),
      wordsPracticed: progressRows.length,
      wordsMastered: progressRows.where((row) => row.isMastered).length,
      // Scoped to this pack like every other field here. Returning every
      // pack's sessions would put a foreign session under tiles that are all
      // counting this pack's words.
      recentSessions: await _sessions.recent(packKey: packKey),
    );
  }

  /// Clears a pack's progress AND its session history.
  ///
  /// Both halves are in one transaction so a failure mid-reset cannot leave a
  /// pack with zeroed word counts and a full "Recent sessions" list — which
  /// reads, to the user, exactly like Reset did nothing.
  Future<int> resetProgress(String packKey) async {
    return _db.transaction<int>((txn) async {
      final cleared = await _progress.reset(packKey, executor: txn);
      await _sessions.deleteForPack(packKey, executor: txn);
      return cleared;
    });
  }

  /// Everything on this device, as one JSON document: every pack with all of its
  /// entries, every word's progress, the session history, and **every word the
  /// user saved by hand.** This is the file a user saves to Drive or Dropbox, and
  /// the file [importBackupJson] reads back.
  ///
  /// **The saved words are in here because without them a restore was data loss.**
  /// `favorites.pack_key` carries `ON DELETE CASCADE` and [importBackupJson]
  /// deletes every `packs` row inside its transaction, so restoring a file that
  /// did not carry favourites wiped the user's whole list - silently, with no
  /// error and no test. `BackupDocument`'s own contract is that restoring it puts
  /// a new phone back where the old one was, and a curated list is part of where
  /// the old phone was. Pinned by `test/data/vocab_repository_test.dart` ->
  /// *a backup carries the user's favourites, and restores them*.
  ///
  /// **Every pack is walked separately on purpose.** `word_progress` and
  /// `favorites` are both keyed on `(pack_key, entry_id)`, so a backup has to
  /// gather one pack's rows at a time rather than assume there is a single active
  /// pack.
  Future<String> exportBackupJson() async {
    final summaries = await _packs.listPacks();
    final packs = <VocabPack>[];
    final progress = <WordProgress>[];
    final favorites = <BackupFavorite>[];
    for (final summary in summaries) {
      final pack = await _packs.getPack(summary.packKey);
      // A pack row whose entries have gone is skipped rather than exported as an
      // empty vocabulary list: it would restore as a real pack that cannot be
      // searched, quizzed or studied.
      if (pack != null) packs.add(pack);
      progress.addAll(await _progress.allForPack(summary.packKey));
      // Read *after* the `getPack` null check above, so a favourite is never
      // exported for a pack this file does not contain - it would restore as an
      // insert the foreign key rejects, failing the whole restore.
      for (final entryId in await _favorites.favoritesIn(summary.packKey)) {
        favorites.add(BackupFavorite(packKey: summary.packKey, entryId: entryId));
      }
    }
    return BackupCodec.encode(BackupDocument(
      exportedAt: _clock(),
      packs: packs,
      progress: progress,
      favorites: favorites,
      // Capped, deliberately: a year of daily quizzes is a few hundred rows and
      // the file is meant to be readable by a person. There is no screen in the
      // app that would notice the difference.
      sessions: await _sessions.recent(limit: 1000),
    ));
  }

  /// Replaces packs, progress, and sessions in a single transaction, returning
  /// how many packs were restored. A failure part-way leaves the device exactly
  /// as it was.
  ///
  /// The document is decoded **before** the transaction opens, so a rejected
  /// file never reaches the database at all — the same ordering
  /// [importPack] uses, and for the same reason.
  ///
  /// **CRITICAL: every DAO call inside the transaction receives `executor: txn`,
  /// and there are EIGHT of them.** A call made without the transaction's handle
  /// does not fail fast — **it waits**, with no exception, no log line and no
  /// timeout message you wrote. `docs/engineering-standards.md` §3, and the
  /// mechanism is read out of `sqflite_common-2.5.14` rather than recalled:
  ///
  /// * `transaction()` (`:894-902`) wraps its whole body in `txnWriteSynchronized`,
  ///   which takes `_rawLock` — a **Dart-side non-reentrant `Lock`** declared at
  ///   `:496`.
  /// * `txnSynchronized` (`:549-592`) runs straight through when it is handed
  ///   the transaction, and otherwise queues on `_rawLock.synchronized(…)`. Its
  ///   own comment reads *"synchronized call to the database / not re-entrant"*.
  /// * after `utils.lockWarningDuration` — 10 s, `constant.dart:174` —
  ///   `utils.dart:43-49` prints `Warning database has been locked … Make sure
  ///   you always use the transaction object for database operations during a
  ///   transaction`.
  /// * `sqflite_common_ffi-2.4.4/lib/src/sqflite_ffi_impl.dart:275-315` queues
  ///   them on the FFI side as well: `handleTransactionId`, *"If a transaction is
  ///   in progress and we are not in it, queue for later"*.
  ///
  /// **It is the same `Database` object, not a second connection, and this has
  /// nothing to do with a SQLite file lock.** `:423` opens with `BEGIN IMMEDIATE`
  /// rather than a deferred `BEGIN`, and the block is not data-dependent: the
  /// first call inside the transaction blocks whether it reads or writes and
  /// whether the table is empty. (Both of those were the wrong story in the first
  /// version of this comment.)
  ///
  /// The eight, and why each one is easy to forget:
  ///
  /// | # | Call | Easy to forget because |
  /// |---|---|---|
  /// | 1 | `_packs.listPacks(executor: txn)` | — |
  /// | 2 | `_progress.reset(..., executor: txn)` | already had the parameter from Task 7 |
  /// | 3 | `_sessions.deleteForPack(..., executor: txn)` | already had it from Task 7 |
  /// | 4 | `_packs.deletePack(..., executor: txn)` | `PackDao` had no `executor` on any method until this task |
  /// | 5 | `_packs.insertPack(..., executor: txn)` | same |
  /// | 6 | `_favorites.replace(..., executor: txn)` | `FavoriteDao` had no `executor` at all until Task 14's fix round added favourites to the backup |
  /// | 7 | `_progress.replace(..., executor: txn)` | written by this task, in the same loop |
  /// | 8 | `_sessions.insert(..., executor: txn)` | same |
  ///
  /// Because the failure mode is a hang and not an error, a missing argument is
  /// invisible to CI. `test/data/vocab_repository_test.dart` → *restore completes
  /// inside five seconds* is the guard: it bounds the future with
  /// `.timeout(Duration(seconds: 5))`, so the regression surfaces as a red test.
  /// **Its fixture carries a saved word on purpose** — site 6 is only *reached*
  /// when the file holds a favourite, so without one the guard would sit at 7/8
  /// and look complete.
  Future<int> importBackupJson(String jsonText) async {
    final backup = BackupCodec.decode(jsonText);
    await _db.transaction((txn) async {
      // **A LANDMINE, and this comment is the only thing standing in front of
      // it.** Sites 2 and 3 below look redundant: `PackDao.deletePack` already
      // deletes `word_progress` and `quiz_sessions` for the pack
      // (`pack_dao.dart:123-126`), so a "simplification" that drops the two
      // explicit deletes is *semantically* correct and *silently* drops the guard
      // from 7/7 to 5/7 — sites 2 and 3 become unreachable, nothing fails, and
      // `test/data/vocab_repository_test.dart`'s executor guard stops proving
      // anything about them. Kept, and asserted on, so that "it was redundant" is
      // a reading of this comment rather than a change somebody makes.
      for (final summary in await _packs.listPacks(executor: txn)) {
        await _progress.reset(summary.packKey, executor: txn);
        await _sessions.deleteForPack(summary.packKey, executor: txn);
        await _packs.deletePack(summary.packKey, executor: txn);
      }
      for (final pack in backup.packs) {
        await _packs.insertPack(pack,
            isBundled: false, importedAt: _clock(), executor: txn);
      }
      // Immediately after the packs, and before the other two loops, because
      // `favorites.pack_key` is a foreign key onto `packs(pack_key)`: a saved
      // word written before its pack exists is rejected by SQLite, which would
      // roll the whole restore back with a raw constraint error rather than a
      // sentence.
      for (final favorite in backup.favorites) {
        await _favorites.replace(favorite, addedAt: _clock(), executor: txn);
      }
      for (final row in backup.progress) {
        await _progress.replace(row, executor: txn);
      }
      for (final session in backup.sessions) {
        await _sessions.insert(session, executor: txn);
      }
    });
    return backup.packs.length;
  }
}