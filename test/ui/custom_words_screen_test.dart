import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/ui/custom_dictionary/add_custom_word_screen.dart';
import 'package:lexilearn/ui/custom_dictionary/custom_words_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../helpers/test_env.dart';

/// The screen's copy, in Arabic.
const _title = 'الكلمات المضافة';
const _searchHint = 'ابحث في كلماتك...';
const _noMatches = 'لا توجد كلمات تطابق بحثك.';
const _emptyHeadline = 'لا توجد كلمات في قاموسك بعد.';
const _emptySupporting = 'أضف كلمتك الأولى لتظهر هنا.';
const _addWord = 'إضافة كلمة';

/// The test words: English terms and Arabic meanings, one pair per search case.
const _serendipity = 'serendipity';
const _optimistic = 'optimistic';
const _wander = 'wander';

/// Mounts the list with the providers it and the add screen behind its empty
/// state both need.
Widget _host(VocabRepository repository) => MultiProvider(
  providers: <SingleChildWidget>[
    Provider<VocabRepository>.value(value: repository),
    ...appSeamProviders(settings: createAppSettings(repository)),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.light,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const CustomWordsScreen(),
  ),
);

Future<void> _pumpWords(WidgetTester tester, VocabRepository repository) async {
  await tester.pumpWidget(_host(repository));
  await settleDatabase(tester);
}

/// Adds one word to the user's dictionary outside the fake-async zone.
Future<void> _addWordToDatabase(
  WidgetTester tester,
  VocabRepository repository,
  String term,
  String meaning,
) => tester.runAsync(
  () => repository.addCustomWord(term: term, meaning: meaning),
);

/// Adds [count] distinct words, so a count label can be asserted against a real
/// list rather than against a number the screen invented.
Future<void> _addWords(
  WidgetTester tester,
  VocabRepository repository,
  int count,
) async {
  for (var i = 0; i < count; i++) {
    await _addWordToDatabase(tester, repository, 'word$i', 'معنى رقم $i');
  }
}

/// A text run inside the list screen only.
Finder _inWords(String text) => find.descendant(
  of: find.byType(CustomWordsScreen),
  matching: find.text(text),
);

/// The card holding the row for [term].
Finder _rowCard(String term) =>
    find.ancestor(of: _inWords(term), matching: find.byType(AppSurface));

Finder _rowHeart(String term) =>
    find.descendant(of: _rowCard(term), matching: find.byType(FavoriteButton));

Finder _rowTrash(String term) => find.descendant(
  of: _rowCard(term),
  matching: find.byIcon(Icons.delete_outline_rounded),
);

/// The exact sentence the dialog must show, quoted word and all.
String _question(String term) => 'هل أنت متأكد من حذف هذه الكلمة "$term"؟';

/// A destructive tap followed by the write and the screen's re-read.
Future<void> _writeAndRelist(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  for (var turn = 0; turn < 3; turn++) {
    await settleDatabase(tester);
  }
}

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('the count', () {
    // 0, 1, 2, 3 and 11 exercise every branch of `customWordCountLabel`,
    // including both sides of the 10/11 boundary.
    const cases = <(int, String)>[
      (0, 'لا كلمات بعد'),
      (1, 'كلمة واحدة'),
      (2, 'كلمتان'),
      (3, '3 كلمات'),
      (11, '11 كلمة'),
    ];

    for (final (count, label) in cases) {
      testWidgets('says «$label» for $count', (tester) async {
        useAPhone(tester);
        await _addWords(tester, harness.repository, count);
        await _pumpWords(tester, harness.repository);

        expect(_inWords(_title), findsOneWidget);
        expect(_inWords(label), findsOneWidget);
        if (count == 0) {
          // Nothing to list, and the screen says what to do about it.
          expect(_inWords(_emptyHeadline), findsOneWidget);
          expect(_inWords(_addWord), findsOneWidget);
          expect(find.byType(AppSurface), findsNothing);
        }
      });
    }

    testWidgets('the count is on the left and the back control on the right', (
      tester,
    ) async {
      useAPhone(tester);
      await _addWordToDatabase(
        tester,
        harness.repository,
        _serendipity,
        'صدفة.',
      );
      await _pumpWords(tester, harness.repository);

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        tester.getCenter(find.byTooltip('رجوع')).dx,
        greaterThan(width / 2),
      );
      expect(tester.getCenter(_inWords('كلمة واحدة')).dx, lessThan(width / 2));
    });
  });

  group('search', () {
    testWidgets('filters by English term and by Arabic meaning', (
      tester,
    ) async {
      useAPhone(tester);
      await _addWordToDatabase(
        tester,
        harness.repository,
        _serendipity,
        'صدفة سعيدة، اكتشاف غير متوقع.',
      );
      await _addWordToDatabase(
        tester,
        harness.repository,
        _optimistic,
        'متفائل',
      );
      await _addWordToDatabase(tester, harness.repository, _wander, 'يتجول');

      await _pumpWords(tester, harness.repository);

      expect(_inWords(_searchHint), findsOneWidget);
      expect(_inWords(_serendipity), findsOneWidget);
      expect(_inWords(_optimistic), findsOneWidget);
      expect(_inWords(_wander), findsOneWidget);
      expect(_inWords('3 كلمات'), findsOneWidget);

      // English, partial and lowercase.
      await tester.enterText(find.byType(TextField), 'ser');
      await tester.pump();
      expect(_inWords(_serendipity), findsOneWidget);
      expect(_inWords(_optimistic), findsNothing);
      expect(_inWords(_wander), findsNothing);
      // The count is the dictionary's size, not the filtered list's.
      expect(_inWords('3 كلمات'), findsOneWidget);

      // Arabic, through the same `SearchMatcher` the pack search uses.
      await tester.enterText(find.byType(TextField), 'متفائل');
      await tester.pump();
      expect(_inWords(_optimistic), findsOneWidget);
      expect(_inWords(_serendipity), findsNothing);
      expect(_inWords(_wander), findsNothing);

      // No match is a sentence, not an empty list.
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(_inWords(_noMatches), findsOneWidget);
      expect(find.byType(AppSurface), findsNothing);

      // Clearing the field brings all three back.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(_inWords(_serendipity), findsOneWidget);
      expect(_inWords(_optimistic), findsOneWidget);
      expect(_inWords(_wander), findsOneWidget);
    });
  });

  group('deleting a word', () {
    testWidgets('cancelling, tapping outside and back all change nothing', (
      tester,
    ) async {
      useAPhone(tester);
      await _addWordToDatabase(
        tester,
        harness.repository,
        _serendipity,
        'صدفة سعيدة.',
      );
      await _addWordToDatabase(
        tester,
        harness.repository,
        _wander,
        'يتجول بلا وجهة.',
      );
      await _pumpWords(tester, harness.repository);

      // `لا` closes the dialog and changes nothing.
      await tester.tap(_rowTrash(_serendipity));
      await tester.pumpAndSettle();
      expect(find.text(_question(_serendipity)), findsOneWidget);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(find.text(_question(_serendipity)), findsNothing);

      // A tap on the barrier closes it too, and is the third exit rather than
      // a second spelling of `لا`.
      await tester.tap(_rowTrash(_serendipity));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text(_question(_serendipity)), findsNothing);

      // The system back reaches the dialog, not the screen underneath.
      await tester.tap(_rowTrash(_serendipity));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_question(_serendipity)), findsNothing);
      expect(find.byType(CustomWordsScreen), findsOneWidget);

      // None of the three exits wrote.
      expect(_inWords(_serendipity), findsOneWidget);
      expect(_inWords(_wander), findsOneWidget);
      expect(_inWords('كلمتان'), findsOneWidget);
      final words = await readOutsideFakeAsync(
        tester,
        () => harness.repository.customWords(),
      );
      expect(words.map((entry) => entry.term), <String>[_serendipity, _wander]);
    });

    testWidgets('confirming deletes the row, the disk row and the count', (
      tester,
    ) async {
      useAPhone(tester);
      await _addWordToDatabase(
        tester,
        harness.repository,
        _serendipity,
        'صدفة سعيدة.',
      );
      await _addWordToDatabase(
        tester,
        harness.repository,
        _wander,
        'يتجول بلا وجهة.',
      );
      await _pumpWords(tester, harness.repository);

      await tester.tap(_rowTrash(_serendipity));
      await tester.pumpAndSettle();
      expect(find.text(_question(_serendipity)), findsOneWidget);

      await _writeAndRelist(tester, find.text('نعم'));

      expect(find.text(_question(_serendipity)), findsNothing);
      expect(_inWords(_serendipity), findsNothing);
      expect(_inWords(_wander), findsOneWidget);
      // The count came back from the same read as the list.
      expect(_inWords('كلمة واحدة'), findsOneWidget);

      final words = await readOutsideFakeAsync(
        tester,
        () => harness.repository.customWords(),
      );
      expect(words, hasLength(1));
      expect(words.single.term, _wander);
    });

    testWidgets('deleting the last word shows the empty state and add action', (
      tester,
    ) async {
      useAPhone(tester);
      await _addWordToDatabase(
        tester,
        harness.repository,
        _serendipity,
        'صدفة سعيدة.',
      );
      await _pumpWords(tester, harness.repository);

      await tester.tap(_rowTrash(_serendipity));
      await tester.pumpAndSettle();
      await _writeAndRelist(tester, find.text('نعم'));

      expect(find.byType(AppSurface), findsNothing);
      expect(_inWords(_emptyHeadline), findsOneWidget);
      expect(_inWords(_emptySupporting), findsOneWidget);
      expect(_inWords(_addWord), findsOneWidget);
      expect(_inWords('لا كلمات بعد'), findsOneWidget);
    });
  });

  group('the heart', () {
    testWidgets('toggles the favourite without opening or deleting the word', (
      tester,
    ) async {
      useAPhone(tester);
      await _addWordToDatabase(
        tester,
        harness.repository,
        _serendipity,
        'صدفة سعيدة.',
      );
      await _pumpWords(tester, harness.repository);

      expect(
        tester.widget<FavoriteButton>(_rowHeart(_serendipity)).isFavorite,
        isFalse,
      );

      await tester.tap(_rowHeart(_serendipity));
      await settleDatabase(tester);

      expect(
        tester.widget<FavoriteButton>(_rowHeart(_serendipity)).isFavorite,
        isTrue,
      );
      expect(find.byType(CustomWordsScreen), findsOneWidget);
      expect(find.byType(AddCustomWordScreen), findsNothing);
      expect(_inWords(_serendipity), findsOneWidget);
      expect(_inWords('كلمة واحدة'), findsOneWidget);

      var saved = await readOutsideFakeAsync(
        tester,
        () => harness.repository.isFavorite(
          packKey: customDictionaryPackKey,
          entryId: customEntryId(_serendipity),
        ),
      );
      expect(saved, isTrue);

      await tester.tap(_rowHeart(_serendipity));
      await settleDatabase(tester);

      expect(
        tester.widget<FavoriteButton>(_rowHeart(_serendipity)).isFavorite,
        isFalse,
      );
      saved = await readOutsideFakeAsync(
        tester,
        () => harness.repository.isFavorite(
          packKey: customDictionaryPackKey,
          entryId: customEntryId(_serendipity),
        ),
      );
      expect(saved, isFalse);
    });
  });

  testWidgets('the empty state adds a word and re-reads on the way back', (
    tester,
  ) async {
    useAPhone(tester);
    await _pumpWords(tester, harness.repository);

    expect(_inWords(_emptyHeadline), findsOneWidget);
    await tester.tap(_inWords(_addWord));
    await tester.pumpAndSettle();

    expect(find.byType(AddCustomWordScreen), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('custom-word-field')),
      _serendipity,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('custom-meaning-field')),
      'صدفة.',
    );
    await tester.tap(find.text('حفظ الكلمة'));
    await settleDatabase(tester);
    await tester.tap(find.text('تم'));
    await tester.pumpAndSettle();

    // Back is the way out of the add screen; the list re-reads when the push
    // it started completes.
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    expect(find.byType(CustomWordsScreen), findsOneWidget);
    expect(_inWords(_serendipity), findsOneWidget);
    expect(_inWords('كلمة واحدة'), findsOneWidget);
    expect(_inWords(_emptyHeadline), findsNothing);
  });

  test('the confirmation fills carry their white labels at AA', () {
    // The tokens are the argument; this is the measurement. The doc comments
    // in `design_tokens.dart` record the same numbers.
    expect(
      contrastRatio(AppColors.onSolidFill, AppColors.successFill),
      closeTo(5.02, 0.01),
    );
    expect(
      contrastRatio(AppColors.onSolidFill, AppColors.errorFill),
      closeTo(6.47, 0.01),
    );
    expect(
      contrastRatio(AppColors.onSolidFill, AppColors.successFill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(AppColors.onSolidFill, AppColors.errorFill),
      greaterThanOrEqualTo(4.5),
    );
  });
}
