import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';

/// The rules of the user's own dictionary, as pure functions.
///
/// The specification is the user's `README.MD`:
/// *«عندنا يضيف المستخدم كلمة كلمة دون معنى او معنى دون كلمة يرفض الحفظ»* —
/// both fields are required — and *«ان يستطيع المستخدم انشاء قاموسه الخاص و جعل
/// امكانية اختيار هذا القاموس كحزمة مستقلة»* — one pack of its own.
///
/// **The literals here are literals on purpose.** A test that compares a
/// constant with itself passes whatever the constant becomes; the strings the
/// user actually reads are written out.
void main() {
  group('the names the user sees', () {
    test('the pack key is reserved, the title is the artwork\'s, and the chip '
        'says whose words these are', () {
      expect(customDictionaryPackKey, 'my_dictionary');
      expect(customDictionaryTitle, 'قاموسك الخاص');
      expect(customDictionaryChip, 'كلماتك');
    });

    test('the field bounds are the artwork\'s 0/500 and a real word limit', () {
      // The drawing puts `0/500` under the meaning field, so 500 is the number.
      expect(customMeaningMaxLength, 500);
      // A hundred characters is longer than any English word, and short
      // enough that the field cannot be used as a notebook.
      expect(customWordMaxLength, 100);
    });

    test('the entry id namespace is `mine:`', () {
      expect(customEntryPrefix, 'mine:');
    });
  });

  group('cleaning and normalising a typed word', () {
    test('the stored form is trimmed and its whitespace is collapsed', () {
      expect(cleanCustomTerm('  serendipity  '), 'serendipity');
      expect(cleanCustomTerm('check\t\n up'), 'check up');
      expect(cleanCustomTerm('  '), '');
    });

    test('case and spacing are not meaning', () {
      expect(normaliseCustomTerm('Serendipity'), 'serendipity');
      expect(normaliseCustomTerm('  SERENDIPITY '), 'serendipity');
      expect(normaliseCustomTerm('check\tup'), 'check up');
    });

    test('an Arabic word is normalised without being latinised', () {
      expect(normaliseCustomTerm('  البرمجة '), 'البرمجة');
    });
  });

  group('the entry id', () {
    test('is the readable slug plus a digest, and the digest is pinned', () {
      // **The literal, not the constant**: the id is what a favourite and a
      // progress row are filed under, so it is an on-device fact, not a
      // formatting detail.
      expect(customEntryId('serendipity'), 'mine:serendipity-bd6a3f');
    });

    test('is stable across case and surrounding space', () {
      expect(
        customEntryId('  Serendipity  '),
        customEntryId('serendipity'),
      );
    });

    test('keeps `check up` and `check-up` apart after the slug collapses both',
        () {
      // The slug alone would make these the same id, and then one word would
      // overwrite the other's favourite and progress.
      expect(customEntryId('check up'), isNot(customEntryId('check-up')));
      expect(
        customEntryId('check up'),
        startsWith('mine:check-up-'),
      );
      expect(
        customEntryId('check-up'),
        startsWith('mine:check-up-'),
      );
    });

    test('falls back to `word` when there is no Latin slug to read', () {
      // An Arabic term has no `[a-z0-9]` to keep. The id is ugly and never
      // shown: the user reads `VocabEntry.term`.
      final id = customEntryId('البرمجة');
      expect(id, startsWith('mine:word-'));
      expect(id.length, 'mine:word-'.length + 6);
    });

    test('an empty term still produces a well-formed id', () {
      // The screen refuses an empty word before this is reached; the function
      // itself must not produce `mine:-`.
      expect(customEntryId(''), startsWith('mine:word-'));
    });
  });

  group('the entry the rest of the app sees', () {
    test('carries the cleaned term, one translation, and the same id', () {
      final entry = customEntry(
        term: '  Serendipity ',
        meaning: '  صدفة سعيدة  ',
      );
      expect(entry.term, 'Serendipity');
      expect(entry.translations, <String>['صدفة سعيدة']);
      expect(entry.id, 'mine:serendipity-bd6a3f');
      // The study surfaces read `primaryTranslation`; the meaning must land
      // where they expect it.
      expect(entry.primaryTranslation, 'صدفة سعيدة');
    });
  });

  group('the count label under the list\'s title', () {
    test('Arabic counts its nouns in three ranges', () {
      // `3 كلمات` is wrong for 1, 2 and 11, which is what makes this a rule
      // rather than a string interpolation.
      expect(customWordCountLabel(0), 'لا كلمات بعد');
      expect(customWordCountLabel(1), 'كلمة واحدة');
      expect(customWordCountLabel(2), 'كلمتان');
      expect(customWordCountLabel(3), '3 كلمات');
      expect(customWordCountLabel(10), '10 كلمات');
      expect(customWordCountLabel(11), '11 كلمة');
      expect(customWordCountLabel(100), '100 كلمة');
    });
  });

  group('the refusal', () {
    test('carries the Arabic sentence the screen shows', () {
      const refusal = CustomDictionaryException('اكتب الكلمة أولاً.');
      expect(refusal.message, 'اكتب الكلمة أولاً.');
      expect(refusal.toString(), contains('اكتب الكلمة أولاً.'));
      expect(refusal, isA<Exception>());
    });
  });
}
