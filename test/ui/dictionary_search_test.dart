import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/ui/dictionary/dictionary_search_controller.dart';
import 'package:lexilearn/ui/dictionary/dictionary_word_screen.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

import '../data/dictionary/dictionary_test_env.dart';

/// The search path, and what it is allowed to do with what the user typed.
///
/// **A suggestion card, never a silent substitution** (the shipped README's
/// Pattern 2), and **never a stem in the type-ahead** (its Pattern 3).
void main() {
  late DictionaryFixture fixture;
  late DictionaryEngine engine;

  /// The two entries the widget tests draw.
  ///
  /// **Read in `setUpAll`, never inside a `testWidgets` body.** A real
  /// sqflite future never completes inside a fake-async zone, and the failure
  /// mode is a ten-minute hang with no message naming the cause
  /// (`docs/engineering-standards.md` §5).
  late DictionaryEntry childEntry;
  late DictionaryEntry abandonEntry;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
    engine = fixture.engine;
    childEntry = (await engine.lookupEnglish('child') as ExactWord).entry;
    abandonEntry = (await engine.lookupEnglish('abandon') as ExactWord).entry;
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('a typo', () {
    test('it is offered, and what was typed is kept', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('childern');
      expect(controller.items, isNotEmpty);
      final suggestions = controller.items
          .whereType<DictionarySuggestionItem>()
          .toList(growable: false);
      expect(suggestions, isNotEmpty);
      final child =
          suggestions.firstWhere((s) => s.entry.word == 'child');
      expect(child.typed, 'childern',
          reason: 'the card shows what the user typed, not what they meant');
      expect(child.reason, 'spelling');
      controller.dispose();
    });

    test('it is offered as a suggestion and never as the word itself',
        () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('childern');
      // **The typed word is not a word item.** A word item means "this is the
      // word you asked for", and `childern` is not a headword.
      final words = controller.items.whereType<DictionaryWordItem>().toList();
      for (final word in words) {
        expect(word.entry.norm, isNot('childern'));
      }
      controller.dispose();
    });
  });

  group('an inflected form', () {
    test('it is a suggestion, and it keeps what was typed', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('abandoning');
      expect(controller.items, isNotEmpty);
      final item = controller.items.first as DictionarySuggestionItem;
      expect(item.typed, 'abandoning');
      expect(item.entry.word, 'abandon');
      expect(item.reason, 'stem');
      controller.dispose();
    });

    test('it is never shown as the word the user typed', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('abandoning');
      final words = controller.items.whereType<DictionaryWordItem>().toList();
      expect(words, isEmpty,
          reason: 'a stem is a suggestion and never an exact hit');
      controller.dispose();
    });
  });

  group('the type-ahead', () {
    test('every word it offers is a real headword', () async {
      final controller = DictionarySearchController(engine: engine);
      for (final prefix in <String>['aban', 'child', 'teach', 'school']) {
        await controller.search(prefix);
        final words = controller.items.whereType<DictionaryWordItem>().toList();
        expect(words, isNotEmpty, reason: prefix);
        for (final word in words) {
          expect(await fixture.store.entryByNorm(word.entry.norm), isNotNull,
              reason: '${word.entry.word} must be a headword');
        }
      }
      controller.dispose();
    });

    test('it never offers an invented form', () async {
      // The README's own example: `autocomplete('aban')` is exactly
      // `abandon`, `abandoned` and `abandonment` — and never `abandoning`,
      // which is not a word in the dictionary.
      final heads = await engine.autocomplete.search('aban');
      final words = heads.map((e) => e.word).toList();
      expect(words, containsAll(<String>['abandon', 'abandoned', 'abandonment']));
      expect(words, isNot(contains('abandoning')));
    });
  });

  group('an Arabic query', () {
    test('it answers with a list, and every row carries the Arabic', () async {
      final controller = DictionarySearchController(engine: engine);
      await controller.search('مدرسه');
      final words = controller.items.whereType<DictionaryWordItem>().toList();
      expect(words.length, greaterThan(1));
      for (final word in words) {
        expect(word.arabic, isNotNull);
        expect(word.arabic, isNotEmpty);
      }
      controller.dispose();
    });

    test('a key shared by many senses answers with many rows', () async {
      // **The shape the brief asks for**: one Arabic key, dozens of headwords,
      // and a list that copes with them.
      final rows = await fixture.store.query(
        'SELECT norm_ar AS k, COUNT(DISTINCT entry_id) AS n FROM senses '
        'WHERE norm_ar IS NOT NULL GROUP BY norm_ar ORDER BY n DESC LIMIT 1',
      );
      final key = rows.first['k']! as String;
      final controller = DictionarySearchController(engine: engine);
      await controller.search(key);
      final words = controller.items.whereType<DictionaryWordItem>().toList();
      expect(words.length, greaterThan(20),
          reason: 'a list of twenty could not hold this answer');
      controller.dispose();
    });
  });

  group('the suggestion card', () {
    testWidgets('it shows what was typed and the word it is offering',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DictionarySuggestionCard(
              typed: 'childern',
              entry: childEntry,
              reason: 'spelling',
              onOpen: () {},
            ),
          ),
        ),
      );

      // **Both**, and they are different strings. A card that showed only the
      // offered word would be a silent substitution with a decoration on it.
      expect(find.textContaining('childern'), findsOneWidget);
      expect(find.textContaining('child'), findsWidgets);
      expect(find.text('هل تقصد child؟'), findsOneWidget);
    });

    testWidgets('it says why the word is being offered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DictionarySuggestionCard(
              typed: 'abandoning',
              entry: abandonEntry,
              reason: 'stem',
              onOpen: () {},
            ),
          ),
        ),
      );
      expect(find.text('صيغة مشتقة'), findsOneWidget);
    });

    testWidgets('tapping it opens the offered word, and the typed one is not '
        'opened', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DictionarySuggestionCard(
              typed: 'childern',
              entry: childEntry,
              reason: 'spelling',
              onOpen: () => opened++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}
