import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';

/// One headword, with every sense that survived the case-variant merge.
///
/// **`word` is the display spelling and `norm` is the key.** They differ for
/// every headword that appeared in the source twice under different case: the
/// first spelling the dictionary offered is kept for display (`Acre`), and
/// `acre` is what every query is matched against.
final class DictionaryEntry {
  const DictionaryEntry({
    required this.id,
    required this.word,
    required this.norm,
    required this.ipa,
    required this.hasArabic,
    this.senses = const <DictionarySense>[],
  });

  /// The row id in `entries`. Stable for a given build of the database.
  final int id;

  /// The headword as the dictionary spells it.
  final String word;

  /// [word] through [normalizeEnglish]. The `UNIQUE(norm)` key.
  final String norm;

  /// The phonetic transcription, or `null` - 15,952 of 31,600 entries have one.
  final String? ipa;

  /// Whether at least one sense carries Arabic.
  ///
  /// Denormalised from `senses` so the search list can show an Arabic badge
  /// without a join per row.
  final bool hasArabic;

  final List<DictionarySense> senses;

  /// A shallow copy carrying [senses]. Used when a query answers with the
  /// headword alone and the senses are filled in separately.
  DictionaryEntry withSenses(List<DictionarySense> next) => DictionaryEntry(
        id: id,
        word: word,
        norm: norm,
        ipa: ipa,
        hasArabic: hasArabic,
        senses: next,
      );

  @override
  String toString() => 'DictionaryEntry($word)';
}

/// One sense of a headword: a part of speech, an Arabic translation, an English
/// gloss and any number of examples.
///
/// **The English gloss is present on all 81,451 senses** and is the only thing
/// there is to show for the 34,185 that carry no Arabic, which is why [gloss]
/// is nullable in the schema but effectively always set.
final class DictionarySense {
  const DictionarySense({
    required this.id,
    required this.pos,
    required this.arabic,
    required this.normArabic,
    required this.gloss,
    this.examples = const <String>[],
  });

  /// The row id in `senses`.
  final int id;

  /// `n`, `v`, `adj`, `adv` - or `null`. Exactly one sense in the source has no
  /// part of speech.
  final String? pos;

  /// The Arabic translation as written, which is frequently a comma-separated
  /// list of synonyms.
  final String? arabic;

  /// [arabic] through [normalizeArabic], or `null` when [arabic] is `null`.
  ///
  /// This is the indexed key. **Search compares against this and never against
  /// [arabic]**; a user who types `مدرسه` has to reach the entry stored as
  /// `مَدْرَسَة`.
  final String? normArabic;

  /// The English gloss.
  final String? gloss;

  final List<String> examples;

  @override
  String toString() => 'DictionarySense($pos, $arabic)';
}

/// One English headword reached from an Arabic query.
///
/// The Arabic text itself is not carried: an Arabic search is a lookup *key*, and
/// the answer the app shows is an English entry. [entry] carries the senses.
final class ArabicSenseHit {
  const ArabicSenseHit({required this.entry});

  final DictionaryEntry entry;

  @override
  String toString() => 'ArabicSenseHit(${entry.word})';
}

/// A near-miss from the spell checker, with the distance that produced it.
final class SpellingSuggestion {
  const SpellingSuggestion({required this.entry, required this.distance});

  final DictionaryEntry entry;

  /// Damerau-Levenshtein (optimal string alignment) distance from the typed
  /// word to [DictionaryEntry.norm].
  final int distance;

  @override
  String toString() => 'SpellingSuggestion(${entry.word}, $distance)';
}

/// Everything the CC-BY-SA-4.0 licence obliges an attribution screen to show,
/// read out of the database's `meta` table.
///
/// **Built from `meta`, and from nothing else.** The source dictionary's
/// `meta.attributionFile` points at `C:/Users/user/Desktop/en-ar/ATTRIBUTION`,
/// which does not exist on any machine this app will run on, so it is carried
/// here as [attributionFile] - a path that is *recorded*, never resolved and
/// never read. Inventing attribution text to fill the gap would be worse than
/// the gap: the licence obliges the app to name its sources accurately, and a
/// fabricated paragraph is not a source.
final class DictionaryAttribution {
  const DictionaryAttribution({
    required this.name,
    required this.source,
    required this.sources,
    required this.license,
    required this.licenseUrl,
    required this.attributionFile,
    required this.generatedFrom,
    required this.entryCount,
    required this.senseCount,
    required this.arabicSenseCount,
    required this.exampleCount,
    required this.ipaEntryCount,
    required this.arabicKeyCount,
  });

  /// `English-Arabic Dictionary`.
  final String name;

  /// `koreader-dicts (StarDict build 2026-09-11)` - the build the data came out
  /// of.
  final String source;

  /// The three upstream wordnets, in the order the source names them:
  /// `omw-arb`, `pwn30`, `wikt-en-ar`.
  final List<String> sources;

  /// `CC-BY-SA-4.0`.
  final String license;

  /// The licence's own URL.
  final String licenseUrl;

  /// A path on the machine that generated the data, kept verbatim and never
  /// resolved. See the class doc.
  final String? attributionFile;

  /// `en-ar.dict.dz + en-ar.idx (StarDict 2.4.2, sametypesequence=h)`.
  final String? generatedFrom;

  /// Headwords in the shipped database, after the case-variant merge: 31,600.
  final int entryCount;

  /// Senses: 81,451.
  final int senseCount;

  /// Senses carrying Arabic: 47,266.
  final int arabicSenseCount;

  /// Example sentences: 37,063.
  final int exampleCount;

  /// Headwords carrying a phonetic transcription: 15,952.
  final int ipaEntryCount;

  /// Distinct normalised Arabic keys: 30,508.
  final int arabicKeyCount;

  /// Whether every source the licence names is present.
  ///
  /// A guard rather than a convenience: the attribution screen is a licence
  /// obligation, and a build that lost a source line would otherwise render a
  /// screen that under-credits the dictionary without anybody noticing.
  bool get namesEveryUpstreamSource =>
      sources.any((s) => s.startsWith('omw-arb')) &&
      sources.any((s) => s.startsWith('pwn30')) &&
      sources.any((s) => s.startsWith('wikt-en-ar'));
}