/// Damerau-Levenshtein, and the length below which it is not worth running.
///
/// **The variant implemented here is optimal string alignment** - the adjacent
/// transposition counts as one edit and is not itself re-edited. That is what
/// "Damerau-Levenshtein" means in every spell checker and in `difflib`, and it
/// is what `childern -> children` needs: one transposition, distance 1.
///
/// The true (unrestricted) Damerau-Levenshtein of Lowrance and Wagner allows
/// `CA` to become `ABC` in two edits by transposing and then inserting between
/// the swapped pair. For a spell checker over headwords the distinction is
/// unobservable, and the name says so rather than leaving a reader to guess
/// which of the two they are looking at.
///
/// **The reason this file exists at all.** The morphology table does not handle
/// misspellings - `childern`, `teachng` and `abandonn` all yield nothing from
/// it, which the shipped README proves in its own §8. Typo correction is a
/// separate concern from inflection and is kept separate here. What it shares
/// with the stemmer is only the rule that the answer must be a real headword.
library;

/// The distance at which a typo is no longer worth offering.
///
/// Two edits. `abandonn` (one insertion), `teachng` (one deletion) and
/// `childern` (one transposition) are all one; `abandoment` is two. Beyond two,
/// the suggestions are noise and the user gets a better answer by typing again.
const int defaultMaximumSpellingDistance = 2;

/// The shortest normalised query the spell checker will answer.
///
/// **Below this the trigram bound stops being a bound.** A three-letter word
/// padded to `"  abc "` carries three trigrams, and the candidate set they
/// select is a large fraction of the dictionary rather than a shortlist - the
/// exact thing trigrams exist to avoid. Four letters is the shortest query whose
/// candidates are a handful of entries, and it is the shortest query a caller
/// has any use for: a one- or two-letter query that matched nothing is not a
/// typo, it is a prefix, and prefixes are [DictionaryAutocomplete]'s job.
///
/// `test/data/dictionary/spelling_test.dart` pins both halves: that a
/// four-letter query is answered, and that a three-letter query is refused
/// rather than answered from a huge candidate set.
const int minimumSpellingQueryLength = 4;

/// The Damerau-Levenshtein (optimal string alignment) distance between [a] and
/// [b], or a value strictly greater than [limit] once the answer is known to
/// exceed it.
///
/// The early exit is what makes this affordable over a bounded candidate set: a
/// row whose every cell is already above [limit] can only grow, so the whole
/// remaining rectangle is above it too. [limit] defaults to
/// [defaultMaximumSpellingDistance] rather than to "infinity", because no caller
/// in this app wants an unbounded answer.
int damerauLevenshtein(String a, String b, {int limit = defaultMaximumSpellingDistance}) {
  if (a == b) return 0;
  if (limit < 0) limit = 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if ((b.length - a.length).abs() > limit) return limit + 1;

  // Runes rather than code units: the trigram table is built on runes too, so a
  // query and a candidate that agree on characters agree on offsets.
  final left = a.runes.toList(growable: false);
  final right = b.runes.toList(growable: false);
  final n = left.length;
  final m = right.length;

  final d = List<int>.filled((n + 1) * (m + 1), 0);
  int at(int i, int j) => d[i * (m + 1) + j];

  for (var i = 0; i <= n; i++) {
    d[i * (m + 1)] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[j] = j;
  }

  for (var i = 1; i <= n; i++) {
    var rowMinimum = limit + 1;
    for (var j = 1; j <= m; j++) {
      final cost = left[i - 1] == right[j - 1] ? 0 : 1;
      var value = at(i - 1, j) + 1;
      final deletion = at(i, j - 1) + 1;
      if (deletion < value) value = deletion;
      final substitution = at(i - 1, j - 1) + cost;
      if (substitution < value) value = substitution;
      // The transposition. `left[i-1] == right[j-2]` and `left[i-2] == right[j-1]`
      // is the pair "the last two of a are the first two of b, swapped".
      if (i > 1 &&
          j > 1 &&
          left[i - 1] == right[j - 2] &&
          left[i - 2] == right[j - 1]) {
        final transposed = at(i - 2, j - 2) + 1;
        if (transposed < value) value = transposed;
      }
      d[i * (m + 1) + j] = value;
      if (value < rowMinimum) rowMinimum = value;
    }
    if (rowMinimum > limit) return limit + 1;
  }
  return at(n, m);
}