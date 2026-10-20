import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/ui/dictionary/dictionary_search_controller.dart';

import 'dictionary_test_env.dart';

/// The search, against the specification it is supposed to meet.
///
/// **The shipped README is the specification**, and so is the user's own
/// ruling, recorded in `.superpowers/sdd/progress.md`:
///
/// > exact first, then prefix, then a synonym that contains the query
///
/// Every group below is one of those bands, and every one of them is measured
/// against the file that ships rather than against a fixture.
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

  /// The words a search reached, in order.
  List<String> reachedWords(List<DictionarySearchItem> items) => <String>[
        for (final item in items)
          if (item is DictionaryWordItem) item.entry.word,
      ];

  group('the English bands', () {
    test('the exact headword is the first result', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('child');

      final words = controller.items.whereType<DictionaryWordItem>().toList();
      expect(words, isNotEmpty);
      expect(words.first.entry.norm, 'child',
          reason: 'the word the user typed comes first');
      expect(words.first.entry.word, 'child');
      controller.dispose();
    });

    test('the prefix matches follow it, and it does not hide them', () async {
      // **The defect the committed golden was documenting.** A search for
      // `child` returned one row — `child` — and the eleven headwords that
      // start with it were nowhere on the screen.
      final controller = DictionarySearchController(engine: engine);
      await controller.search('child');

      final words = reachedWords(controller.items);
      expect(words, containsAll(<String>[
        'childhood',
        'childish',
        'childless',
        'childbirth',
      ]), reason: 'a query that is a prefix of a longer word must not hide '
          'that word: $words');
      controller.dispose();
    });

    test('the prefix band is ordered shortest first, then alphabetically',
        () async {
      // **A prefix with more than a few dozen matches**, because Dart's
      // `List.sort` is only stable for the short lists it sorts by insertion;
      // above that the order of two words of the same length is whatever the
      // implementation does, and the list would differ between two runs of the
      // same query.
      final prefix = await engine.searchEnglishPrefix('ch');
      final norms = prefix.map((entry) => entry.norm).toList();
      expect(norms.length, greaterThan(32),
          reason: 'the order has to be pinned on a list long enough to sort '
              'un-stably: ${norms.length}');

      final byLengthThenAlphabet = <String>[...norms]..sort((a, b) {
        final byLength = a.length.compareTo(b.length);
        if (byLength != 0) return byLength;
        return a.compareTo(b);
      });
      expect(norms, byLengthThenAlphabet,
          reason: 'the list has to read the same way twice: $norms');
      // The shortest first: the first entry is no longer than the last.
      expect(norms.first.length, lessThanOrEqualTo(norms.last.length));
    });

    test('a query that is contained in an entry reaches that entry', () async {
      // **The third band.** The dictionary stores a headword's English
      // definition, and a user who types "young person" is asking for the
      // entry whose gloss says "a young person of either sex".
      final contained = await engine.searchEnglishText('young person');
      final words = contained.map((entry) => entry.word).toList();
      expect(words, contains('child'), reason: 'the gloss of `child` is '
          '"a young person of either sex"');
    });

    test('and the search list shows it', () async {
      // **The same band, through the path the user takes.** The engine's band
      // is only worth anything if the result list carries it.
      //
      // **"port city" and not "young person"**, because `young person` is
      // itself a headword and the exact band answers it — the band under
      // test would never be reached. The gloss of `Acre` is "A port city in
      // northern Israel, holiest city in the Baháʼí Faith."
      final controller = DictionarySearchController(engine: engine);
      await controller.search('port city');
      expect(reachedWords(controller.items), contains('Acre'));
      controller.dispose();
    });

    test('the text band refuses a query too short to mean anything', () async {
      // One character matches 31,339 entries; a list of twenty of them would
      // say nothing at all.
      final contained = await engine.searchEnglishText('a');
      expect(contained, isEmpty);
    });
  });

  group('the Arabic bands', () {
    test('the key is the normalised one, never the raw text', () async {
      // The plain spelling and the tashkeel spelling are one key.
      final plain = await engine.searchArabic('مدرسه');
      final marked = await engine.searchArabic('مَدْرَسَة');
      expect(plain, isNotEmpty);
      expect(
        plain.map((hit) => hit.entry.word).toList(),
        marked.map((hit) => hit.entry.word).toList(),
      );
      expect(plain.map((hit) => hit.entry.word),
          containsAll(<String>['school', 'schoolhouse', 'edifice', 'teacheress']));
    });

    test('a key shared by many headwords answers with all of them', () async {
      // **The shape the brief asks for, measured rather than asserted.** The
      // most-shared *synonym* key in the shipped dictionary, how many senses
      // carry it, and how many distinct headwords the search answers with.
      //
      // **The key is the app's own normalised key**, because that is what the
      // search matches against: the stored list is the normalised whole list
      // and its elements are the normalised words.
      final rows = await fixture.store.query(
        'SELECT entry_id, ar FROM senses WHERE ar IS NOT NULL',
      );
      final byKey = <String, Set<int>>{};
      for (final row in rows) {
        final entryId = row['entry_id']! as int;
        for (final part in (row['ar']! as String).split(',')) {
          final key = normalizeArabic(part.trim());
          if (key.isEmpty) continue;
          byKey.putIfAbsent(key, () => <int>{}).add(entryId);
        }
      }
      final ranked = byKey.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      final key = ranked.first.key;
      final headwords = ranked.first.value.length;
      // ignore: avoid_print
      print('the most-shared Arabic synonym key is "$key", carried by '
          '$headwords distinct headwords');

      final hits = await engine.searchArabic(key);
      expect(hits.length, greaterThanOrEqualTo(headwords),
          reason: 'the search must not drop a headword the key resolves to');
      expect(hits.length, greaterThan(20),
          reason: 'a list of twenty could not hold this answer');
      // ignore: avoid_print
      print('the search answered with ${hits.length} rows: '
          '${hits.take(8).map((hit) => hit.entry.word).join(", ")} ...');
    });

    test('the answer never exceeds the limit it was given', () async {
      // **The limit is a promise about the size of the answer.** The first
      // version gave the prefix band a full `limit` of its own on top of the
      // exact band's, so a key with one exact hit and a hundred prefix hits
      // answered with a hundred and one rows — over the limit the caller set.
      // `ال` is the key that shows it: the definite article is the prefix of
      // 2,017 headwords.
      final hits = await engine.searchArabic('ال', limit: 50);
      // ignore: avoid_print
      print('the key "ال" answered with ${hits.length} rows against a limit '
          'of 50');
      expect(hits.length, lessThanOrEqualTo(50));
    });
  });

  group('the misspellings', () {
    test('the candidates are bounded by the trigram table', () async {
      final result = await engine.spellingSuggestions(
        'childern',
        measurePool: true,
      );
      // ignore: avoid_print
      print('childern: ${result.candidatesConsidered} candidates compared, '
          'from a pool of ${result.poolSize} of 31,600 headwords');
      expect(result.candidatesConsidered, lessThanOrEqualTo(spellingCandidateLimit));
      expect(result.poolSize, isNotNull);
      expect(result.poolSize!, lessThan(31600),
          reason: 'the trigram table is the whole point of the feature');
    });

    test('childern reaches child, through the morphology table', () async {
      // **The path, in full.** `children` is not a headword; it is an irregular
      // in the morphology table, and `children -> child` is in it. So the
      // distance is measured against the *form* `children` — one transposition
      // — and the form is then resolved through the table and checked against
      // the dictionary, which is where `child` comes from.
      final result = await engine.spellingSuggestions('childern');
      final child = result.suggestions
          .where((suggestion) => suggestion.entry.word == 'child')
          .toList();
      expect(child, isNotEmpty,
          reason: 'the near-misses are ${result.suggestions}');
      expect(child.first.distance, 1,
          reason: 'one transposition is one edit');
      expect(child.first.matchedForm, 'children',
          reason: 'the distance was measured against the form, not the headword');
    });

    test('child is not demoted behind Chilean', () async {
      final result = await engine.spellingSuggestions('childern');
      final words = result.suggestions.map((s) => s.entry.word).toList();
      expect(words, isNotEmpty);
      final child = words.indexOf('child');
      final chilean = words.indexOf('Chilean');
      expect(child, isNonNegative, reason: 'the words are $words');
      if (chilean >= 0) {
        expect(child, lessThan(chilean),
            reason: 'the right answer must not sit below a wrong one: $words');
      }
    });
  });

  group('the two kinds of result', () {
    test('a suggestion carries what was typed', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('childern');
      final suggestions =
          controller.items.whereType<DictionarySuggestionItem>().toList();
      expect(suggestions, isNotEmpty);
      expect(suggestions.first.typed, 'childern',
          reason: 'the card shows what the user typed, not what they meant');
      expect(suggestions.first.reason, 'spelling');
      controller.dispose();
    });

    test('a suggestion is never shown as the word the user typed', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('childern');
      for (final word in controller.items.whereType<DictionaryWordItem>()) {
        expect(word.entry.norm, isNot('childern'));
      }
      controller.dispose();
    });

    test('an inflected form is offered, never substituted', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('abandoning');
      final words =
          controller.items.whereType<DictionaryWordItem>().toList();
      expect(words, isEmpty,
          reason: 'a stem is a suggestion and never an exact hit');
      final suggestions =
          controller.items.whereType<DictionarySuggestionItem>().toList();
      expect(suggestions, isNotEmpty);
      expect(suggestions.first.typed, 'abandoning');
      expect(suggestions.first.entry.word, 'abandon');
      controller.dispose();
    });
  });

  group('the autocomplete', () {
    test('every word it offers is a real headword', () async {
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

    test('it never offers a stem', () async {
      // The README's own example: `suggest("aban")` is exactly `abandon`,
      // `abandoned` and `abandonment` — and never the invented `abandoning`,
      // which is not a word in the dictionary.
      final words =
          (await engine.autocomplete.search('aban')).map((e) => e.word).toList();
      expect(words, <String>['abandon', 'abandoned', 'abandonment']);
      expect(words, isNot(contains('abandoning')));
    });
  });

  group('a stem is valid only if the dictionary contains it', () {
    test('gas does not become ga', () async {
      final result = await engine.lookupEnglish('gas');
      expect(result, isA<ExactWord>());
      expect((result as ExactWord).entry.word, 'gas');
    });

    test('a stem that is not a headword is rejected', () async {
      // The `s` rule proposes `zza` for `zzas`; there is no such headword, so
      // the proposal dies. This is the `gas -> ga` failure in a form the `gas`
      // test alone cannot catch.
      final result = await engine.lookupEnglish('zzas');
      expect(result, isA<NoWord>());
    });
  });
}
