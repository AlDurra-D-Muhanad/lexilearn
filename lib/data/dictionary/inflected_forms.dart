import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';

/// The inflected forms the morphology table can produce, and the reverse of
/// the rules that produce them.
///
/// **Why this file exists.** The source README is explicit that the dictionary
/// and the morphology table are one system — «لا يعمل أحدهما بدون الآخر» and
/// «المعجم هو الحكم» — and the shipped engine broke that in exactly one
/// place: the fuzzy stage computed Damerau distance **against headwords
/// only**, and never chained the morphology table in. So `childern` was
/// compared against `Chilean`, `chilver` and `Chaldean` and never against
/// `children`, even though `children` is one transposition away and the
/// morphology table knows `children -> child`.
///
/// The fix is to score the **union** of two candidate sets:
///
/// * the headwords, which the trigram table bounds; and
/// * the inflected forms the morphology rules can produce, which the table
///   itself enumerates.
///
/// A candidate in the second set is **resolved through the table** and is only
/// valid if the word it resolves to is a headword. That is the table's own
/// rule — «المعجم هو الحكم» — and it is what makes `childern -> children ->
/// child` work at the same distance of 1 that the transposition actually is.
///
/// ## The two sets, and why the irregulars are enumerated wholesale
///
/// The 364 irregular forms are a **fixed, finite list** the table carries, so
/// they are enumerated in full on every query: 364 distance computations is
/// nothing, and a subset would be a guess.
///
/// The regular forms are not enumerable without the dictionary — a form is
/// `base + suffix`, and the base is a headword — so they are generated from
/// the headwords the trigram bound has already selected. That keeps the work
/// proportional to the shortlist rather than to the 31,600-entry dictionary,
/// and it is the same bound the spell checker already relies on.
final class InflectedForms {
  InflectedForms(this.table);

  final MorphologyTable table;

  /// Every irregular form the table knows, normalised and de-duplicated.
  ///
  /// **Sorted**, so the candidate set does not depend on the JSON object's
  /// key order and two runs of the same query produce the same list.
  late final List<String> irregularForms = _buildIrregularForms();

  List<String> _buildIrregularForms() {
    final forms = <String>{};
    for (final key in table.irregulars.keys) {
      final normalised = normalizeEnglish(key);
      if (normalised.isEmpty) continue;
      forms.add(normalised);
    }
    final sorted = forms.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// The regular forms [base] can take, by reversing the table's rules.
  ///
  /// **The reverse of the stemmer, and it has to be exact.** The stemmer maps
  /// a form to its base; this maps a base back to the forms that reach it. A
  /// rule is `suf -> to`: the stemmer strips `suf` off the form and appends
  /// `to` to what is left, so the base is `stem + to` and the form is
  /// `stem + suf`. Reversing that needs the stem, which is the base with the
  /// rule's `to` removed — and, for the rules that undouble a consonant, one
  /// character more.
  ///
  /// Every guard the stemmer applies is applied here too, because a form the
  /// stemmer would refuse is a form that does not exist as far as the engine
  /// is concerned:
  ///
  /// * `neverStem` — an auxiliary verb or a preposition resolves to itself and
  ///   to nothing else, so it is not offered as a form of anything.
  /// * `minStem` — the base has to clear the rule's own floor and the table's.
  /// * `dontStripSIfEndsWith` — a word ending in `ss us is as os ics ous` does
  ///   not have its `s` stripped, so `physics` never becomes `physic`.
  List<String> formsOf(String base) {
    if (base.isEmpty) return const <String>[];
    final forms = <String>{};

    for (final rule in table.suffixRules) {
      final suffix = normalizeEnglish(rule.suffix);
      if (suffix.isEmpty) continue;
      final replacement = normalizeEnglish(rule.replacement);
      final floor = rule.minStem > table.minStemLength
          ? rule.minStem
          : table.minStemLength;
      // The stemmer measures the **base**, not the stem: `base.length < floor`
      // is the check, and the base is `stem + replacement`.
      if (base.length < floor) continue;

      for (final stem in _stemsFor(base, replacement, rule.doublesConsonant)) {
        final form = stem + suffix;
        if (form == base) continue;
        if (table.neverStem.contains(form)) continue;
        if (rule.stripsFinalS &&
            table.dontStripSIfEndsWith.any(form.endsWith)) {
          continue;
        }
        forms.add(form);
      }
    }

    // The prefix rules strip a prefix off the front, so the form of a base is
    // the prefix in front of it. The stemmer's own bound is `>= 3` characters
    // left after the prefix, which is a bound on the base.
    if (base.length >= 3) {
      for (final prefix in table.prefixes) {
        final normalised = normalizeEnglish(prefix);
        if (normalised.isEmpty) continue;
        final form = normalised + base;
        if (table.neverStem.contains(form)) continue;
        forms.add(form);
      }
    }

    final sorted = forms.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// The stems whose `stem + replacement` is [base], or whose undoubled form
  /// is.
  ///
  /// **The undoubling only ever fires when the replacement is empty**, and
  /// that is not a simplification: the stemmer undoubles `base = stem +
  /// replacement`, and the doubled consonant has to be the **last** character
  /// of that string. With a non-empty replacement the last character is the
  /// replacement's, and the only rules that undouble have an empty
  /// replacement. So `running -> run` (replacement empty) undoubles, and
  /// `making -> make` (replacement `e`) does not — the same conclusion the
  /// stemmer's own code reaches, read from the other side.
  List<String> _stemsFor(String base, String replacement, bool doubles) {
    if (replacement.isEmpty) {
      final stems = <String>[base];
      if (doubles && base.isNotEmpty) {
        final last = base[base.length - 1];
        if (table.doubleConsonants.contains(last)) {
          stems.add(base + last);
        }
      }
      return stems;
    }
    if (!base.endsWith(replacement)) return const <String>[];
    return <String>[base.substring(0, base.length - replacement.length)];
  }
}
