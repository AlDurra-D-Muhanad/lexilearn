import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/dictionary_stemmer.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';

import 'dictionary_test_env.dart';

/// The morphology table and the stemmer built on it.
///
/// **The stemmer here proposes; the engine decides.** The shipped algorithm's
/// safety net is "is this stem a headword?", and that check needs the
/// dictionary. So this file tests the *proposals* - which rule fires, in what
/// order, and which guards stop it - and `engine_test.dart` tests what
/// survives the dictionary check.
void main() {
  late MorphologyTable table;
  late DictionaryStemmer stemmer;

  setUpAll(() {
    table = shippedMorphologyTable();
    stemmer = DictionaryStemmer(table);
  });

  group('the table itself', () {
    test('carries the numbers the source says it carries', () {
      expect(table.irregulars, hasLength(364));
      expect(table.suffixRules, hasLength(21));
      expect(table.prefixes, hasLength(15));
      expect(table.neverStem, hasLength(57));
    });

    test('the guards are the ones the source ships', () {
      expect(table.minStemLength, 1);
      expect(table.doubleConsonants, 'bdfgklmnprt');
      expect(table.dontStripSIfEndsWith,
          <String>['ss', 'us', 'is', 'as', 'os', 'ics', 'ous']);
      expect(table.neverStem, contains('was'));
      expect(table.neverStem, contains('is'));
      expect(table.neverStem, contains('do'));
    });

    test('the suffix rules keep the order the source gives them', () {
      // Order is load-bearing: `ying -> ie` above `ying -> y` is what makes
      // `dying` resolve to `die`.
      final yingRules = table.suffixRules
          .where((rule) => rule.suffix == 'ying')
          .map((rule) => rule.replacement)
          .toList();
      expect(yingRules, <String>['ie', 'y']);

      final suffixes = table.suffixRules.map((rule) => rule.suffix).toList();
      expect(suffixes.first, "'s");
      expect(suffixes.last, 's');
    });

    test('a malformed table is refused rather than half-read', () {
      expect(
        () => MorphologyTable.parse('not json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => MorphologyTable.parse('{"irregulars": {}}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => MorphologyTable.parse('{"irregulars": {}, "suffixRules": []}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('a missing key returns null, never a default', () {
    test('the irregular map answers null for a word it does not hold', () {
      expect(table.irregular('children'), 'child');
      expect(table.irregular('geese'), 'goose');
      expect(table.irregular('notaword'), isNull);
    });

    test('constructor is not a key, and does not answer like one', () {
      // **The incident this guards.** The shipped JavaScript had to write
      // `Object.prototype.hasOwnProperty.call(irregulars, w)` before every
      // read, because `irregulars["constructor"]` inherited
      // `Object.prototype.constructor` and answered a *function*. Passing that
      // function to `normalizeEn` produced a headword that was not a word.
      //
      // Dart's `Map` cannot inherit, so the bug cannot come back the same way.
      // What *can* come back is a default - a `?? ''`, a `?? 'do'`, an
      // `orElse:` - and a default here is just as wrong: it would propose a
      // stem for a word that has none.
      expect(table.irregular('constructor'), isNull);
    });

    test('every key JavaScript inherits from Object.prototype is null', () {
      // The whole set, not just `constructor`. The JavaScript bug was one
      // symptom of a class, and the class is "a key that is not a key".
      const inherited = <String>[
        'constructor',
        'toString',
        'toLocaleString',
        'valueOf',
        'hasOwnProperty',
        'isPrototypeOf',
        'propertyIsEnumerable',
        '__proto__',
        '__defineGetter__',
        '__defineSetter__',
        '__lookupGetter__',
        '__lookupSetter__',
      ];
      for (final key in inherited) {
        expect(table.irregular(key), isNull, reason: key);
      }
    });

    test('a stemmer reading the irregular map does not invent a stem', () {
      // The end-to-end version of the same guard: `constructor` is a headword
      // in this dictionary, so the exact stage answers it and nothing else
      // touches it.
      final proposals = stemmer.propose('constructor');
      expect(proposals, hasLength(1));
      expect(proposals.single.route, StemRoute.exact);
      expect(proposals.single.candidates.single.word, 'constructor');
    });
  });

  group('the guards on the stemmer', () {
    test('neverStem stops immediately', () {
      // `was` is in the table and is not a headword. The exact stage proposes
      // it and the dictionary refuses it - and nothing else is tried, because
      // neverStem is checked before the irregular map and before the rules.
      final proposals = stemmer.propose('was');
      expect(proposals, hasLength(1));
      expect(proposals.single.route, StemRoute.exact);
      expect(proposals.single.candidates.single.word, 'was');
    });

    test('neverStem stops a word whose stem *is* a headword', () {
      // **The guard at its strongest.** "doing" is in the neverStem list, and
      // the `ing` rule would otherwise find "do" - which is a headword, and
      // which the table also lists as neverStem. The guard is checked before
      // the rules, so the `ing` stage is never proposed at all.
      //
      // `was` alone does not prove this: "wa" is under the `minStem` bound
      // anyway, so `was` would find nothing even without the guard.
      final proposals = stemmer.propose('doing');
      expect(proposals, hasLength(1));
      expect(proposals.single.route, StemRoute.exact);
      expect(
        proposals.expand((stage) => stage.candidates).map((c) => c.word),
        isNot(contains('do')),
      );
    });

    test('neverStem covers all 57 words, normalised', () {
      for (final word in table.neverStem) {
        expect(normalizeEnglish(word), word, reason: word);
      }
      expect(table.neverStem, hasLength(57));
    });

    test('the double-consonant undoubling fires only on the listed letters', () {
      // running -> run
      final running = stemmer.propose('running');
      final runningWords =
          running.expand((stage) => stage.candidates).map((c) => c.word).toList();
      expect(runningWords, contains('run'));
      expect(runningWords, contains('runn'));

      // `z` is not in `bdfgklmnprt`, so `fizzing` never proposes `fiz`. The
      // base `fizz` is still proposed - it is the rule's own output - but the
      // undoubled form is not.
      final buzzing = stemmer.propose('fizzing');
      final buzzingWords =
          buzzing.expand((stage) => stage.candidates).map((c) => c.word).toList();
      expect(buzzingWords, isNot(contains('fiz')));
      expect(buzzingWords, contains('fizz'));
    });

    test('a rule may not produce a base under minStem', () {
      // `s` has minStem 3, so "cats" cannot become "cat"... except that `cat`
      // is four letters, which is over the bound. The bound that bites is on a
      // short word: `as` has minStem 3, so "gas" cannot become "ga".
      final gas = stemmer.propose('gas');
      final gasWords =
          gas.expand((stage) => stage.candidates).map((c) => c.word).toList();
      expect(gasWords, isNot(contains('ga')));
    });

    test('dontStripSIfEndsWith stops the s being stripped', () {
      // `genetics` ends in `ics`, so its `s` stays. Without the guard the
      // table would propose `genetic`.
      final genetics = stemmer.propose('genetics');
      final words =
          genetics.expand((stage) => stage.candidates).map((c) => c.word).toList();
      expect(words, isNot(contains('genetic')));

      // And a word that does not end in a guarded ending is stripped normally.
      final cats = stemmer.propose('cats');
      final catWords =
          cats.expand((stage) => stage.candidates).map((c) => c.word).toList();
      expect(catWords, contains('cat'));
    });

    test('the guard applies to every guarded ending', () {
      for (final ending in table.dontStripSIfEndsWith) {
        final word = 'zap$ending';
        final proposals = stemmer.propose(word);
        final words =
            proposals.expand((stage) => stage.candidates).map((c) => c.word);
        expect(words, isNot(contains('zap$ending'.substring(0, 3))),
            reason: '$word had its s stripped');
      }
    });
  });

  group('the README\'s own examples', () {
    test('the proposed stems are the ones the README lists', () {
      final expectations = <String, String>{
        'create': 'create',
        'creates': 'create',
        'abandons': 'abandon',
        'abandoning': 'abandon',
        'teaches': 'teach',
        'studies': 'study',
        'tried': 'try',
        'largest': 'large',
        'bought': 'buy',
        'children': 'child',
        'mice': 'mouse',
        'geese': 'goose',
        'knives': 'knife',
      };
      expectations.forEach((input, expected) {
        final proposals = stemmer.propose(input);
        final words =
            proposals.expand((stage) => stage.candidates).map((c) => c.word);
        expect(words, contains(expected), reason: input);
      });
    });

    test('the label on each stem is the README\'s', () {
      String via(String input, String word) {
        final proposals = stemmer.propose(input);
        return proposals
            .expand((stage) => stage.candidates)
            .firstWhere((candidate) => candidate.word == word)
            .via;
      }

      expect(via('abandoning', 'abandon'), 'rule:ing+e');
      expect(via('abandons', 'abandon'), 'rule:s');
      expect(via('children', 'child'), 'irregular');
      expect(via('studies', 'study'), 'rule:ies');
      expect(via('largest', 'large'), 'rule:est+e');
    });

    test('an empty input proposes nothing', () {
      expect(stemmer.propose(''), isEmpty);
      expect(stemmer.propose('   '), isEmpty);
    });
  });
}
