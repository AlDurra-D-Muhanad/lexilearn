import 'dart:convert';

import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:sqflite/sqflite.dart';

/// Lightweight row used by the pack list screen.
class PackSummary {
  const PackSummary({
    required this.packKey,
    required this.title,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.entryCount,
    required this.isBundled,
    required this.importedAt,
  });

  final String packKey;
  final String title;
  final String sourceLanguage;
  final String targetLanguage;
  final int entryCount;
  final bool isBundled;
  final DateTime importedAt;
}

class PackDao {
  const PackDao(this._db);

  final Database _db;

  /// Replaces the pack and all of its entries atomically. Progress rows are
  /// keyed on deterministic entry ids and are intentionally left untouched.
  Future<void> insertPack(
    VocabPack pack, {
    required bool isBundled,
    required DateTime importedAt,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'packs',
        <String, Object?>{
          'pack_key': pack.packId,
          'title': pack.title,
          'source_language': pack.sourceLanguage,
          'target_language': pack.targetLanguage,
          'schema_version': pack.schemaVersion,
          'entry_count': pack.entryCount,
          'is_bundled': isBundled ? 1 : 0,
          'imported_at': importedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final batch = txn.batch();
      for (var index = 0; index < pack.entries.length; index++) {
        final entry = pack.entries[index];
        batch.insert(
          'entries',
          <String, Object?>{
            'entry_id': entry.id,
            'pack_key': pack.packId,
            'term': entry.term,
            'translations': jsonEncode(entry.translations),
            'note': entry.note,
            'sort_index': index,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Cascades to `entries`. Also removes this pack's progress and sessions so
  /// Stats cannot read rows for a pack that no longer exists.
  Future<void> deletePack(String packKey) async {
    await _db.transaction((txn) async {
      await txn.delete('word_progress',
          where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
      await txn.delete('quiz_sessions',
          where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
      await txn.delete('packs', where: 'pack_key = ?', whereArgs: <Object?>[packKey]);
    });
  }

  Future<List<PackSummary>> listPacks() async {
    final rows = await _db.query('packs',
        orderBy: 'is_bundled DESC, imported_at DESC');
    return rows
        .map((row) => PackSummary(
              packKey: row['pack_key']! as String,
              title: row['title']! as String,
              sourceLanguage: row['source_language']! as String,
              targetLanguage: row['target_language']! as String,
              entryCount: (row['entry_count']! as num).toInt(),
              isBundled: (row['is_bundled']! as num).toInt() == 1,
              importedAt: DateTime.parse(row['imported_at']! as String),
            ))
        .toList();
  }

  Future<VocabPack?> getPack(String packKey) async {
    final rows = await _db.query('packs',
        where: 'pack_key = ?', whereArgs: <Object?>[packKey], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final entries = await entriesOf(packKey);
    return VocabPack(
      schemaVersion: (row['schema_version']! as num).toInt(),
      packId: row['pack_key']! as String,
      title: row['title']! as String,
      sourceLanguage: row['source_language']! as String,
      targetLanguage: row['target_language']! as String,
      entries: entries,
    );
  }

  Future<List<VocabEntry>> entriesOf(String packKey) async {
    final rows = await _db.query('entries',
        where: 'pack_key = ?', whereArgs: <Object?>[packKey], orderBy: 'sort_index ASC');
    return rows
        .map((row) => VocabEntry(
              id: row['entry_id']! as String,
              term: row['term']! as String,
              translations: (jsonDecode(row['translations']! as String) as List<dynamic>)
                  .cast<String>(),
              note: (row['note'] as String?) ?? '',
            ))
        .toList();
  }

  Future<int> countEntries(String packKey) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM entries WHERE pack_key = ?',
      <Object?>[packKey],
    );
    return (rows.first['c']! as num).toInt();
  }
}