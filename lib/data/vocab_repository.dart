import 'package:lexilearn/core/clock.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:lexilearn/domain/search_matcher.dart';
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
}