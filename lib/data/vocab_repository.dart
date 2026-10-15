import 'package:lexilearn/core/clock.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:lexilearn/domain/stats_summary.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite/sqflite.dart';

import 'pack_dao.dart';
import 'progress_dao.dart';
import 'session_dao.dart';

/// The only class the UI layer is allowed to know about.
class VocabRepository {
  VocabRepository({required Database database, Clock? clock})
      : _db = database,
        _packs = PackDao(database),
        _progress = ProgressDao(database),
        _sessions = SessionDao(database),
        _clock = clock ?? DateTime.now;

  final Database _db;
  final PackDao _packs;
  final ProgressDao _progress;
  final SessionDao _sessions;
  final Clock _clock;

  Future<List<PackSummary>> packs() => _packs.listPacks();

  Future<List<VocabEntry>> entries(String packKey) => _packs.entriesOf(packKey);

  Future<List<VocabEntry>> search({
    required String packKey,
    required String query,
  }) async {
    final normalised = _normalise(query);
    final all = await _packs.entriesOf(packKey);
    if (normalised.isEmpty) return all;
    return all
        .where((entry) => _normalise(entry.searchableText).contains(normalised))
        .toList();
  }

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
      recentSessions: await _sessions.recent(),
    );
  }

  Future<int> resetProgress(String packKey) => _progress.reset(packKey);

  /// Lowercase, strip invisible marks, collapse whitespace. Arabic queries and
  /// Arabic-containing text must compare consistently in both directions.
  ///
  /// The stripped classes are the bidi embedding/override/marking controls
  /// (U+200E-U+200F, U+202A-U+202E, U+2066-U+2069) that the source dataset
  /// really does contain, plus U+061C ARABIC LETTER MARK and the zero-width
  /// family U+200B-U+200D and U+FEFF, which arrive when text is pasted out of
  /// a rich-text editor. None of them are visible, so none should stop a match.
  ///
  /// NOTE: Task 10 extracts this into `lib/domain/search_matcher.dart` as
  /// `SearchMatcher`, which the UI calls directly. It stays here, private, until
  /// then. Task 5 does not own that file.
  static String _normalise(String value) => value
      .replaceAll(_invisibleMarks, '')
      .trim()
      .toLowerCase()
      .replaceAll(_whitespaceRun, ' ');

  static final RegExp _invisibleMarks = RegExp(
      '[\u200e\u200f\u202a-\u202e\u2066-\u2069\u061c\u200b-\u200d\ufeff]');

  static final RegExp _whitespaceRun = RegExp(r'\s+');
}