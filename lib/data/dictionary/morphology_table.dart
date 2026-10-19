import 'dart:convert';

import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';

/// One suffix rule from `en-morphology-table.json`, as the port reads it.
///
/// The source calls the fields `suf`, `to`, `minStem`, `double` and `why`; they
/// are renamed here because `suf`/`to`/`double` are abbreviations that only mean
/// something next to the original, and this file has to be readable on its own.
final class SuffixRule {
  const SuffixRule({
    required this.suffix,
    required this.replacement,
    required this.minStem,
    required this.doublesConsonant,
    required this.why,
  });

  /// The inflection being removed, e.g. `ies`, `ing`, `s`.
  final String suffix;

  /// What replaces it: `y` for `studies -> study`, `""` for `boxes -> box`,
  /// `e` for `created -> create`.
  final String replacement;

  /// The shortest base this rule may produce, from the rule itself. The
  /// effective bound is `max(minStem, guards.minStemLength)` - see
  /// [DictionaryStemmer].
  final int minStem;

  /// Whether the doubled-consonant undoubling applies. True on the six `ing`,
  /// `ed` and `est`/`er` rules.
  final bool doublesConsonant;

  /// The source's own example, carried through for the reader.
  final String why;

  /// Whether this rule removes a trailing `s` from the word.
  ///
  /// The README's JS never reads `guards.dontStripSIfEndsWith`; see
  /// [DictionaryStemmer] for what this port does with it and why this
  /// predicate is the place the decision is made.
  bool get stripsFinalS => normalizeEnglish(suffix) == 's';

  @override
  String toString() => 'SuffixRule($suffix -> $replacement)';
}

/// The morphology table, parsed.
///
/// **8.5 KB, and it stays JSON** (ruling D). It is looked up on nearly every
/// keystroke and it is read once, so a table costs nothing to load and a table
/// in SQLite would cost a query. It is shipped as
/// `assets/dictionary/en_morphology.json`, copied verbatim from
/// `en-morphology-table.json`.
final class MorphologyTable {
  MorphologyTable({
    required Map<String, String> irregulars,
    required List<SuffixRule> suffixRules,
    required List<String> prefixes,
    required this.minStemLength,
    required List<String> dontStripSIfEndsWith,
    required this.doubleConsonants,
    required Iterable<String> neverStem,
  })  : irregulars = Map<String, String>.unmodifiable(irregulars),
        suffixRules = List<SuffixRule>.unmodifiable(suffixRules),
        prefixes = List<String>.unmodifiable(prefixes),
        dontStripSIfEndsWith =
            List<String>.unmodifiable(dontStripSIfEndsWith),
        neverStem = Set<String>.unmodifiable(neverStem);
  /// 364 irregular forms: `children -> child`, `went -> go`, `geese -> goose`.
  final Map<String, String> irregulars;

  /// 21 rules, in the order the README tries them. **Order is load-bearing**:
  /// the first rule that produces a candidate the dictionary actually contains
  /// wins, and the `ying -> ie` rule sits above `ying -> y` for that reason.
  final List<SuffixRule> suffixRules;

  /// 15 prefixes: `re`, `un`, `dis`, `non`, ...
  final List<String> prefixes;

  /// 1. The floor every candidate base must clear.
  final int minStemLength;

  /// `ss, us, is, as, os, ics, ous`. A word ending in one of these does not
  /// have its `s` stripped.
  final List<String> dontStripSIfEndsWith;

  /// `bdfgklmnprt` - the consonants this table undoubles.
  final String doubleConsonants;

  /// 57 words that are never stemmed. See [DictionaryStemmer] for why.
  final Set<String> neverStem;

  /// Parses `en-morphology-table.json`.
  ///
  /// Throws [FormatException] on anything it does not recognise rather than
  /// guessing: a morphology table that silently lost its guards is the exact
  /// failure this app's checklist warns about.
  factory MorphologyTable.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('morphology table is not a JSON object');
    }
    final irregularsRaw = decoded['irregulars'];
    if (irregularsRaw is! Map<String, dynamic>) {
      throw FormatException('morphology table has no "irregulars" object');
    }
    final irregulars = <String, String>{};
    irregularsRaw.forEach((key, value) {
      if (value is! String) {
        throw FormatException('irregular "$key" is not a string');
      }
      irregulars[key] = value;
    });

    final rulesRaw = decoded['suffixRules'];
    if (rulesRaw is! List) {
      throw FormatException('morphology table has no "suffixRules" array');
    }
    final rules = <SuffixRule>[];
    for (final raw in rulesRaw) {
      if (raw is! Map<String, dynamic>) {
        throw FormatException('a suffix rule is not an object');
      }
      final suffix = raw['suf'];
      final replacement = raw['to'];
      final minStem = raw['minStem'];
      if (suffix is! String || replacement is! String || minStem is! int) {
        throw FormatException('a suffix rule is missing suf/to/minStem');
      }
      rules.add(SuffixRule(
        suffix: suffix,
        replacement: replacement,
        minStem: minStem,
        doublesConsonant: raw['double'] == true,
        why: raw['why'] is String ? raw['why'] as String : '',
      ));
    }

    final prefixesRaw = decoded['prefixes'];
    if (prefixesRaw is! List || prefixesRaw.any((p) => p is! String)) {
      throw FormatException('morphology table has no "prefixes" string array');
    }

    final guards = decoded['guards'];
    if (guards is! Map<String, dynamic>) {
      throw FormatException('morphology table has no "guards" object');
    }
    final minStemLength = guards['minStemLength'];
    final doubles = guards['doubleConsonants'];
    final never = guards['neverStem'];
    final dontStrip = guards['dontStripSIfEndsWith'];
    if (minStemLength is! int ||
        doubles is! String ||
        never is! List ||
        dontStrip is! List) {
      throw FormatException('a guard is missing or has the wrong type');
    }

    return MorphologyTable(
      irregulars: irregulars,
      suffixRules: rules,
      prefixes: prefixesRaw.cast<String>(),
      minStemLength: minStemLength,
      dontStripSIfEndsWith: dontStrip.cast<String>(),
      doubleConsonants: doubles,
      // Normalised through the English key, because `neverStem` is consulted
      // with a normalised word and an unnormalised entry would never match.
      neverStem: <String>[
        for (final n in never) normalizeEnglish(n as String),
      ],
    );
  }

  /// The stem of an irregular form, or **`null` when the key is absent**.
  ///
  /// **This method exists in the shape it does because of `constructor`.** The
  /// README's JavaScript had to write
  /// `Object.prototype.hasOwnProperty.call(irregulars, w)` before every read,
  /// because `irregulars["constructor"]` otherwise answered the `Object`
  /// constructor rather than `undefined`, and passing a function to
  /// `normalizeEnglish` produced a headword that was not a word. Dart's [Map]
  /// cannot inherit, so a plain `irregulars[key]` is already the guarded form -
  /// but only for as long as nothing supplies a default. A signature returning
  /// `String` rather than `String?`, or a `?? ''` at a call site, would bring
  /// the whole class of bug back.
  ///
  /// `test/data/dictionary/morphology_table_test.dart` reads every key JavaScript
  /// inherits from `Object.prototype` - `constructor`, `toString`, `valueOf`,
  /// `__proto__` and the rest - and asserts this returns `null` for each.
  String? irregular(String key) => irregulars[key];

  @override
  String toString() => 'MorphologyTable(${irregulars.length} irregulars, '
      '${suffixRules.length} rules, ${prefixes.length} prefixes, '
      '${neverStem.length} neverStem)';
}

/// The `bdfgklmnprt` set, as a lookup.
bool isDoubleConsonant(String table, int rune) {
  final ch = String.fromCharCode(rune);
  return ch.length == 1 && table.contains(ch);
}