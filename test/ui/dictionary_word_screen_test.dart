import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/ui/dictionary/dictionary_word_screen.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

import '../data/dictionary/dictionary_test_env.dart';

/// The word screen, and the long text it has to lay out.
///
/// **The measurements are the data's, not the test's.** The shipped
/// dictionary's longest English gloss is **616 characters** (on `sun letter`),
/// its longest Arabic is **366** (on `yield`) and its longest example
/// sentence is **236** (on `hypertext`). This file reads those three out of
/// the shipped artefact and mounts the screen on them, so the layout is
/// checked against the worst case that actually exists rather than against a
/// string somebody invented.
void main() {
  late DictionaryFixture fixture;

  /// The three worst cases, read out of the shipped data.
  late DictionaryEntry longestGloss;
  late DictionaryEntry longestArabic;
  late DictionaryEntry longestExample;

  /// A short entry, for the size comparison.
  ///
  /// **Read in `setUpAll`**, because a real sqflite future never completes
  /// inside a `testWidgets` body and the failure mode is a ten-minute hang
  /// with no message naming the cause (`docs/engineering-standards.md` §5).
  late DictionaryEntry shortEntry;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();

    final glossRow = await fixture.store.query(
      'SELECT e.norm AS norm, MAX(LENGTH(s.en)) AS n FROM senses s '
      'JOIN entries e ON e.id = s.entry_id GROUP BY e.id '
      'ORDER BY n DESC LIMIT 1',
    );
    final arabicRow = await fixture.store.query(
      'SELECT e.norm AS norm, MAX(LENGTH(s.ar)) AS n FROM senses s '
      'JOIN entries e ON e.id = s.entry_id GROUP BY e.id '
      'ORDER BY n DESC LIMIT 1',
    );
    final exampleRow = await fixture.store.query(
      'SELECT e.norm AS norm, MAX(LENGTH(x.text)) AS n FROM examples x '
      'JOIN senses s ON s.id = x.sense_id JOIN entries e ON e.id = s.entry_id '
      'GROUP BY e.id ORDER BY n DESC LIMIT 1',
    );

    longestGloss = (await fixture.store.entryByNorm(glossRow.first['norm']! as String))!;
    longestArabic = (await fixture.store.entryByNorm(arabicRow.first['norm']! as String))!;
    longestExample = (await fixture.store.entryByNorm(exampleRow.first['norm']! as String))!;
    shortEntry = (await fixture.store.entryByNorm('child'))!;
  });

  tearDownAll(() async {
    await fixture.close();
  });

  /// Mounts the screen on a phone and returns the tester.
  Future<void> pumpWord(
    WidgetTester tester,
    DictionaryEntry entry,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DictionaryWordScreen(
          entry: entry,
          isFavorite: false,
          onToggleFavorite: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the three worst cases in the corpus are what this file claims', () {
    // **The measurements, read out of the shipped data.** A test that quoted
    // a number nobody measured is a claim, and §1 is about claims.
    final gloss = longestGloss.senses
        .map((s) => s.gloss?.length ?? 0)
        .reduce((a, b) => a > b ? a : b);
    final arabic = longestArabic.senses
        .map((s) => s.arabic?.length ?? 0)
        .reduce((a, b) => a > b ? a : b);
    final example = longestExample.senses
        .expand((s) => s.examples)
        .map((e) => e.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    // ignore: avoid_print
    print('longest text in the corpus: gloss $gloss, arabic $arabic, '
        'example $example');
    expect(gloss, 616);
    expect(arabic, 366);
    expect(example, 236);
  });

  testWidgets('the longest gloss lays out without overflowing', (tester) async {
    await pumpWord(tester, longestGloss);
    // **An overflow is a test failure**, because Flutter reports it as an
    // exception in the test zone. This test passing *is* the assertion that
    // the 616-character gloss fitted.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('sun letter'), findsWidgets);
  });

  testWidgets('the longest Arabic lays out without overflowing', (tester) async {
    await pumpWord(tester, longestArabic);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the longest example lays out without overflowing',
      (tester) async {
    await pumpWord(tester, longestExample);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card is sized by its own content and not by the corpus',
      (tester) async {
    // **The second half of the ruling.** A screen that sized its cards to
    // the longest string in the corpus would leave every ordinary word with
    // a screen full of empty space.
    await pumpWord(tester, longestGloss);
    final tall = _senseCardHeight(tester);

    final short = shortEntry;
    await pumpWord(tester, short);
    final shortHeight = _senseCardHeight(tester);

    expect(tall, greaterThan(shortHeight * 2),
        reason: 'a card with a 616-character gloss cannot be the same height '
            'as a card with a two-word gloss');
  });

  testWidgets('the Arabic in a sense is readable, not a wall', (tester) async {
    // **The Arabic is set at a title size and not at a display size.** A
    // 366-character Arabic string set at `headlineSmall` is a wall, and the
    // first sense's Arabic is the one thing a user reads first.
    //
    // **The entry is rebuilt with that one sense**, because a `ListView` only
    // builds what is on screen and the long Arabic may be on a later sense
    // of an entry with several.
    final sense = longestArabic.senses.firstWhere(
      (s) => (s.arabic?.length ?? 0) > 300,
    );
    final oneSense = DictionaryEntry(
      id: longestArabic.id,
      word: longestArabic.word,
      norm: longestArabic.norm,
      ipa: longestArabic.ipa,
      hasArabic: longestArabic.hasArabic,
      senses: <DictionarySense>[sense],
    );
    await pumpWord(tester, oneSense);
    final arabic = find.descendant(
      of: find.byType(DictionaryWordScreen),
      matching: find.byWidgetPredicate(
        (w) => w is Text && (w.data?.length ?? 0) > 300,
      ),
    );
    expect(arabic, findsWidgets);
    final text = tester.widget<Text>(arabic.first);
    expect(text.style?.fontSize, lessThan(30),
        reason: 'a 366-character Arabic string at 30px is unreadable');
  });
}

/// The height of the first sense card on screen, or 0 when there is none.
double _senseCardHeight(WidgetTester tester) {
  final card = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_SenseCard',
  );
  if (card.evaluate().isEmpty) return 0;
  return tester.getSize(card.first).height;
}
