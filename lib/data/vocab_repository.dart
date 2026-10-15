import 'package:lexilearn/core/clock.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite/sqflite.dart';

import 'pack_dao.dart';
import 'pack_seeder.dart';

/// The only class the UI layer is allowed to know about.
class VocabRepository {
  VocabRepository({required Database database, Clock? clock})
      : _db = database,
        _packs = PackDao(database),
        _clock = clock ?? DateTime.now;

  final Database _db;
  final PackDao _packs;
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

  Future<bool> seedBundledPack(String assetJson) =>
      PackSeeder(_db).seedIfMissing(assetJson);

  Future<void> close() => _db.close();

  /// Lowercase, strip bidi marks, collapse whitespace. Arabic queries and
  /// Arabic-containing text must compare consistently in both directions.
  ///
  /// NOTE: Task 10 extracts this into `lib/domain/search_matcher.dart` as
  /// `SearchMatcher`, which the UI calls directly. It stays here, private, until
  /// then — Task 5 does not own that file.
  static String _normalise(String value) => value
      .replaceAll(RegExp('[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}