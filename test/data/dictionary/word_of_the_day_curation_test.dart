import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/study_filter.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';

import 'dictionary_test_env.dart';

/// Which dictionary headwords may be the word of the day.
///
/// **The user's ruling, after seeing the card on a real phone:** it must draw
/// from the curated set, because the 31,600-entry sweep produced «creating by
/// removal» — a phrase, and a gloss rather than a word.
///
/// **The test that matters is the negative one**: the two words the user
/// actually saw are still in the dictionary, and are not in the pool. A rule
/// that excluded them by deleting them would pass a count and fail the app.
void main() {
  late DictionaryFixture fixture;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
  });

  tearDownAll(() async {
    await fixture.close();
  });

  test('the curated pool is 18,913 headwords of the 31,600', () async {
    final pool = await fixture.store.wordOfTheDayEntries();
    // Printed, because the report quotes this number and a number in a report
    // has to come from a run.
    // ignore: avoid_print
    print('word of the day: ${pool.length} of 31600 headwords are eligible');
    expect(pool.length, 18913);
    expect(pool.length, lessThan(await fixture.store.countStudyableEntries()));
  });

  test('every word of the day is a single lowercase Latin token with a '
      'meaning to open', () async {
    final pool = await fixture.store.wordOfTheDayEntries();
    final startsLowercase = RegExp(r'^[a-z]');
    final anyUppercase = RegExp('[A-Z]');
    final anyDigit = RegExp('[0-9]');

    for (final entry in pool) {
      expect(entry.word.contains(' '), isFalse,
          reason: 'a phrase is not a word: "${entry.word}"');
      expect(entry.word.length, greaterThanOrEqualTo(2),
          reason: '"${entry.word}" is too short to be a word of the day');
      expect(startsLowercase.hasMatch(entry.word), isTrue,
          reason: '"${entry.word}" begins a sentence, not a vocabulary card');
      expect(anyUppercase.hasMatch(entry.word), isFalse,
          reason: '"${entry.word}" carries a capital, which is a name or a '
              'brand');
      expect(anyDigit.hasMatch(entry.word), isFalse,
          reason: '"${entry.word}" is a number, not a word');
      expect(entry.hasArabic, isTrue,
          reason: '"${entry.word}" has no Arabic sense for the card to open');
      expect(
        entry.senses.any((sense) => (sense.arabic ?? '').trim().isNotEmpty),
        isTrue,
        reason: '"${entry.word}" would open an empty meaning screen',
      );
      expect(StudyFilter.admits(entry), isTrue,
          reason: '"${entry.word}" is an affix or a proper noun');
    }
  });

  test('the phrases the user saw are still in the dictionary, and out of the '
      'pool', () async {
    final words = <String>{
      for (final entry in await fixture.store.wordOfTheDayEntries())
        entry.word,
    };

    for (final phrase in <String>['creating by removal', 'my pleasure']) {
      final entry = await fixture.store.entryByNorm(phrase);
      expect(entry, isNotNull,
          reason: '"$phrase" must still be in the dictionary: this test is '
              'about what the card draws, not about deleting words');
      expect(entry!.hasArabic, isTrue);
      expect(words, isNot(contains(phrase)),
          reason: '"$phrase" is a phrase or a gloss, and it is what made the '
              'user rule the card must be curated');
    }
  });

  test('names that slip past the proper-noun rule are excluded by the case '
      'rule', () async {
    // The dictionary marks most names and not all of them. These three pass
    // the study filter, which is why the pool needs a rule of its own.
    final words = <String>{
      for (final entry in await fixture.store.wordOfTheDayEntries())
        entry.word,
    };
    for (final name in <String>['aaron', 'abadan', 'italian']) {
      final entry = await fixture.store.entryByNorm(name);
      expect(entry, isNotNull, reason: name);
      expect(StudyFilter.admits(entry!), isTrue,
          reason: '$name passes the study filter; the card still must not '
              'show it');
      expect(words, isNot(contains(entry.word)), reason: name);
    }
  });

  test('the pool the app asks for is 400 words, all eligible', () async {
    // The card does not load 18,913 entries; it asks for a pool and rotates
    // through it. The bound is part of the contract.
    final pool = await fixture.store.wordOfTheDayEntries(
      limit: dictionaryStudyPoolSize,
      salt: 1,
    );
    expect(pool, hasLength(dictionaryStudyPoolSize));
    for (final entry in pool) {
      expect(entry.hasArabic, isTrue, reason: entry.word);
      expect(entry.word.contains(' '), isFalse, reason: entry.word);
    }
  });

  test('the pool is stable within a day and a different sample the next', () async {
    final today = await fixture.store.wordOfTheDayEntries(limit: 40, salt: 1);
    final todayAgain =
        await fixture.store.wordOfTheDayEntries(limit: 40, salt: 1);
    final tomorrow = await fixture.store.wordOfTheDayEntries(limit: 40, salt: 2);

    expect(
      today.map((entry) => entry.norm).toList(),
      todayAgain.map((entry) => entry.norm).toList(),
    );
    expect(
      today.map((entry) => entry.norm).toList(),
      isNot(tomorrow.map((entry) => entry.norm).toList()),
    );
  });
}
