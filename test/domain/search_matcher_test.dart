import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/search_matcher.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

/// The matcher is pure: a list in, a list out, no repository and no database.
/// That is why it can be tested against literals here, and why
/// `VocabRepository.search` is only a lookup followed by a call into it.
void main() {
  const entries = <VocabEntry>[
    VocabEntry(id: 'a', term: 'ghost clusters', translations: <String>['أشباح عنقودية']),
    VocabEntry(id: 'b', term: 'Buried', translations: <String>['دفن']),
    VocabEntry(id: 'c', term: 'check up', translations: <String>['فحص - مراجعة']),
  ];

  test('an empty query returns everything', () {
    expect(SearchMatcher.filter(entries, '   '), hasLength(3));
  });

  test('matches a term case-insensitively', () {
    expect(SearchMatcher.filter(entries, 'BURI').single.id, 'b');
  });

  test('matches a substring', () {
    expect(SearchMatcher.filter(entries, 'heck').single.id, 'c');
  });

  test('matches an Arabic translation', () {
    expect(SearchMatcher.filter(entries, 'دفن').single.id, 'b');
  });

  test('collapses surrounding and repeated whitespace', () {
    expect(SearchMatcher.filter(entries, '  ghost   clusters '), hasLength(1));
  });

  test('returns nothing when nothing matches', () {
    expect(SearchMatcher.filter(entries, 'zzz'), isEmpty);
  });

  test('normalise strips bidi control characters', () {
    expect(SearchMatcher.normalise('\u202b\u062f\u0641\u0646\u202c'), 'دفن');
  });

  // --- Beyond the plan's seven: the strip list the matcher actually has to
  // carry, and the two behaviours that list exists to protect. ---

  test('normalise strips the invisible marks Arabic text arrives with', () {
    // U+061C ARABIC LETTER MARK is emitted by Arabic IMEs and is by far the
    // most likely of these to appear in text pasted into the search field; the
    // zero-width family and U+FEFF ride with text out of a rich-text editor.
    // None of them are visible, so none of them may stop a match.
    const marks = <String>['\u061c', '\u200b', '\u200c', '\u200d', '\ufeff'];
    for (final mark in marks) {
      final label = 'U+${mark.codeUnitAt(0).toRadixString(16).toUpperCase()}';
      // U+200F rides along in every case so the assertion covers two stripped
      // marks of *different* classes at once: 'ta' + mark + RLM + 'rm' -> 'tarm'.
      expect(SearchMatcher.normalise('ta$mark\u200frm'),
          'tarm', reason: '$label was not stripped');
    }
  });

  test('normalise keeps the visible characters around a stripped mark', () {
    expect(SearchMatcher.normalise('\u061cمدفون\u200b'), 'مدفون');
  });

  test('a mark on either side of a match does not block it', () {
    // Both directions, because the mark can arrive on the stored text *or* on
    // what the user just typed, and neither may decide the outcome.
    const marked = <VocabEntry>[
      VocabEntry(id: 'm', term: 'marked\u200b', translations: <String>['تع\u061cريب']),
    ];
    expect(SearchMatcher.filter(marked, 'marked'), hasLength(1));
    expect(SearchMatcher.filter(marked, 'تعريب'), hasLength(1));
    expect(SearchMatcher.filter(marked, 'MARKED'), hasLength(1));
  });

  test('a query that is only whitespace and marks matches everything', () {
    // The empty-after-normalising case has to be decided *after* stripping, or
    // a field holding a single stray mark reads as "search for nothing".
    expect(SearchMatcher.filter(entries, '\u061c\u200b  '), hasLength(3));
  });

  test('normalise collapses whitespace and lowercases', () {
    expect(SearchMatcher.normalise('  Ghost\tCLUSTERS \n '), 'ghost clusters');
  });

  test('filter returns a copy, never the caller\'s own list', () {
    // `SearchController` hands these straight to a `ListView`. A caller that
    // mutated the result would otherwise be mutating the pack's entry list.
    final results = SearchMatcher.filter(entries, 'zzz');
    expect(identical(results, entries), isFalse);
    expect(SearchMatcher.filter(entries, '').first, same(entries.first));
  });

  test('every visible character of a match is significant', () {
    // The guard on the other side of collapsing whitespace: normalisation must
    // not turn two different queries into the same needle.
    expect(SearchMatcher.filter(entries, 'checkup'), isEmpty);
    expect(SearchMatcher.filter(entries, 'check up'), hasLength(1));
  });
}
