import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';

import 'dictionary_test_env.dart';

/// The Arabic search path, and the shape its answer has to have.
///
/// **A list, and not one result.** The brief's measurement: 34,778 distinct
/// normalised Arabic keys, 14,759 of them shared by more than one sense, and
/// the single most-shared key resolving to 68 headwords. This file measures
/// the shipped data with the app's own normalisation rather than taking those
/// figures on trust, and it checks the shape the search path has to have.
void main() {
  late DictionaryFixture fixture;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('the shape of the answer', () {
    test('an Arabic query answers with a list of hits', () async {
      final hits = await fixture.engine.searchArabic('مدرسه');
      expect(hits.length, greaterThan(1),
          reason: 'the README\'s own example is four headwords');
      expect(hits.map((h) => h.entry.word),
          containsAll(<String>['school', 'schoolhouse', 'edifice', 'teacheress']));
    });

    test('the most-shared key answers with many headwords, and the list copes',
        () async {
      // **The key the brief names, found by measurement rather than by
      // assertion.** The most-shared normalised Arabic key in the shipped
      // dictionary, and how many headwords it resolves to.
      final rows = await fixture.store.query(
        'SELECT norm_ar AS k, COUNT(DISTINCT entry_id) AS n FROM senses '
        'WHERE norm_ar IS NOT NULL GROUP BY norm_ar ORDER BY n DESC LIMIT 1',
      );
      expect(rows, isNotEmpty);
      final key = rows.first['k']! as String;
      final shared = (rows.first['n']! as num).toInt();
      // ignore: avoid_print
      print('the most-shared whole-list Arabic key resolves to $shared '
          'headwords');

      final hits = await fixture.engine.searchArabic(key);
      expect(hits.length, greaterThanOrEqualTo(shared),
          reason: 'the search must not drop a headword the key resolves to');
      expect(hits.length, greaterThan(20),
          reason: 'a list of twenty could not hold this answer');
    });

    test('every hit carries the headword and the Arabic that matched',
        () async {
      final hits = await fixture.engine.searchArabic('مدرسه');
      expect(hits, isNotEmpty);
      for (final hit in hits) {
        expect(hit.entry.word, isNotEmpty);
        expect(hit.arabic, isNotNull,
            reason: 'a row with no Arabic tells the user nothing about which '
                'sense matched');
        expect(hit.arabic, isNotEmpty);
      }
    });

    test('the exact key comes before the prefix matches', () async {
      // The exact key is the answer; the keys that merely start with it are
      // the fallback. `test/data/dictionary/engine_test.dart` pins this for
      // the engine, and the store's own ordering has to agree with it.
      final hits = await fixture.engine.searchArabic('كتاب');
      expect(hits, isNotEmpty);
      expect(hits.first.entry.word, 'book');
    });

    test('a word that is not in the dictionary finds nothing', () async {
      final hits = await fixture.engine.searchArabic('مدرسيل');
      expect(hits, isEmpty);
    });
  });

  group('a key inside a list of synonyms', () {
    test('the second and third words of a synonym list are found', () async {
      // **The case the whole-list key cannot reach.** The dictionary stores
      // `روديسيا, زمبابوي, زيمبابوي` as one key, so the first word is
      // reachable by a prefix scan and the other two are not — unless the
      // search looks inside the list.
      final rows = await fixture.store.query(
        "SELECT ar FROM senses WHERE norm_ar LIKE '%, %' AND ar LIKE '%,%' "
        'LIMIT 200',
      );
      // Find a list with three or more elements, and take its second one.
      String? second;
      for (final row in rows) {
        final parts = (row['ar']! as String).split(',');
        if (parts.length < 3) continue;
        second = normalizeArabic(parts[1].trim());
        if (second.isNotEmpty) break;
      }
      expect(second, isNotNull,
          reason: 'the dictionary has synonym lists of three or more');
      final hits = await fixture.engine.searchArabic(second!);
      expect(hits, isNotEmpty,
          reason: 'a word the row visibly contains has to be findable');
    });

    test('the wildcards in a query are not wildcards', () async {
      // `LIKE` treats `%` and `_` as wildcards, and a query is a user's
      // typing. Without the escape, `a_b` would match `axb`.
      final hits = await fixture.engine.searchArabic('%');
      expect(hits, isEmpty);
    });
  });

  group('the numbers, measured with the app\'s own normalisation', () {
    test('the distinct Arabic keys and the shared ones', () async {
      final whole = await fixture.store.query(
        'SELECT COUNT(DISTINCT norm_ar) AS n FROM senses WHERE norm_ar IS NOT NULL',
      );
      final distinctWhole = (whole.first['n']! as num).toInt();
      final sharedWhole = await fixture.store.query(
        'SELECT COUNT(*) AS n FROM (SELECT norm_ar FROM senses '
        'WHERE norm_ar IS NOT NULL GROUP BY norm_ar HAVING COUNT(*) > 1)',
      );
      // ignore: avoid_print
      print('Arabic keys: $distinctWhole distinct whole-list keys, '
          '${(sharedWhole.first['n']! as num).toInt()} of them shared by more '
          'than one sense');

      // **The same count over the individual synonyms**, which is the key a
      // user actually types. The comma-separated list is one `norm_ar` but
      // several words.
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
      var sharedKeys = 0;
      var maxHeadwords = 0;
      for (final heads in byKey.values) {
        if (heads.length > 1) sharedKeys++;
        if (heads.length > maxHeadwords) maxHeadwords = heads.length;
      }
      // ignore: avoid_print
      print('Arabic keys: ${byKey.length} distinct per-synonym keys, '
          '$sharedKeys of them shared by more than one headword, '
          'the most shared resolving to $maxHeadwords headwords');
      expect(byKey.length, greaterThan(distinctWhole ~/ 2));
      expect(maxHeadwords, greaterThan(1));
    });
  });
}
