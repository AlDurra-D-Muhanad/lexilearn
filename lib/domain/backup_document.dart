// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

import 'quiz_session_result.dart';
import 'vocab_pack.dart';
import 'word_progress.dart';

/// One file that contains everything: every pack, every word's progress, and
/// every finished session. Restoring it puts a new phone back where the old one
/// was.
///
/// **Pure Dart, deliberately.** No `package:flutter` import reaches this
/// directory — `lib/domain/` is the layer the whole app is built on and the one
/// the tests can run without a widget binding. The restore path that writes
/// these three lists back into SQLite lives in `lib/data/vocab_repository.dart`.
@immutable
class BackupDocument {
  const BackupDocument({
    required this.exportedAt,
    required this.packs,
    required this.progress,
    required this.sessions,
  });

  /// Bump only when the on-disk shape changes, and read the old shape in
  /// `BackupCodec`. A backup written by an older build must stay readable or the
  /// user has no way back.
  static const int currentSchemaVersion = 1;

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
}
