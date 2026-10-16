import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/domain/word_of_the_day.dart';
import 'package:lexilearn/ui/favorites/favorites_screen.dart';
import 'package:lexilearn/ui/flashcards/flashcards_screen.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_setup_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../helpers/test_env.dart';

/// The chrome strings the artwork draws on the Home phone. Pinned here rather
/// than derived, so a changed string is a failing test and not a silent drift
/// away from `docs/design/brand-reference.png`.
const _greeting = 'مرحباً بك!';
const _subheading = 'كل كلمة جديدة تقرّبك من هدفك';
const _searchHint = 'ابحث عن كلمة...';
const _wordOfTheDayLabel = 'Word of the Day';
const _meaningButton = 'معرفة المعنى';
const _noResults = 'لا توجد نتائج. جرّب جزءاً من الكلمة.';

/// The 2×2 quick-launch grid, in reading order: title, then the grey subtitle
/// the artwork prints under it.
const _tiles = <List<String>>[
  <String>['بطاقات التعلم', 'ابدأ الآن'],
  <String>['الاختبارات', 'اختبر نفسك'],
  <String>['المفضلة', 'كلماتك المفضلة'],
  <String>['إحصائياتك', 'تقدمك وإنجازك'],
];

/// Everything inside the Home screen and nothing outside it.
///
/// `الرئيسية` and `الاختبارات` are drawn twice on the mounted app — once on a
/// grid tile and once in the bottom bar — so every grid assertion is scoped
/// here. Unscoped, `find.text` matches both and `tap` throws instead of
/// navigating.
Finder inHome(String text) =>
    find.descendant(of: find.byType(HomeScreen), matching: find.text(text));

/// A `Text` carrying exactly [text].
///
/// `find.text` also matches an `EditableText`, so once the search field holds
/// `'مدفون'` a plain `find.text('مدفون')` finds the field *and* the result row.
/// The RTL assertion is about the result row, so it needs the `Text` alone.
Finder textWidget(String text) =>
    find.byWidgetPredicate((widget) => widget is Text && widget.data == text,
        description: 'a Text widget showing "$text"');

/// Sizes the surface like the phone the artwork is drawn on.
///
/// The default test surface is 800×600 and tall enough for the header, the field
/// and one row of the grid. The second row lands at y≈668, outside the root, and
/// `tap` on an off-screen widget throws — so every test that taps a tile sizes
/// the surface first. 360×780 is the golden's own logical size.
void _useAPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Mounts the app and gives the screen's *own* start-up read its turn.
///
/// `pumpShell` waits for the shell's read — the one that fills in the active pack
/// key. `HomeScreen` cannot read its pack until it has that key, so the
/// word-of-the-day read starts in the last moments of `pumpShell`'s window and
/// has none of it left. One more turn, on the same shared `shellDatabaseSettle`.
///
/// `pumpShell` is still what mounts the app; this only adds the second read's
/// wait, which is a fact about two sequential reads rather than a second helper.
/// Tasks 13-15 reach their screens the same way and will need the same turn.
Future<void> _pumpApp(WidgetTester tester, VocabRepository repository) async {
  await pumpShell(tester, repository);
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// Types [value] into the search field and lets both halves of the wait finish.
///
/// Two different clocks, and both are needed. The debounce is a `Timer` on the
/// fake-async clock, so it needs `pump(300ms)` — `pumpAndSettle` returns as soon
/// as no frame is scheduled, and a pending timer schedules none. The read that
/// follows is a real sqflite FFI future, which only completes on the real event
/// loop, which is the same one-line reason `pumpShell` exists; the wait itself is
/// the shared `shellDatabaseSettle`, not a copy of it.
Future<void> _search(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// Mounts [HomeScreen] on its own, with callbacks this test can observe.
///
/// `HomeShell` wires `onOpenWord` to a deliberate no-op until Task 14 lands
/// `WordDetailScreen`, so nothing observable reaches it through the app. This
/// mounts the screen directly instead. `HomeScreen` reads its pack from SQLite in
/// `initState`, so it needs the same one `runAsync` turn `pumpShell` gives the
/// shell — shared constant, not a private copy of the helper.
Future<void> _pumpHome(
  WidgetTester tester,
  TestHarness harness, {
  required String packKey,
  void Function(VocabEntry)? onOpenWord,
  void Function(String)? onPackSelected,
}) async {
  await tester.pumpWidget(
    Provider<VocabRepository>.value(
      value: harness.repository,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: HomeScreen(
          packKey: packKey,
          onPackSelected: onPackSelected ?? (_) {},
          onOpenWord: onOpenWord ?? (_) {},
        ),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// The pack under test, as literals.
///
/// Declared once and used for *both* the installed pack and the expected word of
/// the day. Reading them back out of the database inside a `testWidgets` body
/// would be the fake-async trap `test_env.dart` documents: a real sqflite future
/// never completes in that zone, and the test hangs instead of failing.
const _fixtureEntries = <VocabEntry>[
  VocabEntry(id: 'a', term: 'ghost clusters', translations: <String>['أشباح عنقودية']),
  VocabEntry(id: 'b', term: 'Buried', translations: <String>['دفن', 'مدفون']),
  VocabEntry(id: 'c', term: 'check up', translations: <String>['فحص - مراجعة']),
];

void main() {
  late TestHarness harness;

  Future<TestHarness> createHarness() => TestHarness.create(packs: <VocabPack>[
        VocabPack(
          schemaVersion: 1,
          packId: 'en_ar',
          title: 'English to Arabic',
          sourceLanguage: 'en',
          targetLanguage: 'ar',
          entries: _fixtureEntries,
        ),
      ]);

  setUp(() async => harness = await createHarness());
  tearDown(() => harness.dispose());

  group('the dashboard the artwork draws', () {
    testWidgets('the greeting, the search field and the grid are all there',
        (tester) async {
      await _pumpApp(tester, harness.repository);

      expect(inHome(_greeting), findsOneWidget);
      expect(inHome(_subheading), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(inHome(_searchHint), findsOneWidget);
      expect(inHome(_wordOfTheDayLabel), findsOneWidget);
    });

    testWidgets('the grid carries the artwork\'s four tiles', (tester) async {
      await _pumpApp(tester, harness.repository);

      for (final tile in _tiles) {
        expect(inHome(tile[0]), findsOneWidget, reason: 'missing tile "${tile[0]}"');
        expect(inHome(tile[1]), findsOneWidget, reason: 'missing "${tile[1]}"');
      }
    });

    testWidgets('every grid tile is a brand surface', (tester) async {
      await _pumpApp(tester, harness.repository);

      for (final tile in _tiles) {
        expect(
          find.ancestor(of: inHome(tile[0]), matching: find.byType(AppSurface)),
          findsOneWidget,
          reason: '"${tile[0]}" is not inside an AppSurface',
        );
      }
      // The word-of-the-day card is deliberately *not* an `AppSurface`: the brand
      // fills it with the primary colour, `AppSurface` paints the neutral surface
      // colour and has no override for it. So the assertion that covers it is the
      // one below — nothing on the dashboard is a bare `Card`.
    });

    testWidgets('nothing on the dashboard is a bare Card', (tester) async {
      // `Card` reaches its shadow through `elevation`, which the test rasteriser
      // strokes as an opaque black keyline — 29,111 black pixels the last time a
      // screen reached for it. Surfaces go through `AppSurface`.
      await _pumpApp(tester, harness.repository);

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the active pack is named on the screen', (tester) async {
      await _pumpApp(tester, harness.repository);

      expect(inHome('en_ar'), findsOneWidget);
    });

    testWidgets('the field asks for the brand hairline, not the theme\'s default',
        (tester) async {
      // Material 3 paints a filled field's outline with `colorScheme.onSurfaceVariant`
      // whatever `border` says, and the app theme sets that to the secondary
      // *text* grey. So the screen names the hairline per state, and this pins it.
      await _pumpApp(tester, harness.repository);

      final decoration =
          tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
      for (final entry in <String, InputBorder?>{
        'border': decoration.border,
        'enabledBorder': decoration.enabledBorder,
        'disabledBorder': decoration.disabledBorder,
      }.entries) {
        final border = entry.value;
        expect(border, isA<OutlineInputBorder>(), reason: entry.key);
        final outline = border! as OutlineInputBorder;
        expect(outline.borderSide.color, AppColors.borderLight,
            reason: '${entry.key} is not the brand hairline');
        // The artwork's search field is a full pill, not a 16px card radius.
        expect(outline.borderRadius.topLeft.x, AppRadii.pill,
            reason: '${entry.key} is not a pill');
      }
      expect(
        (decoration.focusedBorder! as OutlineInputBorder).borderSide.color,
        AppColors.primaryLight,
        reason: 'the focused field takes the brand purple',
      );
    });

    testWidgets('the field does not bind its text to Inter', (tester) async {
      // An Arabic query typed into an Inter-bound field renders as tofu, which
      // would make the bilingual search unreadable in the one place it is typed.
      await _pumpApp(tester, harness.repository);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, isNotNull);
      expect(field.style?.fontFamily, isNot('Inter'),
          reason: 'an explicit Inter style would render an Arabic query as tofu');
      // With no explicit style the field inherits the theme's family, which must
      // be the one that carries Arabic.
      expect(
        Theme.of(tester.element(find.byType(TextField))).textTheme.bodyLarge?.fontFamily,
        AppTheme.arabicFamily,
      );
    });

    testWidgets('the word-of-the-day card opens the word', (tester) async {
      final expected = WordOfTheDay.pick(_fixtureEntries, DateTime.now());
      await _pumpApp(tester, harness.repository);

      expect(inHome(_meaningButton), findsOneWidget);
      expect(inHome(expected.term), findsOneWidget);
    });

    testWidgets('the word of the day does not reshuffle after a rebuild',
        (tester) async {
      final expected = WordOfTheDay.pick(_fixtureEntries, DateTime.now());
      await _pumpApp(tester, harness.repository);

      // Search, which replaces the whole body, then come back.
      await _search(tester, 'bur');
      expect(inHome(_meaningButton), findsNothing,
          reason: 'the dashboard should have given way to the results');

      await _search(tester, '');
      expect(inHome(expected.term), findsOneWidget,
          reason: 'the card came back with a different word');
    });
  });

  group('searching', () {
    testWidgets('typing an English prefix narrows the list', (tester) async {
      await _pumpApp(tester, harness.repository);
      await _search(tester, 'bur');

      expect(inHome('Buried'), findsOneWidget);
      expect(inHome('ghost clusters'), findsNothing);
    });

    testWidgets('an Arabic query matches the translation and renders it RTL',
        (tester) async {
      await _pumpApp(tester, harness.repository);
      await _search(tester, 'مدفون');

      expect(inHome('Buried'), findsOneWidget);
      expect(textWidget('مدفون'), findsOneWidget);
      // An English term in an Arabic app must not be reordered by the app's
      // direction; a translation must be.
      expect(tester.widget<Text>(textWidget('Buried')).textDirection,
          TextDirection.ltr);
      expect(tester.widget<Text>(textWidget('مدفون')).textDirection,
          TextDirection.rtl);
    });

    testWidgets('a query with no matches shows an empty message', (tester) async {
      await _pumpApp(tester, harness.repository);
      await _search(tester, 'zzzzzz');

      expect(inHome(_noResults), findsOneWidget);
    });

    testWidgets('the results wait for the field to pause', (tester) async {
      // The debounce: 250ms is long enough to coalesce a fast typist and short
      // enough to feel immediate, and it is what keeps every keystroke from
      // hitting SQLite.
      await _pumpApp(tester, harness.repository);

      await tester.enterText(find.byType(TextField), 'bur');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Asserted on the results list rather than on the word "Buried": the word
      // of the day is one of this pack's three terms, so on some days of the
      // year the dashboard *is* showing "Buried" and the assertion would pass
      // or fail with the calendar instead of with the code.
      expect(find.byType(ListTile), findsNothing,
          reason: 'the database was queried before the field paused');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(inHome(_tiles[0][0]), findsOneWidget,
          reason: 'the dashboard should still be standing');
    });

    testWidgets('clearing the field brings the dashboard back', (tester) async {
      await _pumpApp(tester, harness.repository);
      await _search(tester, 'bur');
      expect(inHome('Buried'), findsOneWidget);

      await _search(tester, '');
      expect(inHome(_tiles[0][0]), findsOneWidget);
    });

    testWidgets('the clear button empties the field', (tester) async {
      await _pumpApp(tester, harness.repository);
      await _search(tester, 'bur');
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty);
      expect(inHome(_tiles[0][0]), findsOneWidget);
    });

    testWidgets('the clear button is not drawn while the field is empty',
        (tester) async {
      await _pumpApp(tester, harness.repository);

      expect(find.byIcon(Icons.close), findsNothing);
    });
  });

  group('the quick-launch grid', () {
    testWidgets('بطاقات التعلم opens the deck', (tester) async {
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[0][0]));
      await tester.pumpAndSettle();

      expect(find.byType(FlashcardsScreen), findsOneWidget);
    });

    testWidgets('الاختبارات opens the quiz setup', (tester) async {
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[1][0]));
      await tester.pumpAndSettle();

      expect(find.byType(QuizSetupScreen), findsOneWidget);
    });

    testWidgets('المفضلة opens the saved words', (tester) async {
      // Favourites is deliberately not a bottom-bar tab, per the artwork. The
      // tile is the other of the two doors the brand draws to it.
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[2][0]));
      await tester.pumpAndSettle();

      expect(find.byType(FavoritesScreen), findsOneWidget);
    });

    testWidgets('إحصائياتك opens the rest of the app', (tester) async {
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[3][0]));
      await tester.pumpAndSettle();

      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('a tile is a button to a screen reader', (tester) async {
      await _pumpApp(tester, harness.repository);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.button == true &&
              widget.properties.label?.contains(_tiles[2][0]) == true,
          description: 'a semantics node flagged as a button for "${_tiles[2][0]}"',
        ),
        findsOneWidget,
      );
    });
  });

  group('opening a word', () {
    testWidgets('the word-of-the-day button hands its word to onOpenWord',
        (tester) async {
      final opened = <VocabEntry>[];
      final expected = WordOfTheDay.pick(_fixtureEntries, DateTime.now());

      await _pumpHome(tester, harness,
          packKey: 'en_ar', onOpenWord: opened.add);

      await tester.tap(inHome(_meaningButton));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single, expected);
    });

    testWidgets('tapping a result hands that word to onOpenWord', (tester) async {
      final opened = <VocabEntry>[];
      await _pumpHome(tester, harness,
          packKey: 'en_ar', onOpenWord: opened.add);
      await _search(tester, 'bur');

      await tester.tap(inHome('Buried'));
      await tester.pumpAndSettle();

      expect(opened.single.term, 'Buried');
    });
  });

  group('with no pack installed', () {
    testWidgets('the grid still stands and no word of the day is invented',
        (tester) async {
      // `WordOfTheDay.pick` throws on an empty list, on purpose. The screen has
      // to decide what an empty pack looks like before it calls, and the answer
      // is "no card", not "an empty one".
      await _pumpHome(tester, harness, packKey: 'not-installed');

      expect(tester.takeException(), isNull);
      expect(inHome(_wordOfTheDayLabel), findsNothing);
      expect(inHome(_tiles[0][0]), findsOneWidget);
      expect(inHome(_greeting), findsOneWidget);
    });

    testWidgets('the header is drawn while the pack key is still resolving',
        (tester) async {
      // `HomeShell` starts with an empty key and fills it in once SQLite
      // answers. The screen must render through that window rather than sitting
      // on a blank page.
      await _pumpHome(tester, harness, packKey: '');

      expect(inHome(_greeting), findsOneWidget);
      expect(inHome(_wordOfTheDayLabel), findsNothing);
      expect(inHome(_tiles[0][0]), findsOneWidget);
    });
  });
}
