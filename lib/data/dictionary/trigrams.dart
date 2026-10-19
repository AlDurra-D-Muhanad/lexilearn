/// The trigram window used to bound the spell checker.
///
/// ## Why it lives in its own file
///
/// The build tool in `tool/` has to compute exactly the same trigrams as the
/// runtime, and the runtime's trigram code lives in `dictionary_store.dart`,
/// which imports `package:sqflite` - and `package:sqflite` imports Flutter, so
/// a `dart run` build tool cannot reach it. This file has no imports at all,
/// which is what lets `tool/build_dictionary_db.dart` and
/// `lib/data/dictionary/dictionary_store.dart` share one implementation instead
/// of two that have to be kept in agreement by hand.
///
/// ## The padding, and why it is there
///
/// The word is padded with two spaces on each side before the windows are
/// taken. Without the padding a word of one or two characters would produce no
/// trigrams at all and could never be found by the spell checker, and the
/// windows would not line up at the edges - `child` and `childe` would share no
/// trigram despite differing by a single character.
///
/// The padding is symmetric on purpose: it means the *first* and the *last*
/// characters of a word are inside a window rather than at its edge, so a
/// typo in the first letter (`hild` for `child`) still shares windows with the
/// correct word.
library;

/// The distinct three-rune windows of [word], padded with two spaces.
///
/// The result is sorted, so it is a function of the word alone and not of the
/// order the windows happened to be discovered in. That matters twice: the
/// build writes them to the `trigrams` table in this order, and the runtime
/// queries the table with them, and a mismatch would be a silent failure
/// rather than an error.
List<String> trigramsOf(String word) {
  if (word.isEmpty) return const <String>[];
  final padded = '  $word ';
  final runes = padded.runes.toList(growable: false);
  if (runes.length < 3) return const <String>[];
  final grams = <String>{};
  for (var i = 0; i + 2 < runes.length; i++) {
    grams.add(String.fromCharCodes(runes.sublist(i, i + 3)));
  }
  final sorted = grams.toList()..sort();
  return sorted;
}
