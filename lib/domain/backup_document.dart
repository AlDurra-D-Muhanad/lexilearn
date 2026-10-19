// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

import 'quiz_session_result.dart';
import 'vocab_pack.dart';
import 'word_progress.dart';

/// One file that contains everything: every pack, every word's progress, every
/// finished session, and every word the user saved. Restoring it puts a new
/// phone back where the old one was.
///
/// **Pure Dart, deliberately.** No `package:flutter` import reaches this
/// directory — `lib/domain/` is the layer the whole app is built on and the one
/// the tests can run without a widget binding. The restore path that writes
/// these four lists back into SQLite lives in `lib/data/vocab_repository.dart`.
@immutable
class BackupDocument {
  const BackupDocument({
    required this.exportedAt,
    required this.packs,
    required this.progress,
    required this.sessions,
    this.favorites = const <BackupFavorite>[],
  });

  /// **This is the backup *file's* version, and it is not
  /// `databaseSchemaVersion`.** They are two different numbers with two different
  /// jobs: that one versions the app's SQLite schema, this one versions the shape
  /// of the JSON a user saves to Drive. They moved apart in Task 14's fix round,
  /// when `favorites` was added to the file while the database stayed at v1.
  ///
  /// **They are both 2 now, and that is a coincidence.** The database moved to 2
  /// later and for an unrelated reason — the `settings` table the theme toggle
  /// persists into. So nothing may now rely on the two numbers differing, and the
  /// test that used to say so has been re-expressed around what is actually true:
  /// `BackupCodec` reads *this* constant and `PackCodec` reads
  /// `VocabPack.currentSchemaVersion`, which is why the identical number is
  /// accepted in a backup file and refused in a pack file. See
  /// *the backup file version and the database version are two counters* and *the
  /// same version number means different things to the two formats* in
  /// `test/domain/backup_codec_test.dart`.
  ///
  /// It went to **2** because a v1 file has no `favorites` key at all, and
  /// decoding one as "no favourites" would wipe the new phone's saved words on
  /// the restore. That is the exact data loss adding favourites was meant to stop,
  /// reintroduced from the other side — so an older file is **refused, by name**,
  /// rather than half-read. The cost is stated here rather than discovered: a user
  /// who exports with this build cannot restore that file with an older build.
  /// `BackupCodec` refuses it with a sentence naming the version it reads.
  static const int currentSchemaVersion = 2;

  /// When the file was written, always stored as a UTC ISO-8601 string.
  final DateTime exportedAt;

  /// Full pack contents, not just the summary rows: an entry that is not in
  /// here is a word the restored phone cannot search, quiz or study.
  final List<VocabPack> packs;

  /// Per-word history. Keyed by `(packKey, entryId)`, which is why this is a
  /// flat list of pairs rather than anything nested under [packs].
  final List<WordProgress> progress;

  /// Finished sessions, so the "recent sessions" card is not empty on a restored
  /// phone.
  final List<QuizSessionResult> sessions;

  /// The words the user saved by hand.
  ///
  /// **The one list in this file that is a decision rather than a record.**
  /// Progress and sessions are the app's own account of what the user did and can
  /// be rebuilt by doing it again; a favourite is a curation, and nothing else
  /// anywhere records which words a person cared about. It is here because
  /// `favorites.pack_key` carries `ON DELETE CASCADE` and
  /// `VocabRepository.importBackupJson` deletes every `packs` row inside its
  /// transaction — so a restore used to destroy the whole list, silently, with no
  /// warning and no error. Pinned by
  /// `test/data/vocab_repository_test.dart` → *a backup carries the user's
  /// favourites, and restores them*.
  final List<BackupFavorite> favorites;
}

/// One saved word: which pack it belongs to and which word in it.
///
/// A flat pair rather than something nested under a pack, for the same reason
/// [BackupDocument.progress] is: `favorites` is keyed `(packKey, entryId)`, and
/// the same word id can be saved in two different packs.
@immutable
class BackupFavorite {
  const BackupFavorite({required this.packKey, required this.entryId});

  final String packKey;
  final String entryId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupFavorite &&
          other.packKey == packKey &&
          other.entryId == entryId;

  // Structural, for the same reason [WordProgress] hashes its list fields: two
  // equal favourites built from different literals must compare and hash alike.
  @override
  int get hashCode => Object.hash(packKey, entryId);

  @override
  String toString() => 'BackupFavorite($packKey, $entryId)';
}
