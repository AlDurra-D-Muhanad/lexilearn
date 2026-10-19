import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';

/// The two search keys, rule by rule.
///
/// **Each of the README's rules gets its own test.** The Arabic key has five
/// rules and they are independent - folding a hamza and folding a ta marbuta
/// are different operations that happen to be applied in one pass - and a
/// single "the Arabic key works" test would pass with any four of the five
/// broken.
void main() {
  group('the Arabic key', () {
    test('rule 1: every hamza carrier folds onto alif', () {
      // أ U+0623, إ U+0625, آ U+0622, ٱ U+0671  ->  ا U+0627
      expect(normalizeArabic('\u0623'), '\u0627');
      expect(normalizeArabic('\u0625'), '\u0627');
      expect(normalizeArabic('\u0622'), '\u0627');
      expect(normalizeArabic('\u0671'), '\u0627');
      // Each character folds onto an alif; the fold is per character, so four
      // hamza carriers become four alifs and not one.
      expect(normalizeArabic('\u0623\u0625\u0622\u0671'),
          '\u0627\u0627\u0627\u0627');
    });

    test('rule 2: ta marbuta folds onto haa', () {
      // ة U+0629 -> ه U+0647
      expect(normalizeArabic('\u0629'), '\u0647');
      expect(normalizeArabic('\u0645\u062f\u0631\u0633\u0629'),
          '\u0645\u062f\u0631\u0633\u0647');
    });

    test('rule 3: alef maqsura and hamza-on-yaa fold onto yaa', () {
      // ى U+0649, ئ U+0626 -> ي U+064A
      expect(normalizeArabic('\u0649'), '\u064A');
      expect(normalizeArabic('\u0626'), '\u064A');
      expect(normalizeArabic('\u0649\u0626'), '\u064A\u064A');
    });

    test('rule 4: waw with hamza folds onto waw', () {
      // ؤ U+0624 -> و U+0648
      expect(normalizeArabic('\u0624'), '\u0648');
      // مؤة  ->  موه
      expect(normalizeArabic('\u0645\u0624\u0629'), '\u0645\u0648\u0647');
    });

    test('rule 5: the tashkeel and the tatweel are deleted', () {
      // ـ U+0640, ً U+064B, ٌ U+064C, ٍ U+064D, َ U+064E, ُ U+064F,
      // ِ U+0650, ّ U+0651, ْ U+0652, ٓ U+0653, ٰ U+0670
      for (final mark in <String>[
        '\u0640', '\u064B', '\u064C', '\u064D', '\u064E', '\u064F', '\u0650',
        '\u0651', '\u0652', '\u0653', '\u0670',
      ]) {
        expect(normalizeArabic(mark), '', reason: 'U+${mark.codeUnitAt(0).toRadixString(16)}');
      }
      // مَدْرَسَة  ->  مدرسه
      expect(normalizeArabic('\u0645\u064e\u062f\u0652\u0631\u064e\u0633\u064e\u0629'),
          '\u0645\u062f\u0631\u0633\u0647');
    });

    test('whitespace is collapsed to single spaces and trimmed', () {
      expect(normalizeArabic('  \u0645\u062f\u0631\u0633\u0629  '),
          '\u0645\u062f\u0631\u0633\u0647');
      expect(normalizeArabic('\u0645\u062f\u0631   \u0633\u0629'),
          '\u0645\u062f\u0631 \u0633\u0647');
      expect(normalizeArabic('\u0645\u062f\u0631\t\n\u0633\u0629'),
          '\u0645\u062f\u0631 \u0633\u0647');
    });

    test('every spelling of the same Arabic word gives the same key', () {
      // The point of the whole exercise: a user who types any of these has to
      // reach the same entry.
      const spellings = <String>[
        '\u0645\u064e\u062f\u0652\u0631\u064e\u0633\u064e\u0629', // مَدْرَسَة
        '\u0645\u062f\u0631\u0633\u0647', // مدرسه  (ta marbuta)
        '\u0645\u064e\u062f\u0651\u0631\u064e\u0633\u064e\u0647', // مَدْرّسَة
        '\u0645\u0652\u062f\u0631\u0633\u0629', // strip the marks
        '\u0645\u0640\u062f\u0631\u0633\u0647', // insert the tatweel
      ];
      final keys = spellings.map(normalizeArabic).toSet();
      expect(keys, hasLength(1), reason: 'the keys were $keys');
      expect(keys.single, '\u0645\u062f\u0631\u0633\u0647');
    });

    test('letters the table has never heard of pass through untouched', () {
      // A missing key must yield nothing, never a default. The letter ب is not
      // in any of the five rules and it must survive.
      expect(normalizeArabic('\u0628'), '\u0628');
      expect(normalizeArabic('\u0643'), '\u0643');
      // ا U+0621 is ALEF, not ALIF U+0627, and it is not one of the four
      // folded letters - so it comes out as it went in.
      expect(normalizeArabic('\u0621\u0628\u062c\u062f'),
          '\u0621\u0628\u062c\u062f');
    });

    test('an empty or null input is an empty key, not a crash', () {
      expect(normalizeArabic(null), '');
      expect(normalizeArabic(''), '');
      expect(normalizeArabic('   '), '');
    });

    test('the whitespace set is the one ECMAScript matches', () {
      // The hand-written set and `\s` must agree, or the normaliser and the
      // README's regex would drift apart.
      final regex = RegExp(r'\s');
      for (var code = 0; code < 0x3000; code++) {
        final ch = String.fromCharCode(code);
        final expected = regex.hasMatch(ch);
        final actual = whitespaceCodepoints.contains(code);
        expect(actual, expected, reason: 'U+${code.toRadixString(16)}');
      }
    });
  });

  group('the English key', () {
    test('is lowercased', () {
      expect(normalizeEnglish('Abandon'), 'abandon');
      expect(normalizeEnglish('ABANDON'), 'abandon');
    });

    test('drops both apostrophes', () {
      expect(normalizeEnglish("cat's"), 'cats');
      expect(normalizeEnglish('cat\u2019s'), 'cats');
      expect(normalizeEnglish("don't"), 'dont');
    });

    test('collapses whitespace and trims', () {
      expect(normalizeEnglish('  new   york '), 'new york');
      expect(normalizeEnglish('a\tb'), 'a b');
    });

    test('an empty or null input is an empty key, not a crash', () {
      expect(normalizeEnglish(null), '');
      expect(normalizeEnglish(''), '');
      expect(normalizeEnglish('   '), '');
    });

    test('the two case spellings of a headword share one key', () {
      expect(normalizeEnglish('Acre'), normalizeEnglish('acre'));
      expect(normalizeEnglish('Abu Dhabi'), normalizeEnglish('abu dhabi'));
    });
  });
}
