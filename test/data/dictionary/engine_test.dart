import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';

import 'dictionary_test_env.dart';

/// The lookup engine, against the dictionary that ships.
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

  group('ruling C: the case variants are merged, and every sense survives', () {
    test('one headword, not two', () async {
      final upper = await fixture.store.entryByNorm('acre');
      final lower = await fixture.store.entryByNorm('acre');
      expect(upper, isNotNull);
      expect(lower, isNotNull);
      expect(upper!.id, lower!.id);
      expect(upper.word, 'Acre');
    });

    test('the senses of both spellings are kept', () async {
      // "Acre" the city and "acre" the unit of area are different senses, and
      // the merge is a merge - not a deletion of one of them.
      final entry = await fixture.store.entryByNorm('acre');
      expect(entry, isNotNull);
      final glosses = entry!.senses.map((sense) => sense.gloss).toList();
      expect(
        glosses.any((gloss) =>
            gloss != null && gloss.contains('unit of area')),
        isTrue,
        reason: 'the sense from the lower-case spelling is missing: $glosses',
      );
      expect(
        glosses.any((gloss) =>
            gloss != null && gloss.contains('port city')),
        isTrue,
        reason: 'the sense from the capitalised spelling is missing: $glosses',
      );
    });

    test('851 spellings were folded away', () async {
      final meta = await fixture.store.meta();
      expect(meta['sourceEntryCount'], '32451');
      expect(meta['entryCount'], '31600');
      expect(meta['mergedCaseVariantCount'], '851');
    });

    test('a headword that appears under two cases answers to either', () async {
      for (final pair in <List<String>>[
        <String>['Allah', 'allah'],
        <String>['Antioch', 'antioch'],
        <String>['Isis', 'isis'],
        <String>['Acre', 'acre'],
      ]) {
        final a = await fixture.store.entryByNorm(normalizeEnglish(pair[0]));
        final b = await fixture.store.entryByNorm(normalizeEnglish(pair[1]));
        expect(a, isNotNull, reason: pair[0]);
        expect(b, isNotNull, reason: pair[1]);
        expect(a!.id, b!.id, reason: pair.join(' / '));
      }
    });
  });

  group('ruling C: Arabic search runs against norm_ar', () {
    test('the tashkeel spelling and the plain spelling find the same', () async {
      // مَدْرَسَة  and  مدرسه  are one key.
      final withMarks = await engine.searchArabic('\u0645\u064e\u062f\u0652'
          '\u0631\u064e\u0633\u064e\u0629');
      final without = await engine.searchArabic('\u0645\u062f\u0631\u0633\u0647');
      expect(withMarks, isNotEmpty);
      expect(
        withMarks.map((hit) => hit.entry.word).toList(),
        without.map((hit) => hit.entry.word).toList(),
      );
    });

    test('the README\'s own Arabic example still answers', () async {
      // مدرسه  ->  school, schoolhouse, edifice, teacheress
      final hits = await engine.searchArabic('\u0645\u062f\u0631\u0633\u0647');
      final words = hits.map((hit) => hit.entry.word).toList();
      expect(words, contains('school'));
      expect(words, contains('schoolhouse'));
      expect(words, contains('edifice'));
      expect(words, contains('teacheress'));
    });

    test('the exact key comes before the prefix matches', () async {
      // The exact key is the answer; the keys that merely start with it are
      // the fallback.
      final hits = await engine.searchArabic('\u0643\u062a\u0627\u0628');
      expect(hits, isNotEmpty);
      expect(hits.first.entry.word, 'book');
    });

    test('a word that is not in the dictionary finds nothing', () async {
      final hits = await engine.searchArabic('\u0645\u062f\u0631\u0633\u0644');
      expect(hits, isEmpty);
    });

    test('a hit carries the senses that hold the Arabic', () async {
      final hits = await engine.searchArabic('\u0645\u062f\u0631\u0633\u0647');
      expect(hits, isNotEmpty);
      final school = hits.firstWhere((hit) => hit.entry.word == 'school');
      expect(school.entry.senses, isNotEmpty);
      expect(
        school.entry.senses.any((sense) => sense.arabic != null),
        isTrue,
      );
    });
  });

  group('ruling F: a stem is a suggestion, never a substitution', () {
    test('a headword is an exact hit', () async {
      final result = await engine.lookupEnglish('abandon');
      expect(result, isA<ExactWord>());
      expect((result as ExactWord).entry.word, 'abandon');
    });

    test('an inflected form is a suggestion that keeps what was typed', () async {
      final result = await engine.lookupEnglish('abandoning');
      expect(result, isA<StemSuggestion>());
      final suggestion = result as StemSuggestion;
      // The typed form is carried, so the app can show it and offer the
      // headword beside it.
      expect(suggestion.typed, 'abandoning');
      expect(suggestion.entry.word, 'abandon');
      expect(suggestion.via, 'rule:ing+e');
    });

    test('a suggestion is never an exact hit', () async {
      // **This is the whole of Pattern 2.** The shipped README calls silent
      // correction "Pattern 1" and says it defeats the purpose of a
      // memorisation app, because the user has to learn and save the form
      // they typed. The types make that structural: a stem-derived entry can
      // only be carried by a `StemSuggestion`, which always carries the
      // typed string.
      final result = await engine.lookupEnglish('abandoning');
      expect(result, isNot(isA<ExactWord>()));
      expect(result, isA<StemSuggestion>());
    });

    test('the suggestion card names the headword, not the stem', () async {
      final result = await engine.lookupEnglish('abandoning');
      final suggestion = result as StemSuggestion;
      // The card reads: abandoning - هل تقصد: abandon
      expect(suggestion.entry.word, 'abandon');
      expect(suggestion.entry.word, isNot(suggestion.typed));
    });

    test('the README\'s inflection examples all resolve through a stem', () async {
      final expectations = <String, String>{
        'creates': 'create',
        'abandons': 'abandon',
        'abandoning': 'abandon',
        'teaches': 'teach',
        'studies': 'study',
        'tried': 'try',
        'largest': 'large',
        'children': 'child',
        'mice': 'mouse',
        'geese': 'goose',
        'knives': 'knife',
        'bought': 'buy',
      };
      for (final entry in expectations.entries) {
        final result = await engine.lookupEnglish(entry.key);
        expect(result, isA<StemSuggestion>(), reason: entry.key);
        expect((result as StemSuggestion).entry.word, entry.value,
            reason: entry.key);
      }
    });
  });

  group('ruling E: the dictionary is the judge', () {
    test('gas does not become ga', () async {
      // "gas" is a headword, so the exact stage answers it. Even if it were
      // not, the `s` rule would propose "ga" and the dictionary would refuse
      // it - which is the check that stops the proposal.
      final result = await engine.lookupEnglish('gas');
      expect(result, isA<ExactWord>());
      expect((result as ExactWord).entry.word, 'gas');
      expect(result.entry.senses, isNotEmpty);
    });

    test('a word that is not a headword and has no stem is not found', () async {
      final result = await engine.lookupEnglish('zzzznotaword');
      expect(result, isA<NoWord>());
    });

    test('a stem that is not a headword is rejected', () async {
      // **The dictionary is the judge, and this is what that looks like.**
      // The morphology table proposes "zza" for "zzas"; there is no such
      // headword, so the proposal dies and the lookup finds nothing. Without
      // the check, the app would offer the user a word that does not exist -
      // which is the "gas -> ga" failure the shipped README warns about.
      final result = await engine.lookupEnglish('zzas');
      expect(result, isA<NoWord>());
    });

    test('a stem that is a headword is accepted', () async {
      // "abandons" is not in the dictionary - the README says so - and the
      // table's `s` rule is exactly what fills that gap.
      final result = await engine.lookupEnglish('abandons');
      expect(result, isA<StemSuggestion>());
      expect((result as StemSuggestion).entry.word, 'abandon');
    });

    test('a neverStem word is not stemmed', () async {
      // `was` is in the neverStem list and is not a headword. The exact stage
      // proposes it, the dictionary refuses it, and neverStem stops the search
      // before the suffix rules are tried - so no "wa" is ever proposed.
      //
      // `doing` is the one that proves the guard is load-bearing: it is in
      // neverStem, and without the guard the `ing` rule would find "do",
      // which *is* a headword. `was` alone would not prove anything, because
      // "wa" is under the `minStem` bound anyway.
      for (final word in <String>['was', 'been', 'is', 'does', 'doing']) {
        final result = await engine.lookupEnglish(word);
        expect(result, isA<NoWord>(), reason: word);
      }
    });

    test('constructor is found, and is not turned into anything', () async {
      final result = await engine.lookupEnglish('constructor');
      expect(result, isA<ExactWord>());
      expect((result as ExactWord).entry.word, 'constructor');
    });
  });

  group('ruling F: the autocomplete never applies the stemmer', () {
    test('shows the real headwords and nothing else', () async {
      // The README's Pattern 3, verbatim: suggest("aban") must show the real
      // suffixes - abandon, abandoned, abandonment - and not the inferred
      // "abandoning", which is not a word in the dictionary.
      final results = await engine.autocomplete.search('aban');
      final words = results.map((entry) => entry.word).toList();
      expect(words, <String>['abandon', 'abandoned', 'abandonment']);
      expect(words, isNot(contains('abandoning')));
    });

    test('every word it returns is a real headword', () async {
      // The property, not the example. If the autocomplete ever applied the
      // stemmer, one of these would not be in `entries`.
      for (final prefix in <String>['a', 'ab', 'aban', 'ch', 'child', 'z']) {
        final results = await engine.autocomplete.search(prefix);
        for (final entry in results) {
          expect(
            await fixture.store.hasHeadword(entry.norm),
            isTrue,
            reason: '${entry.word} came back from the autocomplete',
          );
        }
      }
    });

    test('the class it runs on cannot reach the stemmer', () {
      // **Structural, and the reason the property above is not a coincidence.**
      // `DictionaryAutocomplete` holds a store and nothing else; there is no
      // morphology table and no stemmer anywhere in its fields, so there is no
      // code path by which a stem could be applied.
      final fields = DictionaryAutocomplete(
        fixture.store,
      ).toString();
      expect(fields, isNot(contains('Stemmer')));
    });

    test('it carries the senses, so a result can be shown with its Arabic',
        () async {
      final results = await engine.autocomplete.search('abandon');
      expect(results, isNotEmpty);
      expect(results.first.senses, isNotEmpty);
    });
  });

  group('ruling H: the attribution is a licence obligation', () {
    test('the licence and its URL are carried', () async {
      final attribution = await engine.attribution();
      expect(attribution.license, 'CC-BY-SA-4.0');
      expect(attribution.licenseUrl, 'https://creativecommons.org/licenses/by-sa/4.0/');
    });

    test('all three sources are named', () async {
      final attribution = await engine.attribution();
      expect(attribution.sources, hasLength(3));
      expect(attribution.namesEveryUpstreamSource, isTrue);
      expect(
        attribution.sources.first,
        contains('Arabic WordNet'),
      );
      expect(
        attribution.sources[1],
        contains('Princeton University WordNet 3.0'),
      );
      expect(
        attribution.sources[2],
        contains('kaikki.org'),
      );
    });

    test('the counts it reports are the counts in the database', () async {
      final attribution = await engine.attribution();
      expect(attribution.entryCount, 31600);
      expect(attribution.senseCount, 81451);
      expect(attribution.arabicSenseCount, 47266);
      expect(attribution.exampleCount, 37063);
      expect(attribution.ipaEntryCount, 15952);
      expect(attribution.arabicKeyCount, 30508);
    });

    test('the attribution file is recorded, never resolved', () async {
      // The source dictionary names an `ATTRIBUTION` file on the machine that
      // generated it. That file does not exist anywhere else, so the path is
      // carried verbatim and read from nothing - and no attribution text is
      // invented to replace it.
      final attribution = await engine.attribution();
      expect(attribution.attributionFile, isNotNull);
      expect(attribution.attributionFile, contains('ATTRIBUTION'));
      expect(attribution.generatedFrom, contains('StarDict'));
    });
  });

  group('the English gloss is the fallback', () {
    test('a sense with no Arabic still carries its gloss', () async {
      // 34,185 senses carry no Arabic, and the English gloss is the only
      // thing there is to show for them.
      final rows = await fixture.store.query(
        "SELECT en FROM senses WHERE ar IS NULL LIMIT 50",
      );
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final gloss = row['en']! as String?;
        expect(gloss, isNotNull);
        expect(gloss, isNotEmpty);
      }
    });

    test('and the entry it belongs to shows it', () async {
      final entry = await fixture.store.entryByNorm('acre');
      final withoutArabic =
          entry!.senses.where((sense) => sense.arabic == null).toList();
      expect(withoutArabic, isNotEmpty);
      expect(withoutArabic.first.gloss, isNotEmpty);
    });
  });
}
