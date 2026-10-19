/// The two search keys, and the only two.
///
/// Every lookup in this app - English headword, English autocomplete, Arabic
/// sense - is made against one of these strings, never against the raw text.
/// That is ruling C in the Task 20a brief, and the reason is that the raw text
/// cannot answer a query: `Isis` and `isis` are one headword, `مَدْرَسَة` and
/// `مدرسه` and `مَدرَسة` are one Arabic key, and a user who types either spelling
/// has to find the other.
///
/// **This file is the single implementation of both functions.** The build tool
/// in `tool/` uses the same code the app uses, so a database cannot be written
/// with one normalisation and searched with another - which is the failure mode
/// that would otherwise only show up as "Arabic search finds nothing" in the
/// field.
///
/// The two maps below are Dart [Map]s, and every read of them is
/// `map[key] ?? the input`. That is not a style choice: a missing key must
/// yield *nothing*, never a default. The shipped JavaScript needed
/// `hasOwnProperty` for exactly
/// this reason, because `irregulars["constructor"]` inherited
/// `Object.prototype.constructor` and returned a function. Dart cannot express
/// that bug, and `?? ` is how it stays inexpressible here.
/// `test/data/dictionary/dictionary_normalization_test.dart` pins both.
library;

/// Every codepoint ECMAScript's `\s` matches, and therefore every codepoint the
/// README's `normEn` / `normAr` collapse.
///
/// Written out rather than `RegExp(r'\s')` because both normalisers run once
/// per sense at build time - 81,451 of them - and a per-character regex test is
/// the difference between a build that takes a second and one that takes three.
/// `test/data/dictionary/dictionary_normalization_test.dart` asserts that this
/// set and `\s` agree, so the two cannot drift apart silently.
const Set<int> whitespaceCodepoints = <int>{
  0x09, // tab
  0x0A, // line feed
  0x0B, // vertical tab
  0x0C, // form feed
  0x0D, // carriage return
  0x20, // space
  0xA0, // no-break space
  0x1680, // ogham space mark
  0x2000, // en quad
  0x2001, // em quad
  0x2002, // en space
  0x2003, // em space
  0x2004, // three-per-em space
  0x2005, // four-per-em space
  0x2006, // six-per-em space
  0x2007, // figure space
  0x2008, // punctuation space
  0x2009, // thin space
  0x200A, // hair space
  0x2028, // line separator
  0x2029, // paragraph separator
  0x202F, // narrow no-break space
  0x205F, // medium mathematical space
  0x3000, // ideographic space
  0xFEFF, // zero width no-break space / BOM
};

/// The two apostrophes the README strips: U+0027 and U+2019.
///
/// U+2019 is not a nicety. `don’t` appears in the headwords, and a search for
/// `don't` typed with a keyboard that emits the typographic apostrophe has to
/// reach the same entry.
const Set<int> apostropheCodepoints = <int>{0x27, 0x2019};

/// The Arabic letter equivalences of the shipped README, as one map.
///
/// `أ إ آ ٱ -> ا`, `ة -> ه`, `ى ئ -> ي`, `ؤ -> و`.
///
/// Ordered by source codepoint rather than by the README's four separate
/// `replace` passes, because the four passes are four intermediate strings per
/// sense and the map is one pass. The *result* is identical, which
/// `test/data/dictionary/dictionary_normalization_test.dart` checks rule by
/// rule - including that `ة -> ه` happens before `ى ئ -> ي` cannot matter,
/// because no source codepoint maps into another mapping's target except `ا`
/// and `ه`, which are not themselves sources.
const Map<int, int> arabicLetterEquivalences = <int, int>{
  // أ U+0623, إ U+0625, آ U+0622, ٱ U+0671  ->  ا U+0627
  0x0623: 0x0627,
  0x0625: 0x0627,
  0x0622: 0x0627,
  0x0671: 0x0627,
  // ة U+0629 -> ه U+0647
  0x0629: 0x0647,
  // ى U+0649, ئ U+0626 -> ي U+064A
  0x0649: 0x064A,
  0x0626: 0x064A,
  // ؤ U+0624 -> و U+0648
  0x0624: 0x0648,
};

/// The tashkeel, and the tatweel, removed entirely by the README's `normAr`.
///
/// The tatweel (U+0640) is not a diacritic - it is the kashida, a pure
/// typographic elongation - but the README deletes it with the diacritics and
/// `مـــدرسة` has to reach the same entry as `مدرسة`, so it is here too.
///
/// **U+0653 (ARABIC MADDAH ABOVE) is included, and that is a documented
/// difference from `dictionary.js`.** The README's own `normAr` regex
/// (`/[\u0640\u064B-\u0652\u0670\u0653]/g`) lists it; the JS file that ships
/// beside the README (`dictionary.js:39`) does not, and reads
/// `[ـ ً ٌ ٍ َ ُ ِ ّ ْ ٰ]`. The README is the specification this port is written
/// against, and the extra codepoint can only make the key *more* canonical.
/// The two files disagree on exactly one codepoint and this is it.
const Set<int> arabicMarksStripped = <int>{
  0x0640, // ـ  tatweel
  0x064B, // ً  fathatan
  0x064C, // ٌ  dammatan
  0x064D, // ٍ  kasratan
  0x064E, // َ  fatha
  0x064F, // ُ  damma
  0x0650, // ِ  kasra
  0x0651, // ّ  shadda
  0x0652, // ْ  sukun
  0x0653, // ٓ  maddah
  0x0670, // ٰ  superscript alef
};

/// The English search key: lowercased, apostrophes removed, whitespace
/// collapsed to single spaces and trimmed.
///
/// A verbatim port of the README's `normEn`:
///
/// ```js
/// const normEn = s => (s||"").toLowerCase()
///                       .replace(/['’]/g, "")
///                       .replace(/\s+/g, " ").trim();
/// ```
///
/// `null` is accepted and answers `''` rather than throwing, because the
/// dictionary has 32,451 rows and one of them being malformed must not take
/// down a build.
String normalizeEnglish(String? input) {
  final source = (input ?? '').toLowerCase();
  if (source.isEmpty) return '';
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in source.runes) {
    if (whitespaceCodepoints.contains(rune)) {
      // Leading whitespace is dropped rather than deferred: there is nothing in
      // front of it to separate from.
      if (buffer.length > 0) pendingSpace = true;
      continue;
    }
    if (apostropheCodepoints.contains(rune)) continue;
    if (pendingSpace) {
      buffer.writeCharCode(0x20);
      pendingSpace = false;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// The Arabic search key: hamza and ta-marbuta folded, ta-marbuta to haa,
/// alef-maqsura and hamza-on-yaa to yaa, waw-with-hamza to waw, tashkeel and
/// tatweel deleted, whitespace collapsed.
///
/// A verbatim port of the README's `normAr`, with its four letter rules and its
/// one diacritic rule all in the same pass.
///
/// **Arabic search runs against this, never the raw text** (ruling C). The
/// `senses.norm_ar` column holds exactly this string and `idx_senses_norm_ar`
/// is the index that makes the query an index seek rather than a scan.
String normalizeArabic(String? input) {
  final source = input ?? '';
  if (source.isEmpty) return '';
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in source.runes) {
    if (whitespaceCodepoints.contains(rune)) {
      if (buffer.length > 0) pendingSpace = true;
      continue;
    }
    if (arabicMarksStripped.contains(rune)) continue;
    // `?? rune` is the whole point: a codepoint this map has never heard of is
    // passed through untouched. Anything else - a default, an empty string, a
    // thrown error - would corrupt or lose text the dictionary legitimately
    // contains, and the README's `replace` calls pass unknown letters through.
    final mapped = arabicLetterEquivalences[rune] ?? rune;
    if (pendingSpace) {
      buffer.writeCharCode(0x20);
      pendingSpace = false;
    }
    buffer.writeCharCode(mapped);
  }
  return buffer.toString();
}