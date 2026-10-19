import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/inflected_forms.dart';

import 'dictionary_test_env.dart';

/// The fuzzy stage and the morphology table, as one system.
///
/// **The defect this file exists for.** `childern` did not reach `child`, and
/// the engine offered `Chilean(2) / chilver(2) / Chaldean(2)` instead. The
/// proof that the offer was wrong is in the data:
///
/// ```
/// child        IS a headword in the dictionary
/// children     is NOT a headword
/// morphology:  children -> child   (an irregular form)
/// ```
///
/// The correct path is `childern` -> Damerau **1** (a transposition of
/// `er` <-> `re`) -> `children` -> irregular -> `child`, and `child` is in the
/// dictionary. The engine computed Damerau **directly against headwords** and
/// never chained the morphology table in, which contradicts the source README:
/// «لا يعمل أحدهما بدون الآخر» and «المعجم هو الحكم».
///
/// **The ruling.** The fuzzy stage scores the **union** of the headwords and
/// the inflected forms the morphology rules can produce, and a form is only a
/// candidate if the word it resolves to is a headword.
void main() {
  late DictionaryFixture fixture;
  late DictionaryEngine engine;
  late InflectedForms forms;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
    engine = fixture.engine;
    forms = InflectedForms(fixture.morphology);
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('the data the ruling rests on', () {
    test('child is a headword and children is not', () async {
      final child = await fixture.store.entryByNorm('child');
      expect(child, isNotNull, reason: 'child is in the dictionary');
      expect(child!.word, 'child');
      expect(await fixture.store.entryByNorm('children'), isNull,
          reason: 'children is not a headword, so nothing can be looked up '
              'under it directly');
    });

    test('the morphology table knows children -> child', () {
      expect(fixture.morphology.irregular('children'), 'child');
    });
  });

  group('childern reaches child', () {
    test('the suggestion is child, and it is the first one', () async {
      final result = await engine.spellingSuggestions('childern');
      final words = result.suggestions.map((s) => s.entry.word).toList();
      expect(words, contains('child'),
          reason: 'the morphology table resolves children to child, and child '
              'is in the dictionary');
      expect(words.first, 'child',
          reason: 'the right answer must not be demoted behind Chilean');
    });

    test('the distance is one, because the transposition is one edit',
        () async {
      final result = await engine.spellingSuggestions('childern');
      final child = result.suggestions.firstWhere((s) => s.entry.word == 'child');
      expect(child.distance, 1);
    });

    test('the route is the inflected form, and the form is reported', () async {
      final result = await engine.spellingSuggestions('childern');
      final child = result.suggestions.firstWhere((s) => s.entry.word == 'child');
      expect(child.matchedForm, 'children',
          reason: 'the distance was measured against the form, and the form '
              'is what the morphology table resolved');
    });

    test('the old wrong answer is no longer offered at the top', () async {
      final result = await engine.spellingSuggestions('childern');
      final words = result.suggestions.map((s) => s.entry.word).toList();
      expect(words, isNot(contains('Chilean')));
      expect(words, isNot(contains('chilver')));
      expect(words, isNot(contains('Chaldean')));
    });

    test('the distance is still two, and no third', () async {
      // The brief is explicit: keep the distance at 2, and do not invent a
      // ranker that demotes the right answer.
      for (final suggestion
          in (await engine.spellingSuggestions('childern')).suggestions) {
        expect(suggestion.distance, lessThanOrEqualTo(2));
      }
    });
  });

  group('the union, and its two halves', () {
    test('a headword candidate still comes from the headword set', () async {
      final result = await engine.spellingSuggestions('abandonn');
      final abandon =
          result.suggestions.firstWhere((s) => s.entry.word == 'abandon');
      expect(abandon.distance, 1);
      expect(abandon.matchedForm, isNull,
          reason: 'abandon is a headword, so the distance was measured '
              'against the headword itself');
    });

    test('a form candidate resolves through the table to a headword',
        () async {
      final result = await engine.spellingSuggestions('childern');
      final child = result.suggestions.firstWhere((s) => s.entry.word == 'child');
      expect(child.entry.norm, 'child');
      // The resolved word really is in the dictionary, which is the table's
      // own rule: the dictionary is the judge.
      expect(await fixture.store.entryByNorm(child.entry.norm), isNotNull);
    });

    test('a form that resolves to nothing is not offered', () async {
      // `xyzzy` is not in the morphology table and `xyzzying` is not a form
      // of anything in the dictionary, so the fuzzy stage has nothing to say
      // about it beyond what the headword set already said.
      final result = await engine.spellingSuggestions('xyzzying');
      for (final suggestion in result.suggestions) {
        expect(await fixture.store.entryByNorm(suggestion.entry.norm),
            isNotNull);
      }
    });

    test('the candidate set is still bounded, forms and all', () async {
      final result = await engine.spellingSuggestions('childern',
          measurePool: true);
      expect(result.poolSize, lessThan(31600));
      expect(result.candidatesConsidered, lessThanOrEqualTo(spellingCandidateLimit));
    });
  });

  group('the inflected forms the table can produce', () {
    test('the irregular forms are enumerated', () {
      expect(forms.irregularForms, contains('children'));
      expect(forms.irregularForms, contains('went'));
      expect(forms.irregularForms, contains('geese'));
      // Every one of them is a form and not a headword of its own accord.
      expect(forms.irregularForms.length, 364);
    });

    test('the irregular forms are normalised and de-duplicated', () {
      for (final form in forms.irregularForms) {
        expect(form, normalizeEnglish(form));
      }
      expect(forms.irregularForms.toSet().length, forms.irregularForms.length);
    });

    test('a regular form of a base is produced by reversing its rule', () {
      // `running` is `run` with the doubled consonant and the `ing` put back.
      expect(forms.formsOf('run'), contains('running'));
      expect(forms.formsOf('abandon'), contains('abandoning'));
      expect(forms.formsOf('abandon'), contains('abandoned'));
    });

    test('a prefix rule produces the prefixed form', () {
      expect(forms.formsOf('build'), contains('rebuild'));
    });

    test('the guards are honoured, so no form is offered that the stemmer '
        'would refuse', () {
      // `neverStem`: an auxiliary verb resolves to itself and to nothing else.
      expect(forms.formsOf('be'), isNot(contains('being')));
      // `dontStripSIfEndsWith`: a word ending in `ss` does not lose its `s`.
      expect(forms.formsOf('physic'), isNot(contains('physics')));
      // `minStem`: the base has to clear the floor.
      expect(forms.formsOf('is'), isNot(contains('isis')));
    });

    test('every form the table produces resolves to a headword or to nothing',
        () async {
      // The property that keeps the union honest: a form is only ever
      // *offered* when it resolves to a word the dictionary holds. Checked
      // over a sample of the table's own forms against the shipped data.
      const bases = <String>[
        'run',
        'abandon',
        'child',
        'teach',
        'happy',
        'quick',
        'build',
        'create',
        'big',
      ];
      var resolved = 0;
      for (final base in bases) {
        for (final form in forms.formsOf(base)) {
          final lookup = await engine.lookupEnglish(form);
          if (lookup is NoWord) continue;
          resolved++;
          final entry = switch (lookup) {
            ExactWord(:final entry) => entry,
            StemSuggestion(:final entry) => entry,
            NoWord() => throw StateError('unreachable'),
          };
          expect(await fixture.store.entryByNorm(entry.norm), isNotNull,
              reason: '$form resolved to ${entry.norm}, which is not a headword');
        }
      }
      expect(resolved, greaterThan(10),
          reason: 'the sample has to have exercised the resolution, or the '
              'property above it proved nothing');
    });
  });
}
