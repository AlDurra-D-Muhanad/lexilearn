import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/study_filter.dart';

import 'dictionary_test_env.dart';

/// Which entries may become a flashcard or a quiz question.
///
/// **The dictionary keeps all 31,600.** A dictionary contains affixes
/// legitimately and a user looking one up has to find it. **Only the study
/// surface filters them**, because a flashcard that says «-ation: …» teaches
/// nothing.
void main() {
  late DictionaryFixture fixture;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('the affixes', () {
    test('a headword beginning with a hyphen is an affix', () async {
      for (final word in <String>['-able', '-ation', '-er', '-ese', '-ness']) {
        final entry = await fixture.store.entryByNorm(word);
        expect(entry, isNotNull, reason: '$word is in the dictionary');
        expect(StudyFilter.isAffix(entry!), isTrue, reason: word);
        expect(StudyFilter.admits(entry), isFalse, reason: word);
      }
    });

    test('the affixes are in the dictionary, and they are counted', () async {
      final rows = await fixture.store.query(
        "SELECT word FROM entries WHERE word LIKE '-%' ORDER BY word",
      );
      expect(rows.length, 31,
          reason: 'the hyphen rule alone finds these affixes');
      for (final row in rows) {
        final word = row['word']! as String;
        final entry = await fixture.store.entryByNorm(word);
        expect(entry, isNotNull);
        expect(StudyFilter.admits(entry!), isFalse, reason: word);
      }
    });

    test('the dictionary marks its own prefixes, and they are excluded too',
        () async {
      // Eight prefixes that END with a hyphen, and two elisions that BEGIN
      // with one. The dictionary marks them `pref` / `suf`, and a learner
      // studying `bio-` is not studying a word.
      for (final word in <String>[
        'anti-',
        'bio-',
        'electro-',
        'extra-',
        'meso-',
        'pseudo-',
        'tri-',
        'vice-',
      ]) {
        final entry = await fixture.store.entryByNorm(word);
        expect(entry, isNotNull, reason: '$word is in the dictionary');
        expect(StudyFilter.isAffix(entry!), isTrue, reason: word);
      }
    });

    test('a real word is not an affix', () async {
      for (final word in <String>['child', 'abandon', 'school', 'run']) {
        final entry = await fixture.store.entryByNorm(word);
        expect(entry, isNotNull);
        expect(StudyFilter.isAffix(entry!), isFalse, reason: word);
      }
    });
  });

  group('the proper nouns', () {
    test('an entry whose senses are all proper nouns is a proper noun',
        () async {
      final entry = await fixture.store.entryByNorm('aachen');
      expect(entry, isNotNull);
      expect(StudyFilter.isProperNoun(entry!), isTrue);
      expect(StudyFilter.admits(entry), isFalse);
    });

    test('an entry with a common-noun sense is not a proper noun', () async {
      // `may` is the month and a modal verb, and the verb is what a learner
      // is asked about. A rule that excluded an entry for having *one*
      // proper-noun sense would throw the verb away with the month.
      final entry = await fixture.store.entryByNorm('may');
      expect(entry, isNotNull);
      expect(entry!.senses.any((s) => s.pos != 'prop. n'), isTrue,
          reason: 'may has a sense that is not a proper noun');
      expect(StudyFilter.isProperNoun(entry), isFalse);
      expect(StudyFilter.admits(entry), isTrue);
    });

    test('a common noun is not a proper noun', () async {
      for (final word in <String>['child', 'school', 'abandon']) {
        final entry = await fixture.store.entryByNorm(word);
        expect(entry, isNotNull);
        expect(StudyFilter.isProperNoun(entry!), isFalse, reason: word);
      }
    });
  });

  group('the filter and the SQL agree, on every headword', () {
    test('the SQL filter and the Dart filter admit the same entries', () async {
      // **Two implementations of one rule is two things to keep in
      // agreement**, so they are compared over the whole dictionary rather
      // than over a sample.
      final rows = await fixture.store.query(
        'SELECT id, word, norm FROM entries ORDER BY id',
      );
      expect(rows.length, 31600);
      final norms = <String>[
        for (final row in rows) row['norm']! as String,
      ];
      // **Chunked**, because SQLite's parameter limit is 999 by default and
      // 31,600 placeholders is not a query.
      final dartAdmits = <String>{};
      for (var start = 0; start < norms.length; start += 500) {
        final end = (start + 500).clamp(0, norms.length);
        final chunk = await fixture.store.entriesByNormsWithSenses(
          norms.sublist(start, end),
        );
        for (final entry in chunk) {
          if (StudyFilter.admits(entry)) dartAdmits.add(entry.norm);
        }
      }
      final sqlAdmits = await fixture.store.studyableEntries();
      expect(sqlAdmits.length, dartAdmits.length,
          reason: 'the SQL filter and the Dart filter are the same rule and '
              'must admit the same number of entries');
      expect(
        sqlAdmits.map((e) => e.norm).toSet(),
        dartAdmits,
        reason: 'and they must admit the same entries',
      );
    });
  });

  group('the numbers the report quotes', () {
    test('the dictionary has 31,600 entries and the filter admits some of them',
        () async {
      final total = await fixture.store.query('SELECT COUNT(*) AS n FROM entries');
      expect((total.first['n']! as num).toInt(), 31600);
      final admitted = await fixture.store.countStudyableEntries();
      // Printed, because the report quotes this number and a number in a
      // report has to come from a run.
      // ignore: avoid_print
      print('study filter: $admitted of 31600 entries admitted, '
          '${31600 - admitted} excluded');
      expect(admitted, greaterThan(0));
      expect(admitted, lessThan(31600));
    });

    test('every admitted entry has at least one Arabic sense', () async {
      // The brief's measurement: no entry in this dictionary has neither an
      // Arabic nor an English sense, so there is no blank card.
      final rows = await fixture.store.query(
        'SELECT COUNT(*) AS n FROM entries e WHERE '
        "e.id NOT IN (SELECT entry_id FROM senses WHERE ar IS NOT NULL) "
        'AND e.id NOT IN (SELECT entry_id FROM senses WHERE en IS NOT NULL)',
      );
      expect((rows.first['n']! as num).toInt(), 0,
          reason: 'no entry has neither Arabic nor English');
    });

    test('the study pool is drawn from the admitted entries', () async {
      final pool = await fixture.store.studyableEntries(limit: 50);
      expect(pool.length, 50);
      for (final entry in pool) {
        expect(StudyFilter.admits(entry), isTrue, reason: entry.word);
        expect(entry.senses, isNotEmpty);
      }
    });

    test('the pool is stable within a day and different the next', () async {
      final today = await fixture.store.studyableEntries(limit: 20, salt: 1);
      final todayAgain = await fixture.store.studyableEntries(limit: 20, salt: 1);
      final tomorrow = await fixture.store.studyableEntries(limit: 20, salt: 2);
      expect(
        today.map((e) => e.norm).toList(),
        todayAgain.map((e) => e.norm).toList(),
      );
      expect(
        today.map((e) => e.norm).toList(),
        isNot(tomorrow.map((e) => e.norm).toList()),
      );
    });
  });
}
