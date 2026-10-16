import 'vocab_entry.dart';

/// The search rule, as a pure function.
///
/// Lifted out of `VocabRepository` so the comparison can be reasoned about — and
/// tested — without a database, and so the UI can run it over an entry list it
/// already has. `VocabRepository.search` is now a lookup followed by a call into
/// here; there is exactly one normalisation rule in the app, not two.
class SearchMatcher {
  const SearchMatcher._();

  /// Everything invisible that can sit between a user and a match.
  ///
  /// The bidi embedding/override/marking controls (U+200E-U+200F, U+202A-U+202E,
  /// U+2066-U+2069) are in the source dataset itself. U+061C ARABIC LETTER MARK
  /// is the one Arabic IMEs emit and the one most likely to arrive in text pasted
  /// into the search field; the zero-width family U+200B-U+200D and U+FEFF ride
  /// along with text copied out of a rich-text editor. None of them are visible,
  /// so none of them may decide whether a word is found.
  static final RegExp _invisibleMarks = RegExp(
    '[\u200e\u200f\u202a-\u202e\u2066-\u2069\u061c\u200b-\u200d\ufeff]',
  );

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Lowercase, strip invisible marks, collapse whitespace, trim.
  ///
  /// Applied to *both* sides, which is the only reason `'multi   space'` in the
  /// dataset is reachable by the query `'multi space'`.
  static String normalise(String value) => value
      .replaceAll(_invisibleMarks, '')
      .replaceAll(_whitespaceRun, ' ')
      .trim()
      .toLowerCase();

  /// The entries whose term, translations or note contain [query].
  ///
  /// The Python original searched raw file lines, so a query hit the English
  /// term, the Arabic translation, or the raw line joining them. Keep all three:
  /// `VocabEntry.searchableText` is that line.
  ///
  /// A query that is empty once normalised matches everything — decided *after*
  /// stripping, so a field holding a single stray mark is not a search for
  /// nothing. The empty case returns a copy, so a caller cannot sort or clear
  /// the list it was handed and mutate the pack's entries.
  static List<VocabEntry> filter(List<VocabEntry> entries, String query) {
    final needle = normalise(query);
    if (needle.isEmpty) return List<VocabEntry>.of(entries);
    return entries
        .where((entry) => normalise(entry.searchableText).contains(needle))
        .toList();
  }
}
