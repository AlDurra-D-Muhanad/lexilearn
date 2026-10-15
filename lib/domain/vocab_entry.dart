// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// One vocabulary pair: an English term and its Arabic translations.
@immutable
class VocabEntry {
  const VocabEntry({
    required this.id,
    required this.term,
    required this.translations,
    this.note = '',
    // The brand's Word Detail screen shows pronunciation, part of speech,
    // synonyms, and examples. `English.txt` has none of these, so every one is
    // optional and defaults to empty. Task 14's screen hides a section rather
    // than rendering an empty heading.
    this.phonetic = '',
    this.partOfSpeech = '',
    this.synonyms = const <String>[],
    this.examples = const <String>[],
  });

  /// Stable, deterministic id. Progress is keyed on this, so it must never be
  /// derived from a counter, a timestamp, or list position.
  final String id;

  final String term;
  final List<String> translations;
  final String note;

  /// Static pronunciation text, e.g. `/səˈrenəti/`. Never played back: the
  /// user excluded text-to-speech, so this is text that merely looks like an
  /// IPA transcription.
  final String phonetic;
  final String partOfSpeech;
  final List<String> synonyms;
  final List<String> examples;

  String get primaryTranslation => translations.isEmpty ? '' : translations.first;

  /// What the quiz shows for this entry when only one string fits.
  String get displayText =>
      primaryTranslation.isNotEmpty ? primaryTranslation : term;

  /// The Python original searched raw file lines, so a query matched either
  /// side of the "term : translation" pair. Keep that: Arabic queries work.
  String get searchableText => '$term ${translations.join(' ')} $note';

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'term': term,
        'translations': translations,
        if (note.isNotEmpty) 'note': note,
        if (phonetic.isNotEmpty) 'phonetic': phonetic,
        if (partOfSpeech.isNotEmpty) 'partOfSpeech': partOfSpeech,
        if (synonyms.isNotEmpty) 'synonyms': synonyms,
        if (examples.isNotEmpty) 'examples': examples,
      };

  static VocabEntry fromJson(Map<String, Object?> json) => VocabEntry(
        id: json['id'] as String,
        term: json['term'] as String,
        translations: (json['translations'] as List<dynamic>).cast<String>(),
        note: (json['note'] as String?) ?? '',
        phonetic: (json['phonetic'] as String?) ?? '',
        partOfSpeech: (json['partOfSpeech'] as String?) ?? '',
        synonyms: _stringList(json['synonyms']),
        examples: _stringList(json['examples']),
      );

  static List<String> _stringList(Object? value) => value is List
      ? value.cast<String>()
      : const <String>[];

  VocabEntry copyWith({
    String? id,
    String? term,
    List<String>? translations,
    String? note,
    String? phonetic,
    String? partOfSpeech,
    List<String>? synonyms,
    List<String>? examples,
  }) =>
      VocabEntry(
        id: id ?? this.id,
        term: term ?? this.term,
        translations: translations ?? this.translations,
        note: note ?? this.note,
        phonetic: phonetic ?? this.phonetic,
        partOfSpeech: partOfSpeech ?? this.partOfSpeech,
        synonyms: synonyms ?? this.synonyms,
        examples: examples ?? this.examples,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VocabEntry &&
          other.id == id &&
          other.term == term &&
          other.note == note &&
          other.phonetic == phonetic &&
          other.partOfSpeech == partOfSpeech &&
          _sameStrings(other.translations, translations) &&
          _sameStrings(other.synonyms, synonyms) &&
          _sameStrings(other.examples, examples);

  // The list fields are folded into the hash rather than hashed by identity:
  // two equal entries built from different literal lists must hash alike.
  @override
  int get hashCode => Object.hash(
        id,
        term,
        note,
        phonetic,
        partOfSpeech,
        Object.hashAll(translations),
        Object.hashAll(synonyms),
        Object.hashAll(examples),
      );

  @override
  String toString() => 'VocabEntry($id, $term)';
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
