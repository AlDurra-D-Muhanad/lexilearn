import 'dart:convert';

import 'package:lexilearn/data/dictionary/damerau_levenshtein.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/dictionary_store.dart';
import 'package:lexilearn/data/dictionary/dictionary_stemmer.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';

/// What an English lookup found.
///
/// **A sealed hierarchy, and that is the whole point of ruling F.** The README
/// is explicit that a memorisation app must not silently substitute a stem for
/// what the user typed - "abandoning" has to show `abandon` as a *suggestion*,
/// because the user has to learn and save the form they typed. So there is no
/// way to hold "an entry" without also holding "what was typed", and the two
/// kinds of answer are different types.
///
/// The constructors are private to this file. The only way to obtain an
/// [ExactWord] is to ask [DictionaryEngine.lookupEnglish] for one, and the
/// engine only builds it when the stemmer's `exact` stage survived the
/// dictionary check - that is, when the word the user typed *is* the headword
/// that comes back. A stem-derived entry can only be carried by a
/// [StemSuggestion], which always carries the typed string with it.
sealed class DictionaryLookup {
  const DictionaryLookup();

  /// The string the user typed, in every case.
  String get typed;
}

/// The typed word is itself a headword.
///
/// **This is the only answer that may be shown as if the user had typed it.**
final class ExactWord extends DictionaryLookup {
  const ExactWord._({required this.typed, required this.entry});

  @override
  final String typed;

  /// The entry for the typed word.
  final DictionaryEntry entry;

  @override
  String toString() => 'ExactWord($typed)';
}

/// The typed word is not a headword, but a stem of it is.
///
/// **This is the suggestion card.** The app shows the typed form and offers the
/// headword - *abandoning - هل تقصد: abandon* - and the user decides. Nothing
/// here substitutes anything.
final class StemSuggestion extends DictionaryLookup {
  const StemSuggestion._({
    required this.typed,
    required this.entry,
    required this.via,
    required this.alsoTried,
  });

  @override
  final String typed;

  /// The headword the stem resolved to - `abandon` for `abandoning`.
  final DictionaryEntry entry;

  /// How the stem was reached: `rule:ing+e`, `irregular`, `prefix:re`.
  final String via;

  /// The other headwords the same rule produced, if any.
  final List<StemCandidate> alsoTried;

  @override
  String toString() => 'StemSuggestion($typed -> ${entry.word} via $via)';
}

/// Nothing matched - not the word itself, and no stem of it.
final class NoWord extends DictionaryLookup {
  const NoWord({required this.typed});

  @override
  final String typed;

  @override
  String toString() => 'NoWord($typed)';
}

/// Type-ahead over the headwords.
///
/// **This class has no stemmer and no morphology table, and that is the
/// structural half of ruling F.** The README's Pattern 3 says the autocomplete
/// must show `abandon`, `abandoned`, `abandonment` and never the invented
/// `abandoning`, because `abandoning` is not a word in the dictionary. A
/// class that cannot see the stemmer cannot apply it, so the mistake is not
/// possible to make by forgetting a guard - it is not expressible.
///
/// The test for it is not "the guard was not removed" but "the returned words
/// are all real headwords", checked against the database itself.
final class DictionaryAutocomplete {
  DictionaryAutocomplete(this._store);

  final DictionaryStore _store;

  /// Headwords whose normalised form starts with [prefix].
  ///
  /// The shipped README's `suggest`, including its ordering: the first
  /// [limit] matches in dictionary order, then those sorted by length. See
  /// [DictionaryStore.headwordsWithPrefix].
  Future<List<DictionaryEntry>> search(String prefix, {int limit = 20}) async {
    final normalized = normalizeEnglish(prefix);
    if (normalized.isEmpty) return const <DictionaryEntry>[];
    final heads = await _store.headwordsWithPrefix(normalized, limit: limit);
    return _store.entriesByNormsWithSenses(
      heads.map((entry) => entry.norm).toList(growable: false),
    );
  }
}

/// The dictionary: English headwords, Arabic senses, type-ahead and
/// spell correction, over one read-only SQLite file.
///
/// **The app never parses the source JSON.** The 11.7 MB `en-ar-dictionary.json`
/// was turned into `assets/dictionary/en_ar.db` once, offline, by
/// `tool/build_dictionary_db.dart`. Opening this engine costs one SQLite file
/// open and nothing else - no `jsonDecode` of 12 MB, which is 387 ms of
/// synchronous work that would block the first frame.
final class DictionaryEngine {
  DictionaryEngine({
    required DictionaryStore store,
    required MorphologyTable morphology,
  })  : _store = store,
        _stemmer = DictionaryStemmer(morphology),
        autocomplete = DictionaryAutocomplete(store);

  final DictionaryStore _store;
  final DictionaryStemmer _stemmer;

  /// The type-ahead, with no stemmer in reach.
  final DictionaryAutocomplete autocomplete;

  /// Looks [input] up as an English headword.
  ///
  /// The three answers are [ExactWord], [StemSuggestion] and [NoWord], and the
  /// caller cannot tell them apart by accident: they are different types and
  /// the hierarchy is sealed.
  Future<DictionaryLookup> lookupEnglish(String input) async {
    final typed = input;
    final stages = _stemmer.propose(input);
    if (stages.isEmpty) return NoWord(typed: typed);

    // One query for the whole walk. The stemmer proposes every stage it can
    // reach, and the dictionary check - "is this stem a headword?" - is asked
    // once for all of them rather than once per stage.
    final wanted = <String>[];
    for (final stage in stages) {
      for (final candidate in stage.candidates) {
        if (!wanted.contains(candidate.word)) wanted.add(candidate.word);
      }
    }
    final known = await _store.entriesByNormsWithSenses(wanted);
    final byNorm = <String, DictionaryEntry>{
      for (final entry in known) entry.norm: entry,
    };

    for (final stage in stages) {
      final survivors = <StemCandidate>[];
      final survivorEntries = <DictionaryEntry>[];
      for (final candidate in stage.candidates) {
        final entry = byNorm[candidate.word];
        if (entry == null) continue;
        if (survivors.any((s) => s.word == candidate.word)) continue;
        survivors.add(candidate);
        survivorEntries.add(entry);
      }
      if (survivors.isEmpty) continue;

      // The winner, with its examples loaded.
      final full = await _store.entryByNorm(survivors.first.word);
      final entry = full ?? survivorEntries.first;

      if (stage.route == StemRoute.exact) {
        return ExactWord._(typed: typed, entry: entry);
      }
      return StemSuggestion._(
        typed: typed,
        entry: entry,
        via: survivors.first.via,
        alsoTried: survivors.skip(1).toList(growable: false),
      );
    }
    return NoWord(typed: typed);
  }

  /// Looks [input] up as an Arabic key.
  ///
  /// The query is normalised with [normalizeArabic] and matched against
  /// `senses.norm_ar` - never against the raw Arabic text, which is stored with
  /// its tashkeel and its hamzas exactly as the dictionary wrote it.
  Future<List<ArabicSenseHit>> searchArabic(String input, {int limit = 20}) async {
    final key = normalizeArabic(input);
    if (key.isEmpty) return const <ArabicSenseHit>[];
    return _store.searchArabic(key, limit: limit);
  }

  /// Near-misses for a misspelling.
  ///
  /// **Bounded by the trigram table, and the bound is the feature.** The
  /// candidate pool is the set of headwords sharing a three-character window
  /// with the query; Damerau-Levenshtein is then computed over that pool and
  /// not over the dictionary. A pool of a few hundred entries is a per-keystroke
  /// operation; 31,600 is not.
  ///
  /// **This is a fallback, not a per-keystroke feature.** It is meant to be
  /// asked once, after [lookupEnglish] has found nothing - the user typed a
  /// word that is not in the dictionary and wants the nearest thing that is.
  /// Measured: 37 to 119 ms per query on this machine, of which the candidate
  /// query is the larger half. [measurePool] adds a second scan of the same
  /// posting lists and is therefore off by default; the tests turn it on
  /// because a bound that is not measured is a claim.
  ///
  /// The result carries the numbers, because "the candidate set is bounded" is
  /// a claim and a claim has to be measurable.
  Future<SpellingResult> spellingSuggestions(
    String input, {
    int limit = 5,
    int maxDistance = defaultMaximumSpellingDistance,
    bool measurePool = false,
  }) async {
    final norm = normalizeEnglish(input);
    if (norm.length < minimumSpellingQueryLength) {
      return const SpellingResult(
        suggestions: <SpellingSuggestion>[],
        candidatesConsidered: 0,
        poolSize: null,
      );
    }
    final candidates = await _store.spellingCandidates(
      norm,
      limit: spellingCandidateLimit,
    );
    if (candidates.isEmpty) {
      return SpellingResult(
        suggestions: const <SpellingSuggestion>[],
        candidatesConsidered: 0,
        poolSize: measurePool
            ? await _store.spellingCandidatePoolSize(norm)
            : null,
      );
    }
    final entries = await _store.entriesByIds(
      candidates.map((candidate) => candidate.entryId).toList(growable: false),
    );
    final suggestions = <SpellingSuggestion>[];
    for (final entry in entries) {
      final distance =
          damerauLevenshtein(norm, entry.norm, limit: maxDistance);
      if (distance <= maxDistance) {
        suggestions.add(SpellingSuggestion(entry: entry, distance: distance));
      }
    }
    suggestions.sort(_byDistanceThenLength);
    return SpellingResult(
      suggestions: suggestions.take(limit).toList(growable: false),
      candidatesConsidered: candidates.length,
      poolSize: measurePool
          ? await _store.spellingCandidatePoolSize(norm)
          : null,
    );
  }

  /// How many headwords share a trigram with [input] - the size of the pool the
  /// spell checker would work through.
  ///
  /// Exposed because the bound is the thing that has to be *measured*, not
  /// asserted. `test/data/dictionary/spelling_test.dart` reads it.
  Future<int> spellingCandidatePoolSize(String input) async {
    final norm = normalizeEnglish(input);
    if (norm.isEmpty) return 0;
    return _store.spellingCandidatePoolSize(norm);
  }

  /// Everything the CC-BY-SA-4.0 licence obliges an attribution screen to show.
  ///
  /// **Built from `meta` and from nothing else.** The source dictionary names
  /// an `attributionFile` that does not exist on any machine this app runs on;
  /// it is carried through verbatim and never resolved, and no attribution text
  /// is invented to fill the gap.
  Future<DictionaryAttribution> attribution() async {
    final meta = await _store.meta();
    return DictionaryAttribution(
      name: meta['name'] ?? '',
      source: meta['source'] ?? '',
      sources: _decodeSources(meta['sources']),
      license: meta['license'] ?? '',
      licenseUrl: meta['licenseUrl'] ?? '',
      attributionFile: meta['attributionFile'],
      generatedFrom: meta['generatedFrom'],
      entryCount: _intOf(meta['entryCount']),
      senseCount: _intOf(meta['senseCount']),
      arabicSenseCount: _intOf(meta['arabicSenseCount']),
      exampleCount: _intOf(meta['exampleCount']),
      ipaEntryCount: _intOf(meta['ipaEntryCount']),
      arabicKeyCount: _intOf(meta['arabicKeyCount']),
    );
  }

  /// The `meta` table, verbatim.
  Future<Map<String, String>> meta() => _store.meta();

  static int _byDistanceThenLength(SpellingSuggestion a, SpellingSuggestion b) {
    final byDistance = a.distance.compareTo(b.distance);
    if (byDistance != 0) return byDistance;
    final byLength = a.entry.word.length.compareTo(b.entry.word.length);
    if (byLength != 0) return byLength;
    return a.entry.word.compareTo(b.entry.word);
  }

  static List<String> _decodeSources(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded.whereType<String>().toList(growable: false);
    } on FormatException {
      return const <String>[];
    }
  }

  static int _intOf(String? raw) => int.tryParse(raw ?? '') ?? 0;
}

/// The answer to a misspelling, and the size of the search that produced it.
///
/// **The two counts are the point.** [candidatesConsidered] is how many
/// headwords the Damerau distance was actually computed over;
/// [poolSize] is how many headwords shared a trigram with the query. Neither
/// is the 31,600 the dictionary holds, and the difference between them and
/// 31,600 is the whole reason the `trigrams` table exists.
final class SpellingResult {
  const SpellingResult({
    required this.suggestions,
    required this.candidatesConsidered,
    required this.poolSize,
  });

  /// The near-misses, nearest first.
  final List<SpellingSuggestion> suggestions;

  /// How many headwords the distance was computed over.
  final int candidatesConsidered;

  /// How many headwords share a trigram with the query.
  ///
  /// `null` unless the caller asked for it. Measuring it costs a second scan
  /// of the same posting lists the candidate query already read, and the
  /// answer does not need it.
  final int? poolSize;

  @override
  String toString() => 'SpellingResult(${suggestions.length} of '
      '$candidatesConsidered from a pool of ${poolSize ?? '?'})';
}

/// How many headwords the spell checker will consider at once.
///
/// **A ceiling, not a target.** The trigram bound usually produces far fewer
/// than this; the cap is what stops a query made entirely of common short
/// trigrams from turning into a full scan. 512 candidates of Damerau distance
/// is a few hundred thousand cell comparisons, which is nothing.
const int spellingCandidateLimit = 512;
