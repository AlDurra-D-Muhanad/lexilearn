import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/word_of_the_day.dart';

/// A pure function of `(entries, day)`. The whole point of the type is that the
/// Home screen can call it on every rebuild and get the same word back, so the
/// determinism is the feature and it is tested from both directions: the same
/// day twice, and different days.
void main() {
  const entries = <VocabEntry>[
    VocabEntry(id: 'a', term: 'serenity', translations: <String>['الهدوء والسكينة']),
    VocabEntry(id: 'b', term: 'ambition', translations: <String>['طموح']),
    VocabEntry(id: 'c', term: 'fervour', translations: <String>['حماس']),
    VocabEntry(id: 'd', term: 'clarity', translations: <String>['وضوح']),
  ];

  final day = DateTime(2026, 10, 14);

  test('the same day always picks the same entry', () {
    final first = WordOfTheDay.pick(entries, day);
    for (var repeat = 0; repeat < 50; repeat++) {
      expect(WordOfTheDay.pick(entries, day).id, first.id);
    }
  });

  test('picking twice in a row returns an identical object', () {
    // Stronger than "the same id": the screen rebuilds on every keystroke, and
    // handing it a new object each time would rebuild the card's subtree too.
    expect(WordOfTheDay.pick(entries, day), same(WordOfTheDay.pick(entries, day)));
  });

  test('the time of day does not change the pick', () {
    // A calendar day, not a moment in it: 03:00 and 23:00 on the same date are
    // the same word of the day.
    final atThree = WordOfTheDay.pick(entries, DateTime(2026, 10, 14, 3));
    final atTwentyThree = WordOfTheDay.pick(entries, DateTime(2026, 10, 14, 23, 59, 59));
    expect(atThree, same(atTwentyThree));
  });

  test('consecutive days never repeat the same entry', () {
    // With more than one entry, day N and day N+1 are different words. A hash
    // that ignored the date, or one seeded only by month, would fail here.
    for (var offset = 0; offset < 30; offset++) {
      final today = WordOfTheDay.pick(
          entries, DateTime(2026, 10, 14).add(Duration(days: offset)));
      final tomorrow = WordOfTheDay.pick(
          entries, DateTime(2026, 10, 14).add(Duration(days: offset + 1)));
      expect(today.id, isNot(tomorrow.id),
          reason: '2026-10-${14 + offset} repeated the same word');
    }
  });

  test('n consecutive days show every entry exactly once', () {
    // The rotation is a full cycle, not a random walk: no word is starved for
    // longer than the pack is long.
    final seen = <String>{
      for (var offset = 0; offset < entries.length; offset++)
        WordOfTheDay.pick(entries, day.add(Duration(days: offset))).id,
    };
    expect(seen, hasLength(entries.length));
  });

  test('a date before the epoch does not throw or go out of range', () {
    final picked = WordOfTheDay.pick(entries, DateTime(1969, 7, 20));
    expect(entries.map((entry) => entry.id), contains(picked.id));
  });

  test('a date far in the future still lands inside the pack', () {
    final picked = WordOfTheDay.pick(entries, DateTime(9999, 12, 31));
    expect(entries.map((entry) => entry.id), contains(picked.id));
  });

  test('a pack with one entry always shows that entry', () {
    const single = <VocabEntry>[
      VocabEntry(id: 'only', term: 'only', translations: <String>['وحدها']),
    ];
    for (var offset = 0; offset < 10; offset++) {
      expect(WordOfTheDay.pick(single, day.add(Duration(days: offset))).id, 'only');
    }
  });

  test('an empty pack throws rather than returning a placeholder', () {
    // The Home screen has to decide what an empty pack looks like before it
    // calls this; it must not be handed a zero-th entry.
    expect(() => WordOfTheDay.pick(const <VocabEntry>[], day),
        throwsA(isA<ArgumentError>()));
  });

  test('the pick depends on the entry list, not on a cached value', () {
    // Two packs of different length must not share an answer, or a pack switch
    // would keep showing the previous pack's word.
    const shorter = <VocabEntry>[
      VocabEntry(id: 'x', term: 'x', translations: <String>['x']),
    ];
    final fromLong = WordOfTheDay.pick(entries, day);
    final fromShort = WordOfTheDay.pick(shorter, day);
    expect(fromShort.id, 'x');
    expect(fromLong.id, isNot('x'));
  });
}
