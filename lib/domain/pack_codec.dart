import 'dart:convert';

import 'vocab_entry.dart';
import 'vocab_pack.dart';

/// Thrown for every malformed-document case. The UI shows `message` verbatim,
/// so messages must be written for a person, not for a log file.
class PackDecodeException implements Exception {
  const PackDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PackCodec {
  const PackCodec._();

  static Map<String, Object?> decodeDocument(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw PackDecodeException('This file is not valid JSON: ${error.message}');
    }
    if (decoded is! Map) {
      throw const PackDecodeException(
          'Expected a JSON object at the top level of the file.');
    }
    return decoded.cast<String, Object?>();
  }

  static VocabPack decodePack(String jsonText) => packFromDocument(decodeDocument(jsonText));

  static VocabPack packFromDocument(Map<String, Object?> document) {
    if (document.containsKey('kind')) {
      throw const PackDecodeException(
          'This is a backup file, not a vocabulary pack. Use "Restore backup" instead.');
    }
    final version = _requireInt(document, 'schemaVersion');
    if (version != VocabPack.currentSchemaVersion) {
      throw PackDecodeException(
          'Unsupported pack version $version. This app reads version '
          '${VocabPack.currentSchemaVersion}.');
    }
    final rawEntries = _requireList(document, 'entries');
    final seenIds = <String>{};
    final entries = <VocabEntry>[];
    for (var index = 0; index < rawEntries.length; index++) {
      final raw = rawEntries[index];
      if (raw is! Map) {
        throw PackDecodeException('Entry #${index + 1} is not an object.');
      }
      final json = raw.cast<String, Object?>();
      final entry = VocabEntry.fromJson(_validateEntry(json, index));
      if (!seenIds.add(entry.id)) {
        throw PackDecodeException(
            'Duplicate entry id "${entry.id}" at position ${index + 1}.');
      }
      entries.add(entry);
    }
    return VocabPack(
      schemaVersion: version,
      packId: _requireNonEmptyString(document, 'packId'),
      title: _requireNonEmptyString(document, 'title'),
      sourceLanguage: (document['sourceLanguage'] as String?) ?? 'en',
      targetLanguage: (document['targetLanguage'] as String?) ?? 'ar',
      entries: entries,
    );
  }

  static String encodePack(VocabPack pack) =>
      const JsonEncoder.withIndent('  ').convert(pack.toJson());

  static Map<String, Object?> _validateEntry(Map<String, Object?> json, int index) {
    final at = 'Entry #${index + 1}';
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw PackDecodeException('$at is missing a non-empty "id".');
    }
    final term = json['term'];
    if (term is! String || term.trim().isEmpty) {
      throw PackDecodeException('$at is missing a non-empty "term".');
    }
    final translations = json['translations'];
    if (translations is! List || translations.isEmpty) {
      throw PackDecodeException('$at must have a non-empty "translations" list.');
    }
    for (final translation in translations) {
      if (translation is! String) {
        throw PackDecodeException('$at has a non-string translation.');
      }
    }
    final note = json['note'];
    if (note != null && note is! String) {
      throw PackDecodeException('$at has a non-string "note".');
    }
    return json;
  }

  static String _requireNonEmptyString(Map<String, Object?> document, String key) {
    final value = document[key];
    if (value is! String || value.trim().isEmpty) {
      throw PackDecodeException('The file is missing a non-empty "$key".');
    }
    return value;
  }

  static int _requireInt(Map<String, Object?> document, String key) {
    final value = document[key];
    if (value is! num) {
      throw PackDecodeException('The file is missing a numeric "$key".');
    }
    return value.toInt();
  }

  static List<dynamic> _requireList(Map<String, Object?> document, String key) {
    final value = document[key];
    if (value is! List) {
      throw PackDecodeException('The file is missing a "$key" list.');
    }
    return value;
  }
}
