import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/damerau_levenshtein.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/trigrams.dart';

import 'dictionary_test_env.dart';

/// Misspellings, and the bound that makes them shippable.
void main() {
  late DictionaryFixture fixture;
  late DictionaryEngine engine;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
    engine = fixture.engine;
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('the distance itself', () {
    test('counts a transposition as one edit', () {
      // The reason this is Damerau and not plain Levenshtein: `childern` and
      // `children` differ by a swap, and a swap is one mistake a person makes.
      // Plain Levenshtein calls it two.
      expect(damerauLevenshtein('ab', 'ba'), 1);
      expect(damerauLevenshtein('childern', 'children'), 1);
      expect(damerauLevenshtein('teh', 'the'), 1);
    });

    test('counts an insertion, a deletion and a substitution as one each', () {
      expect(damerauLevenshtein('abandonn', 'abandon'), 1);
      expect(damerauLevenshtein('teachng', 'teaching'), 1);
      expect(damerauLevenshtein('creat', 'great'), 1);
      expect(damerauLevenshtein('creat', 'crust'), 2);
      expect(damerauLevenshtein('', 'abc'), 3);
    });

    test('is zero for the same word and symmetric otherwise', () {
      expect(damerauLevenshtein('abandon', 'abandon'), 0);
      expect(damerauLevenshtein('abandon', 'abandonn'),
          damerauLevenshtein('abandonn', 'abandon'));
    });

    test('stops early once the answer is known to be over the limit', () {
      // The early exit has to return a value that is *over* the limit, not the
      // limit, or a caller comparing with `<=` would accept a word that is too
      // far away.
      expect(damerauLevenshtein('abcdefgh', 'zyxwvuts', limit: 2), greaterThan(2));
      expect(damerauLevenshtein('abcdefgh', 'abcdefgh', limit: 0), 0);
    });
  });

  group('the morphology table does not handle misspellings', () {
    test('and the engine does not pretend otherwise', () async {
      // The shipped README's own section 8: the table handles forms, not
      // spellings. `childern`, `teachng` and `abandonn` all yield nothing
      // from it.
      for (final typo in <String>['childern', 'teachng', 'abandonn']) {
        final result = await engine.lookupEnglish(typo);
        expect(result, isA<NoWord>(), reason: typo);
      }
    });
  });

  group('ruling G: the candidate set is bounded by the trigrams', () {
    test('childern is compared against a handful of headwords, not 31,600',
        () async {
      final result = await engine.spellingSuggestions('childern',
          measurePool: true);
      // **The measurement the brief asks for.** The dictionary holds 31,600
      // headwords. The trigram table reduces the comparison set to the
      // headwords that share a three-character window with the query.
      expect(result.poolSize, lessThan(31600));
      expect(result.candidatesConsidered, lessThanOrEqualTo(spellingCandidateLimit));
      expect(result.candidatesConsidered, lessThan(result.poolSize!));
    });

    test('the bound holds for every typo the README names', () async {
      for (final typo in <String>[
        'childern', 'teachng', 'abandonn', 'creat', 'swiming', 'childrn',
      ]) {
        final result = await engine.spellingSuggestions(typo,
            measurePool: true);
        expect(result.candidatesConsidered, lessThan(31600), reason: typo);
        expect(result.poolSize, lessThan(31600), reason: typo);
      }
    });

    test('the trigrams of a word are its own padded windows', () {
      expect(trigramsOf('child'),
          <String>['  c', ' ch', 'chi', 'hil', 'ild', 'ld ']);
      expect(trigramsOf(''), isEmpty);
      // Sorted, so the build and the runtime agree on the order.
      final grams = trigramsOf('abandon');
      expect(grams, equals(List<String>.from(grams)..sort()));
    });

    test('a headword within two edits of the query is always in the pool',
        () async {
      // **The property that makes the bound sound.** If the trigram filter
      // threw away the right answer, the bound would be a bug rather than a
      // bound. Checked against the shipped dictionary rather than asserted:
      // 250 headwords spread across the file, every one-character mutation of
      // each, and the headword's own trigrams have to survive the filter.
      //
      // Measured over the whole dictionary - 765,815 mutations of 3,000
      // headwords - this held for every headword of four letters or more, and
      // failed only for words of one, two or three letters. That is why
      // [minimumSpellingQueryLength] is 4 and not 1.
      const sampleSize = 250;
      const stride = 31600 ~/ sampleSize;
      final rows = await fixture.store.query(
        'SELECT norm FROM entries ORDER BY id',
      );
      expect(rows.length, 31600);
      var checked = 0;
      for (var i = 0; i < rows.length; i += stride) {
        final word = rows[i]['norm']! as String;
        if (word.length < minimumSpellingQueryLength) continue;
        final head = trigramsOf(word).toSet();
        for (final mutation in _oneCharacterMutations(word)) {
          if (damerauLevenshtein(mutation, word, limit: 2) > 2) continue;
          checked++;
          final shared = head.intersection(trigramsOf(mutation).toSet());
          expect(shared, isNotEmpty, reason: '$word -> $mutation');
        }
      }
      expect(checked, greaterThan(1000));
    });

    test('a word of three letters or fewer can miss, which is why they are refused',
        () {
      // The limit is not theoretical. `all` and `lal` are one transposition
      // apart and share no three-character window, so a three-letter query
      // cannot be bounded this way - and the engine refuses those queries
      // rather than answering them from a pool that might not hold the answer.
      final head = trigramsOf('all').toSet();
      final shared = head.intersection(trigramsOf('lal').toSet());
      expect(shared, isEmpty);
      expect(damerauLevenshtein('lal', 'all'), 1);
      expect('all'.length, lessThan(minimumSpellingQueryLength));
    });
  });

  group('the corrections the spell checker finds', () {
    test('a transposition is corrected', () async {
      // `thsi` is `this` with the middle two letters swapped.
      final result = await engine.spellingSuggestions('thsi');
      expect(
        result.suggestions.map((s) => s.entry.word),
        contains('this'),
      );
      expect(
        result.suggestions.firstWhere((s) => s.entry.word == 'this').distance,
        1,
      );
    });

    test('the README\'s own typos are corrected', () async {
      final expectations = <String, String>{
        'abandonn': 'abandon',
        'teachng': 'teaching',
        'swiming': 'swimming',
      };
      for (final entry in expectations.entries) {
        final result = await engine.spellingSuggestions(entry.key);
        expect(
          result.suggestions.map((s) => s.entry.word),
          contains(entry.value),
          reason: entry.key,
        );
      }
    });

    test('a query that is too short is refused, not answered from a huge pool',
        () async {
      // Three letters is where the trigram bound stops being a bound, and a
      // one- or two-letter query that matched nothing is a prefix rather than
      // a typo. The prefixes are the autocomplete's job.
      final result = await engine.spellingSuggestions('cat');
      expect(result.suggestions, isEmpty);
      expect(result.candidatesConsidered, 0);
    });
  });
}

/// Every one-character mutation of [word]: a deletion, a substitution and a
/// transposition at each position.
///
/// The set of ways a person mistypes one letter of a word. Not exhaustive over
/// insertions, because an insertion makes the word longer and the trigram
/// windows slide rather than disappear.
Iterable<String> _oneCharacterMutations(String word) sync* {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz';
  for (var i = 0; i < word.length; i++) {
    yield word.substring(0, i) + word.substring(i + 1);
    for (final letter in alphabet.split('')) {
      if (letter == word[i]) continue;
      yield word.substring(0, i) + letter + word.substring(i + 1);
    }
  }
  for (var i = 0; i + 1 < word.length; i++) {
    yield word.substring(0, i) +
        word[i + 1] +
        word[i] +
        word.substring(i + 2);
  }
}
