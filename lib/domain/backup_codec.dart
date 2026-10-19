import 'dart:convert';

import 'backup_document.dart';
import 'dictionary_pack.dart';
import 'pack_codec.dart';
import 'quiz_session_result.dart';
import 'vocab_pack.dart';
import 'word_progress.dart';

/// Reads and writes the one file that carries packs, progress, sessions and the
/// user's saved words.
///
/// **Every failure throws `PackDecodeException`**, not `FormatException` and not
/// a bare `TypeError`. The UI renders `message` verbatim, so a malformed or
/// wrongly-shaped file reaches the user as one readable sentence rather than as
/// a stack trace — and the restore path decodes *before* it opens a
/// transaction, so a rejected file never touches the database at all.
class BackupCodec {
  const BackupCodec._();

  /// The marker that separates the two file kinds, both of which are `.json` and
  /// both of which a user might hand to either action.
  ///
  /// This one string is why `PackCodec.packFromDocument` can say "that is a
  /// backup, use Restore backup" instead of failing on a missing `entries` list,
  /// and why [decode] can reject a plain pack with the mirror-image message.
  static const String kind = 'backup';

  /// Indented on purpose: this is the file a user is told they can read and
  /// hand-edit, and a single-line JSON blob of 300 entries defeats that.
  static String encode(BackupDocument document) =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'kind': kind,
        'schemaVersion': BackupDocument.currentSchemaVersion,
        'exportedAt': document.exportedAt.toUtc().toIso8601String(),
        'packs': <Map<String, Object?>>[
          for (final pack in document.packs) pack.toJson(),
        ],
        'progress': <Map<String, Object?>>[
          for (final row in document.progress)
            <String, Object?>{
              'entryId': row.entryId,
              'packKey': row.packKey,
              'attempts': row.attempts,
              'correct': row.correct,
              'lastSeenAt': row.lastSeenAt?.toUtc().toIso8601String(),
            },
        ],
        'sessions': <Map<String, Object?>>[
          for (final session in document.sessions)
            <String, Object?>{
              'packKey': session.packKey,
              'startedAt': session.startedAt.toUtc().toIso8601String(),
              'totalQuestions': session.totalQuestions,
              'correctCount': session.correctCount,
            },
        ],
        'favorites': <Map<String, Object?>>[
          for (final favorite in document.favorites)
            <String, Object?>{
              'packKey': favorite.packKey,
              'entryId': favorite.entryId,
            },
        ],
      });

  static BackupDocument decode(String jsonText) {
    // `decodeDocument` owns "not JSON at all" and "root is not an object", so
    // there is exactly one place that reports those two, whatever the caller.
    final document = PackCodec.decodeDocument(jsonText);

    if (document['kind'] != kind) {
      throw const PackDecodeException(
          'This is not a backup file. Import it as a vocabulary pack instead.');
    }

    final version = (document['schemaVersion'] as num?)?.toInt();
    if (version != BackupDocument.currentSchemaVersion) {
      throw PackDecodeException(
          'Unsupported backup version $version. This app reads version '
          '${BackupDocument.currentSchemaVersion}.');
    }

    final exportedAtRaw = document['exportedAt'];
    if (exportedAtRaw is! String) {
      throw const PackDecodeException('The backup is missing "exportedAt".');
    }

    final packs = <VocabPack>[
      for (final raw in _list(document, 'packs'))
        VocabPack.fromJson((raw as Map<dynamic, dynamic>).cast<String, Object?>()),
    ];
    final progress = <WordProgress>[
      for (final raw in _list(document, 'progress'))
        _progressFromJson((raw as Map<dynamic, dynamic>).cast<String, Object?>()),
    ];
    final sessions = <QuizSessionResult>[
      for (final raw in _list(document, 'sessions'))
        _sessionFromJson((raw as Map<dynamic, dynamic>).cast<String, Object?>()),
    ];
    final favorites = <BackupFavorite>[
      for (final raw in _list(document, 'favorites'))
        _favoriteFromJson((raw as Map<dynamic, dynamic>).cast<String, Object?>()),
    ];
    _checkFavoritesResolve(packs, favorites);

    return BackupDocument(
      exportedAt: DateTime.parse(exportedAtRaw),
      packs: packs,
      progress: progress,
      sessions: sessions,
      favorites: favorites,
    );
  }

  /// Every saved word must name a pack **this file carries**.
  ///
  /// `favorites.pack_key` is a real foreign key onto `packs(pack_key)`, so a file
  /// whose `favorites` block names a pack the document does not contain cannot be
  /// restored at all. Left uncaught it failed deep inside the restore with a raw
  /// `SqfliteFfiException(sqlite_error: 787)` — SQLite's constraint, not a
  /// message. The transaction rolled back and the device was untouched, so it was
  /// never data loss; but this codec advertises the file as one a user is told
  /// they can hand-edit, and **every other malformed input here becomes a
  /// sentence.** This one was the exception, and it is now not.
  ///
  /// **Checked here rather than caught around the transaction**, for the reason
  /// `importBackupJson` decodes before it opens one: the pack ids are in hand, and
  /// refusing before any write means the device is never touched at all.
  ///
  /// **Only the pack is checked. An unknown `entry_id` is deliberately allowed**
  /// — see `_checkFavoritesResolve`'s caller in
  /// `test/data/vocab_repository_test.dart` →
  /// *a saved word whose entry the pack no longer has is KEPT, and shown as none*.
  /// There is no foreign key onto `entries` on purpose, so a row may outlive the
  /// word it names; dropping it would destroy a curation for a pack whose entries
  /// could come back.
  ///
  /// **The dictionary pack is the one exception, and it is not an oversight.**
  /// The dictionary is reference data: it is not carried in the backup — 25 MB
  /// of it must never reach a file the user emails to themselves — but its **row**
  /// survives a restore, because the row is what the `favorites` foreign key
  /// points at. A saved dictionary word is the user's data and it is in the
  /// backup; the words it names are not.
  static void _checkFavoritesResolve(
    List<VocabPack> packs,
    List<BackupFavorite> favorites,
  ) {
    if (favorites.isEmpty) return;
    final packIds = <String>{for (final pack in packs) pack.packId};
    for (final favorite in favorites) {
      if (packIds.contains(favorite.packKey)) continue;
      if (favorite.packKey == dictionaryPackKey) continue;
      // The **first** offender, named specifically: a user with a 300-word file
      // needs to know which line to fix, not that favourites are involved.
      throw PackDecodeException(
          'The backup\'s "favorites" saves "${favorite.entryId}" under a pack called '
          '"${favorite.packKey}", and this file has no pack by that name. Either the '
          'pack was removed before it was exported, or the file was edited.');
    }
  }

  /// A missing list is an **empty** list, not an error.
  ///
  /// Measured, not assumed: the plan's version wrote
  /// `(document['progress'] as List<dynamic>? ?? const [])`, which treats "key
  /// absent" and "key null" as empty but throws a raw `TypeError` on any *other*
  /// non-list value — and a raw `TypeError` is not a `PackDecodeException`, so
  /// `PacksController`'s `on PackDecodeException` handler would miss it and the
  /// user would watch an exception escape instead of reading a sentence.
  static List<dynamic> _list(Map<String, Object?> document, String key) {
    final value = document[key];
    if (value == null) return const <dynamic>[];
    if (value is! List) {
      throw PackDecodeException('The backup\'s "$key" is not a list.');
    }
    return value;
  }

  static WordProgress _progressFromJson(Map<String, Object?> json) => WordProgress(
        entryId: json['entryId'] as String,
        packKey: json['packKey'] as String,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        correct: (json['correct'] as num?)?.toInt() ?? 0,
        lastSeenAt: json['lastSeenAt'] == null
            ? null
            : DateTime.parse(json['lastSeenAt']! as String),
      );

  static QuizSessionResult _sessionFromJson(Map<String, Object?> json) =>
      QuizSessionResult(
        packKey: json['packKey'] as String,
        startedAt: DateTime.parse(json['startedAt']! as String),
        totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 0,
        correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
      );

  /// Both keys are required, not defaulted.
  ///
  /// A missing `packKey` would produce a favourite that restores under a pack
  /// that does not exist, and the foreign key would reject the whole restore with
  /// a raw SQLite error instead of a sentence — so a `null` is caught here, where
  /// `BackupCodec` can throw the `PackDecodeException` its doc promises.
  static BackupFavorite _favoriteFromJson(Map<String, Object?> json) {
    final packKey = json['packKey'];
    final entryId = json['entryId'];
    if (packKey is! String || entryId is! String) {
      throw const PackDecodeException(
          'A saved word in the backup is missing its pack or its word id.');
    }
    return BackupFavorite(packKey: packKey, entryId: entryId);
  }
}
