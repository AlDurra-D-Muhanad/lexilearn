import 'dart:convert';

import 'package:lexilearn/data/dictionary/damerau_levenshtein.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/dictionary_store.dart';
import 'package:lexilearn/data/dictionary/dictionary_stemmer.dart';
import 'package:lexilearn/data/dictionary/inflected_forms.dart';
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
        _forms = InflectedForms(morphology),
        autocomplete = DictionaryAutocomplete(store);

  final DictionaryStore _store;
  final DictionaryStemmer _stemmer;

  /// The inflected forms the morphology table can produce.
  ///
  /// **Held here, and not in [DictionaryAutocomplete], on purpose.** The
  /// autocomplete must never offer an invented form; the fuzzy stage must
  /// offer exactly the forms the table knows.
  final InflectedForms _forms;

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

    final resolution = _firstSurvivor(stages, byNorm);
    if (resolution == null) return NoWord(typed: typed);

    // The winner, with its examples loaded.
    final full = await _store.entryByNorm(resolution.entry.norm);
    final entry = full ?? resolution.entry;

    if (resolution.route == StemRoute.exact) {
      return ExactWord._(typed: typed, entry: entry);
    }
    return StemSuggestion._(
      typed: typed,
      entry: entry,
      via: resolution.via,
      alsoTried: resolution.alsoTried,
    );
  }

  /// Looks [input] up as an Arabic key.
  ///
  /// The query is normalised with [normalizeArabic] and matched against
  /// `senses.norm_ar` - never against the raw Arabic text, which is stored with
  /// its tashkeel and its hamzas exactly as the dictionary wrote it.
  ///
  /// **The list, not the one answer.** 30,508 distinct normalised Arabic keys
  /// are in this dictionary and thousands of them are shared by more than one
  /// sense, so an Arabic query is answered with a **ranked list**: the exact
  /// key first, then the keys that merely start with it, then the keys that
  /// hold it inside a comma-separated list of synonyms.
  ///
  /// The limit is 100 rather than 20 because the most-shared key in this
  /// dictionary resolves to more headwords than that, and a search that
  /// silently drops the tail of its own answer is a search that lies.
  Future<List<ArabicSenseHit>> searchArabic(
    String input, {
    int limit = defaultArabicSearchLimit,
  }) async {
    final key = normalizeArabic(input);
    if (key.isEmpty) return const <ArabicSenseHit>[];
    return _store.searchArabic(key, limit: limit);
  }

  /// The headwords the search list's **prefix band** holds: the ones whose
  /// normalised form starts with [query].
  ///
  /// **This is not the autocomplete.** The autocomplete ([DictionaryAutocomplete])
  /// is the README's `suggest` and answers a type-ahead; this answers a
  /// finished search, and the two are ordered differently — shortest first and
  /// then alphabetically, so the list does not reshuffle as the query grows.
  /// The autocomplete also applies no stemming, and neither does this.
  Future<List<DictionaryEntry>> searchEnglishPrefix(
    String query, {
    int limit = 50,
  }) async {
    final normalized = normalizeEnglish(query);
    if (normalized.isEmpty) return const <DictionaryEntry>[];
    return _store.entriesStartingWith(normalized, limit: limit);
  }

  /// The headwords the search list's **text band** holds: the ones whose own
  /// English definition contains [query].
  ///
  /// **The third band, and the loosest.** The exact band matches a headword,
  /// the prefix band matches a headword that starts with the query, and this
  /// one matches an entry whose *definition* contains it — the mirror of the
  /// Arabic band's third case, which looks inside the comma-separated synonym
  /// list the dictionary stores for an Arabic sense.
  ///
  /// The query is the same key the rest of the app uses ([normalizeEnglish]), so
  /// a query and a headword are compared the same way everywhere.
  Future<List<DictionaryEntry>> searchEnglishText(
    String query, {
    int limit = 20,
  }) async {
    final normalized = normalizeEnglish(query);
    if (normalized.isEmpty) return const <DictionaryEntry>[];
    return _store.entriesMentioningEnglish(normalized, limit: limit);
  }

  /// The headwords the study surface may use, with their senses.
  ///
  /// **The dictionary is the judge and the filter is the dictionary's own.**
  /// See `StudyFilter` for the rules and for why an affix and a proper noun
  /// are not a flashcard.
  Future<List<DictionaryEntry>> studyableEntries({
    int limit = 0,
    int salt = 0,
  }) =>
      _store.studyableEntries(limit: limit, salt: salt);

  /// How many headwords the study surface admits.
  Future<int> countStudyableEntries() => _store.countStudyableEntries();

  /// Near-misses for a misspelling.
  ///
  /// **Bounded by the trigram table, and the bound is the feature.** The
  /// candidate pool is the set of headwords sharing a three-character window
  /// with the query; Damerau-Levenshtein is then computed over that pool and
  /// not over the dictionary. A pool of a few hundred entries is a per-keystroke
  /// operation; 31,600 is not.
  ///
  /// **The candidate set is the union of the headwords and the inflected
  /// forms, and that is the fix.** The source README is explicit that the
  /// dictionary and the morphology table are one system, and the shipped engine
  /// broke that in one place: the distance was computed against headwords
  /// only, so `childern` was never compared with `children` even though
  /// `children` is one transposition away and the table knows
  /// `children -> child`. The scoring set is therefore
  ///
  /// * the headwords the trigram bound selected, and
  /// * the inflected forms the morphology rules can produce - the 364
  ///   irregular forms, and the regular forms of the shortlisted headwords.
  ///
  /// **A form is only a candidate if the word it resolves to is a headword.**
  /// That is the table's own rule - «المعجم هو الحكم» - and it is what keeps
  /// `childern -> child` an answer about a real word rather than a guess.
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

    // One map, keyed by the entry, so the two candidate sets can be merged
    // without offering the same word twice.
    final byEntry = <int, SpellingSuggestion>{};
    for (final entry in entries) {
      final distance =
          damerauLevenshtein(norm, entry.norm, limit: maxDistance);
      if (distance <= maxDistance) {
        byEntry[entry.id] = SpellingSuggestion(entry: entry, distance: distance);
      }
    }

    // The inflected forms. The same distance, the same limit, and the same
    // table - so `childern` reaches `child` through `children` at distance 1.
    for (final suggestion in await _formSuggestions(
      norm,
      entries,
      maxDistance,
    )) {
      final existing = byEntry[suggestion.entry.id];
      if (existing == null || suggestion.distance < existing.distance) {
        byEntry[suggestion.entry.id] = suggestion;
      }
    }

    final suggestions = byEntry.values.toList()..sort(_byDistanceThenLength);
    return SpellingResult(
      suggestions: suggestions.take(limit).toList(growable: false),
      candidatesConsidered: candidates.length,
      poolSize: measurePool
          ? await _store.spellingCandidatePoolSize(norm)
          : null,
    );
  }

  /// The suggestions that come from the **inflected forms** rather than from a
  /// headword.
  ///
  /// **Three steps, in this order, and the order is the rule.** Build the
  /// candidate forms, keep the ones the distance allows, and then resolve each
  /// of *those* through the morphology table - a form that does not resolve to
  /// a headword is not a candidate at all, and is dropped rather than offered.
  Future<List<SpellingSuggestion>> _formSuggestions(
    String norm,
    List<DictionaryEntry> pool,
    int maxDistance,
  ) async {
    final forms = _candidateForms(norm, pool, maxDistance);
    if (forms.isEmpty) return const <SpellingSuggestion>[];

    final close = <String>[];
    final distances = <String, int>{};
    for (final form in forms) {
      final distance = damerauLevenshtein(norm, form, limit: maxDistance);
      if (distance > maxDistance) continue;
      close.add(form);
      distances[form] = distance;
    }
    if (close.isEmpty) return const <SpellingSuggestion>[];

    // Resolve them all in one query: the same batching the exact stage uses.
    final stagesByForm = <String, List<StemStage>>{};
    final wanted = <String>[];
    for (final form in close) {
      final stages = _stemmer.propose(form);
      stagesByForm[form] = stages;
      for (final stage in stages) {
        for (final candidate in stage.candidates) {
          if (!wanted.contains(candidate.word)) wanted.add(candidate.word);
        }
      }
    }
    final known = await _store.entriesByNormsWithSenses(wanted);
    final byNorm = <String, DictionaryEntry>{
      for (final entry in known) entry.norm: entry,
    };

    final suggestions = <SpellingSuggestion>[];
    for (final form in close) {
      final resolution = _firstSurvivor(stagesByForm[form]!, byNorm);
      if (resolution == null) continue;
      suggestions.add(SpellingSuggestion(
        entry: resolution.entry,
        distance: distances[form]!,
        matchedForm: form,
      ));
    }
    return suggestions;
  }

  /// The inflected forms worth scoring, from the two sources the table has.
  ///
  /// **The length filter is the bound.** A form more than [maxDistance]
  /// characters longer or shorter than the query cannot be within the distance,
  /// so it is never scored. That is what keeps the regular forms affordable:
  /// the shortlist is a few hundred headwords and each one yields a few dozen
  /// forms, of which the length filter keeps a small fraction.
  List<String> _candidateForms(
    String norm,
    List<DictionaryEntry> pool,
    int maxDistance,
  ) {
    final forms = <String>{};
    for (final form in _forms.irregularForms) {
      if ((form.length - norm.length).abs() <= maxDistance) forms.add(form);
    }
    for (final entry in pool) {
      for (final form in _forms.formsOf(entry.norm)) {
        if ((form.length - norm.length).abs() <= maxDistance) forms.add(form);
      }
    }
    return forms.toList(growable: false);
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
  /// **Built from `meta` and from nothing else.** The build tool writes the
  /// upstream project, its URL and each source's own licence and verbatim
  /// credit into the `meta` table, and this reads them back. The stale
  /// `attributionFile` path is **not** among them: it pointed at a file on
  /// the machine that generated the data, it exists nowhere else, and a
  /// path that cannot be resolved is not an attribution.
  Future<DictionaryAttribution> attribution() async {
    final meta = await _store.meta();
    return DictionaryAttribution(
      name: meta['name'] ?? '',
      source: meta['source'] ?? '',
      sources: _decodeSources(meta['sources']),
      license: meta['license'] ?? '',
      licenseUrl: meta['licenseUrl'] ?? '',
      generatedFrom: meta['generatedFrom'],
      upstreamProject: meta['upstreamProject'] ?? '',
      upstreamProjectUrl: meta['upstreamProjectUrl'] ?? '',
      upstreamTagline: meta['upstreamTagline'] ?? '',
      upstreamPair: meta['upstreamPair'] ?? '',
      upstreamPairDescription: meta['upstreamPairDescription'] ?? '',
      sourceLicenses: _decodeMap(meta['sourceLicenses']),
      sourceCredits: _decodeMap(meta['sourceCredits']),
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

  /// The first stage of [stages] that produced a headword, with the headwords
  /// that stage produced.
  ///
  /// **The one place the "first matching rule wins" rule lives.** The shipped
  /// code appends to one list and returns as soon as that list is non-empty -
  /// and it is only non-empty when a candidate *is a headword*, because the
  /// dictionary check is where the candidate is added. So "first matching
  /// rule" really means "first rule that produced a word the dictionary
  /// contains", and that is what this returns.
  _Resolution? _firstSurvivor(
    List<StemStage> stages,
    Map<String, DictionaryEntry> byNorm,
  ) {
    for (final stage in stages) {
      final survivors = <StemCandidate>[];
      for (final candidate in stage.candidates) {
        final entry = byNorm[candidate.word];
        if (entry == null) continue;
        if (survivors.any((s) => s.word == candidate.word)) continue;
        survivors.add(candidate);
      }
      if (survivors.isEmpty) continue;
      return _Resolution(
        entry: byNorm[survivors.first.word]!,
        via: survivors.first.via,
        route: stage.route,
        alsoTried: survivors.skip(1).toList(growable: false),
      );
    }
    return null;
  }

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

  /// A `meta` value that is a JSON object of strings, read back as a map.
  static Map<String, String> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return const <String, String>{};
    }
  }

  static int _intOf(String? raw) => int.tryParse(raw ?? '') ?? 0;
}

/// What one resolution of a word produced.
final class _Resolution {
  const _Resolution({
    required this.entry,
    required this.via,
    required this.route,
    required this.alsoTried,
  });

  final DictionaryEntry entry;
  final String via;
  final StemRoute route;
  final List<StemCandidate> alsoTried;
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

/// How many headwords an Arabic search answers with.
///
/// **Two hundred, and the number is measured rather than chosen.** The
/// brief's figure — "one Arabic key can resolve to up to 68 headwords" — is a
/// count of *senses*, and the sense and the headword are not the same thing:
/// the most-shared key in the shipped dictionary, `حكم`, is carried by **68
/// senses** and by **47 distinct headwords**. The three bands together — the
/// exact key, the keys that start with it, and the keys that hold it inside a
/// comma-separated synonym list — answer that key with **56 headwords**.
///
/// The limit has to be a number, and no number holds everything: the
/// two-character fragments `ال` (2,017 headwords) and `ان` (994) are larger
/// than any list. Two hundred holds every answer that is a *word* rather than
/// a fragment, and the largest of those measured is `عمل` at 112.
const int defaultArabicSearchLimit = 200;
