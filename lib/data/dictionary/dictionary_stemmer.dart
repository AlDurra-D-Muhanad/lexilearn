import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';

/// How a candidate stem was reached. Only [StemRoute.exact] may be presented as
/// "the word the user typed"; the rest are suggestion-card material.
enum StemRoute {
  /// The normalised input is itself a headword.
  exact,

  /// The input is in the table's `irregulars` map.
  irregular,

  /// A suffix rule produced it.
  suffix,

  /// Stripping a prefix produced it.
  prefix,
}

/// One candidate stem, with the label the README would have given it.
///
/// [via] is the README's `how` string verbatim - `exact`, `irregular`,
/// `rule:ing`, `rule:ing+e`, `prefix:re` - because it is the one piece of the
/// algorithm a UI can show and a test can assert on.
final class StemCandidate {
  const StemCandidate({required this.word, required this.via, required this.route});

  /// A normalised headword. **Not yet known to exist in the dictionary.**
  final String word;

  /// `exact`, `irregular`, `rule:s`, `rule:ing+e`, `prefix:re`, ...
  final String via;

  final StemRoute route;

  @override
  String toString() => 'StemCandidate($word via $via)';
}

/// One rule's worth of candidates, in the order the README adds them.
///
/// **Staging is what keeps the README's "first matching rule wins" honest.**
/// The shipped code appends to one list and returns as soon as that list is
/// non-empty - and it is only non-empty when a candidate *is a headword*,
/// because `add` is where the dictionary check lives. So "first matching rule"
/// really means "first rule that produced a word the dictionary contains". A
/// stage is the unit the caller resolves against the dictionary, and the first
/// stage with a survivor is the answer.
final class StemStage {
  const StemStage({required this.route, required this.candidates});

  final StemRoute route;
  final List<StemCandidate> candidates;

  @override
  String toString() => 'StemStage($route, $candidates)';
}

/// The README's stemmer, ported to Dart.
///
/// ## What this class is, and what it is not
///
/// It is **pure and synchronous**: it turns an input word into an ordered list
/// of proposed stages and never touches a database. The one thing that makes
/// the README's algorithm work - *a candidate stem is only accepted if the
/// dictionary contains it* - is therefore not in here at all. It belongs to
/// [DictionaryEngine], which is where a query is resolved against the store.
///
/// That split is deliberate. In the shipped code the check and the "stop at the
/// first rule that worked" decision are one and the same `add` function; splitting
/// them is what lets each be tested, and it is why [StemStage] exists as a type
/// rather than a comment.
///
/// ## The guards, and each one's incident
///
/// * **The dictionary check.** `gas` must not become `ga`. This class happily
///   proposes `ga`; the engine rejects it because no such headword exists, which
///   is the behaviour the README's §7 line `gas -> gas [exact]` describes.
/// * **`neverStem` (57 words).** An auxiliary verb or a preposition must stop
///   dead. `was` is in the table, and so is `does` and `did`; stemming them
///   would produce `w`, `doe`, `d`.
/// * **`minStem`.** A rule may not produce a base shorter than
///   `max(rule.minStem, guards.minStemLength)`.
/// * **Double-consonant undoubling.** `running -> run`, `bigger -> big`. Only
///   for the consonants in `guards.doubleConsonants` (`bdfgklmnprt`), and only
///   when the last two letters are the same one.
/// * **`dontStripSIfEndsWith`.** A word ending in `ss us is as os ics ous` does
///   not have its `s` stripped, so `physics` does not become `physic` and
///   `crisis` does not become `crisi`.
///   **This is a deliberate difference from the shipped JavaScript, which
///   declares the guard and never reads it.** `dictionary.js:128-140` and the
///   README's §4 both compute `dontStripSIfEndsWith` and then never mention it
///   again; `gas` survives in the shipped code purely because `ga` is not a
///   headword. The brief for this port lists the guard as one of the five that
///   must be carried, so it is carried here. `test/data/dictionary/dictionary_stemmer_test.dart`
///   pins both the guard's own behaviour (`physics`, `crisis`) and the fact
///   that it is load-bearing (deleting it turns those tests red).
/// * **Rule order.** `ying -> ie` sits above `ying -> y`. Swapping them changes
///   `dying`'s answer. The list is used in file order, never sorted.
///
/// ## One dead rule, kept on purpose
///
/// The table's first rule is `{"suf": "'s", "to": ""}`. The README's `normEn`
/// deletes apostrophes, so no normalised word can ever end in `'s` and this rule
/// can never fire - the possessive `cat's` normalises to `cats` and is handled
/// by the `s` rule at the bottom of the table instead. It is ported rather than
/// dropped so that the Dart rules list and the JSON rules list stay the same
/// length and the same order, which is what makes the two comparable.
class DictionaryStemmer {
  DictionaryStemmer(this.table);

  final MorphologyTable table;

  /// The ordered proposals for [input]. Empty when [input] normalises to
  /// nothing.
  List<StemStage> propose(String? input) {
    final w = normalizeEnglish(input);
    if (w.isEmpty) return const <StemStage>[];

    final stages = <StemStage>[];

    // 1) the input verbatim.
    stages.add(StemStage(
      route: StemRoute.exact,
      candidates: <StemCandidate>[
        StemCandidate(word: w, via: 'exact', route: StemRoute.exact),
      ],
    ));

    // 2) an auxiliary verb or a preposition stops here. `out` in the README is
    //    whatever `add` accepted, so an exact hit survives this return and a
    //    word that is not a headword at all leaves nothing behind.
    if (table.neverStem.contains(w)) return stages;

    // 3) an irregular form.
    //
    //    `irregulars[w]` then `irregulars[input]`: the README tries the
    //    normalised word first and only then the raw one, so a table keyed by
    //    capitalisation still answers. `irregular` returns **null** for an
    //    absent key and that null is load-bearing - see [MorphologyTable.irregular].
    final irregular = table.irregular(w) ?? table.irregular(input ?? '');
    if (irregular != null) {
      final target = normalizeEnglish(irregular);
      if (target.isNotEmpty) {
        stages.add(StemStage(
          route: StemRoute.irregular,
          candidates: <StemCandidate>[
            StemCandidate(
                word: target, via: 'irregular', route: StemRoute.irregular),
          ],
        ));
      }
    }

    // 4) suffix rules, in table order.
    for (final rule in table.suffixRules) {
      if (!w.endsWith(rule.suffix)) continue;
      // The guard. Only rules that strip a trailing `s` are subject to it, which
      // is exactly the two rules whose suffix normalises to `s`: `'s` and `s`.
      if (rule.stripsFinalS &&
          table.dontStripSIfEndsWith.any(w.endsWith)) {
        continue;
      }
      final stem = w.substring(0, w.length - rule.suffix.length);
      final base = stem + rule.replacement;
      if (base.length <
          (rule.minStem > table.minStemLength
              ? rule.minStem
              : table.minStemLength)) {
        continue;
      }
      final produced = <StemCandidate>[];
      if (rule.doublesConsonant) {
        final undoubled = _undouble(base);
        // `running -> run` keeps the rule's own label; `making -> make` is the
        // `+e` form of the same rule. Both come out of the one rule, which is
        // why a candidate carries its own label and a stage does not.
        if (undoubled != base) {
          produced.add(StemCandidate(
              word: undoubled, via: 'rule:${rule.suffix}', route: StemRoute.suffix));
        }
        produced.add(StemCandidate(
            word: base, via: 'rule:${rule.suffix}+e', route: StemRoute.suffix));
      } else {
        produced.add(StemCandidate(
            word: base, via: 'rule:${rule.suffix}', route: StemRoute.suffix));
      }
      if (produced.isEmpty) continue;
      stages.add(StemStage(
          route: StemRoute.suffix, candidates: _deduplicate(produced)));
    }

    // 5) prefixes, in table order. The `>= 3` is the README's own literal, not
    //    `guards.minStemLength`; ported as written rather than "improved".
    for (final prefix in table.prefixes) {
      if (!w.startsWith(prefix)) continue;
      if (w.length - prefix.length < 3) continue;
      final rest = w.substring(prefix.length);
      if (rest.isEmpty) continue;
      stages.add(StemStage(
        route: StemRoute.prefix,
        candidates: <StemCandidate>[
          StemCandidate(
              word: rest, via: 'prefix:$prefix', route: StemRoute.prefix),
        ],
      ));
    }

    return stages;
  }

  /// `runn -> run`, and nothing else.
  ///
  /// Two guards, both from the README: the last two characters must be the
  /// *same* character, and that character must be one of
  /// `guards.doubleConsonants`. Without the first, `abandoning` would lose its
  /// final `n` and propose `abando`.
  String _undouble(String value) {
    if (value.length < 2) return value;
    final last = value.codeUnitAt(value.length - 1);
    final previous = value.codeUnitAt(value.length - 2);
    if (last != previous) return value;
    if (!isDoubleConsonant(table.doubleConsonants, last)) return value;
    return value.substring(0, value.length - 1);
  }

  /// Within one rule, the README's `add` refuses a word it already holds.
  ///
  /// **Only within a rule.** Across rules the README dedupes against a list
  /// that only ever contains *dictionary-accepted* words, so a candidate
  /// rejected by the dictionary there can legitimately be proposed again by a
  /// later rule and accepted there. Deduplicating across stages instead would
  /// silently swallow it.
  List<StemCandidate> _deduplicate(List<StemCandidate> candidates) {
    final seen = <String>{};
    return candidates.where((c) => seen.add(c.word)).toList();
  }
}