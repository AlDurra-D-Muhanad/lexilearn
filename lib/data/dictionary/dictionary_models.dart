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
/// The Arabic text itself is carried: an Arabic search is a lookup *key*, and
/// the answer the app shows is an English entry — but a list of headwords with
/// no Arabic beside them tells the user nothing about **which** of the senses
/// matched, and 30,567 of the dictionary's Arabic senses are stored as
/// comma-separated synonym lists.
final class ArabicSenseHit {
  const ArabicSenseHit({
    required this.entry,
    this.arabic,
    this.partOfSpeech,
  });

  final DictionaryEntry entry;

  /// The Arabic of the sense that matched, as the dictionary wrote it.
  final String? arabic;

  /// The part of speech of the sense that matched.
  final String? partOfSpeech;

  @override
  String toString() => 'ArabicSenseHit(${entry.word}, $arabic)';
}

/// A near-miss from the spell checker, with the distance that produced it.
final class SpellingSuggestion {
  const SpellingSuggestion({
    required this.entry,
    required this.distance,
    this.matchedForm,
  });

  final DictionaryEntry entry;

  /// Damerau-Levenshtein (optimal string alignment) distance from the typed
  /// word to [DictionaryEntry.norm].
  final int distance;

  /// The inflected form the distance was measured against, or `null` when the
  /// candidate was the headword itself.
  ///
  /// **This is the second half of the union.** `childern` is one transposition
  /// from `children`, and `children` is not a headword - it resolves through
  /// the morphology table to `child`, which is. The distance is measured
  /// against the *form*, so it is 1, and the headword the form resolves to is
  /// what the user is offered. Without this field the two halves of the
  /// candidate set are indistinguishable, and the distance would read as if it
  /// had been measured against the headword - which it was not, and could not
  /// have been, because `damerauLevenshtein('childern', 'child')` is 3.
  final String? matchedForm;

  @override
  String toString() => 'SpellingSuggestion(${entry.word}, $distance'
      '${matchedForm == null ? '' : ' via $matchedForm'})';
}

/// Everything the CC-BY-SA-4.0 licence obliges an attribution screen to show,
/// read out of the database's `meta` table.
///
/// **The record, and not a summary.** The `meta` block inside the source
/// dictionary names the *build* and reduces three different licences to one.
/// The build tool therefore writes the upstream project, its URL and **each
/// source's own licence and verbatim credit** into `meta`, and this class
/// reads them back. Two of the three sources are not share-alike, and
/// labelling them as though they were would misstate the licence.
final class DictionaryAttribution {
  const DictionaryAttribution({
    required this.name,
    required this.source,
    required this.sources,
    required this.license,
    required this.licenseUrl,
    required this.generatedFrom,
    required this.entryCount,
    required this.senseCount,
    required this.arabicSenseCount,
    required this.exampleCount,
    required this.ipaEntryCount,
    required this.arabicKeyCount,
    this.upstreamProject = '',
    this.upstreamProjectUrl = '',
    this.upstreamTagline = '',
    this.upstreamPair = '',
    this.upstreamPairDescription = '',
    this.sourceLicenses = const <String, String>{},
    this.sourceCredits = const <String, String>{},
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

  /// `en-ar.dict.dz + en-ar.idx (StarDict 2.4.2, sametypesequence=h)`.
  final String? generatedFrom;

  /// The upstream project the dictionary was built from.
  final String upstreamProject;

  /// The upstream project's URL.
  final String upstreamProjectUrl;

  /// The upstream project's own one-line description.
  final String upstreamTagline;

  /// The dictionary pair inside the upstream project: `en-ar`.
  final String upstreamPair;

  /// The upstream's own description of that pair.
  final String upstreamPairDescription;

  /// Each source's own licence, keyed by the source's id.
  ///
  /// **The three differ.** `WordNet-3.0` is a separate and permissive
  /// licence, `CC-BY-SA-3.0` and `CC-BY-SA-4.0` are not the same thing
  /// either, and one share-alive line for all three would misstate two of
  /// them.
  final Map<String, String> sourceLicenses;

  /// Each source's verbatim credit string, keyed by the source's id.
  final Map<String, String> sourceCredits;

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

  /// The id of each named source, in the order the sources are named.
  ///
  /// The `meta` list is `id: credit`, and the id is the part before the
  /// colon. The screen needs the ids because **the licences are keyed by
  /// them**.
  List<String> get sourceIds => <String>[
        for (final source in sources)
          if (source.contains(':')) source.split(':').first.trim() else source,
      ];

  /// The credit string of [id], or the empty string when it is not named.
  String creditOf(String id) => sourceCredits[id] ?? '';

  /// The licence of [id], or the empty string when it is not named.
  String licenseOf(String id) => sourceLicenses[id] ?? '';
}