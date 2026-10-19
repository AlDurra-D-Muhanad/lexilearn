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
import 'package:lexilearn/ui/stats/stats_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:lexilearn/ui/wallpaper/nature_photo.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_scrim.dart';
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
/// A thin alias for the shared `useAPhone`, kept only so this file's intent is
/// readable at the call site, exactly as `_pumpApp` is for `pumpShell`. The
/// helper itself lives in `test/helpers/test_env.dart` because
/// `test/ui/stats_screen_test.dart` needs the identical thing and the two copies
/// were byte-for-byte the same.
void _useAPhone(WidgetTester tester) => useAPhone(tester);

/// Mounts the app and waits for both start-up reads.
///
/// A thin alias for the shared `pumpShell`, kept only so this file's intent is
/// readable at the call site. `HomeScreen` reads the pack a second time — it
/// cannot until the shell has resolved the pack key — and `pumpShell` waits for
/// both, so no test here needs a private `runAsync` turn of its own.
Future<void> _pumpApp(WidgetTester tester, VocabRepository repository) =>
    pumpShell(tester, repository);

/// Types [value] into the search field and lets both halves of the wait finish.
///
/// Two different clocks, and both are needed. The debounce is a `Timer` on the
/// fake-async clock, so it needs `pump(300ms)` — `pumpAndSettle` returns as soon
/// as no frame is scheduled, and a pending timer schedules none. The read that
/// follows is a real sqflite FFI future, which only completes on the real event
/// loop, which is the same one-line reason `pumpShell` exists.
///
/// **The second half is [realTurnThenSettle] and not `settleDatabase`, and the
/// order is the whole point.** Home's results list shows an indeterminate
/// `CircularProgressIndicator` while that read is in flight, and a
/// `pumpAndSettle` that runs while one is on screen never returns. These two
/// lines used to be written out privately here as well as in `golden_test.dart`,
/// which is two copies of a dance whose ordering is the thing worth sharing.
Future<void> _search(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await realTurnThenSettle(tester);
}

/// Mounts [HomeScreen] on its own, with callbacks this test can observe.
///
/// `HomeShell` wires `onOpenWord` to the real `Navigator.push` of
/// `WordDetailRoute` — Task 14 landed it — so this file does not depend on that
/// to observe the callback, and mounts the screen directly instead. `HomeScreen`
/// reads its pack from SQLite in `initState`, so it needs the same one real turn
/// `pumpShell` gives the shell — **[realTurnThenSettle], not a copy of it.** The
/// two lines this used to spell out *were* that helper's body, line for line,
/// under a doc comment that claimed they were not a copy.
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
      // `HomeScreen` carries the app's overflow menu, which reads the two
      // seams `LexiLearnApp` installs. This stand-in bypasses the app, so it
      // supplies them here — the same reason it supplies the repository.
      child: MultiProvider(
        providers: appSeamProviders(
          settings: createAppSettings(harness.repository),
        ),
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
    ),
  );
  await realTurnThenSettle(tester);
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

    testWidgets('every surface on the dashboard is an AppSurface', (tester) async {
      // The rule is meant to be checkable, not argued: the four grid tiles and
      // the word-of-the-day card all go through the shared surface, which is what
      // carries the brand shadow and the radius. The card says "not the neutral
      // fill" through `AppSurface.fill`, so it is still one of these.
      await _pumpApp(tester, harness.repository);

      for (final tile in _tiles) {
        expect(
          find.ancestor(of: inHome(tile[0]), matching: find.byType(AppSurface)),
          findsOneWidget,
          reason: '"${tile[0]}" is not inside an AppSurface',
        );
      }
      expect(
        find.ancestor(
            of: inHome(_meaningButton), matching: find.byType(AppSurface)),
        findsOneWidget,
        reason: 'the word-of-the-day card is not an AppSurface',
      );
      // And nothing anywhere on the dashboard is a bare Card, which is the other
      // half of the same rule.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the word-of-the-day card asks for the primary fill',
        (tester) async {
      await _pumpApp(tester, harness.repository);

      final surface = tester.widget<AppSurface>(
        find.ancestor(
          of: inHome(_meaningButton),
          matching: find.byType(AppSurface),
        ),
      );
      expect(surface.fill, AppColors.primaryLight,
          reason: 'the brand fills this card with the primary colour');
    });

    testWidgets('the active pack is named on the screen', (tester) async {
      await _pumpApp(tester, harness.repository);

      expect(inHome('en_ar'), findsOneWidget);
    });

    testWidgets('the field takes its outline from the theme, not from itself',
        (tester) async {
      // Material 3 synthesises a filled field's outline from `enabledBorder` /
      // `focusedBorder` / `disabledBorder` and ignores `border` when they are
      // null, falling back to `colorScheme.onSurfaceVariant` — the muted text
      // role. So the outline lives in `AppTheme`, exactly once, and this screen
      // restates none of it. The screen-side assertion is that the borders are
      // *absent* here; the theme-side guard is `test/design/input_outline_test.dart`.
      await _pumpApp(tester, harness.repository);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.border, isNull);
      expect(field.decoration?.enabledBorder, isNull);
      expect(field.decoration?.focusedBorder, isNull);
      expect(field.decoration?.disabledBorder, isNull);

      // And the mounted decorator still resolves the brand hairline, so this is
      // a check that the theme supplies it rather than that it is missing.
      final decoration =
          tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
      expect(
        (decoration.enabledBorder! as OutlineInputBorder).borderSide.color,
        AppColors.borderLight,
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

    testWidgets('the card carries one of the user\'s photographs', (tester) async {
      await _pumpApp(tester, harness.repository);

      final photo = find.byType(NaturePhoto);
      expect(photo, findsOneWidget,
          reason: 'the card is the artwork\'s photograph, not a brand wash');
      final card = tester.widget<NaturePhoto>(photo);
      expect(card.assetPath, isIn(Wallpapers.light),
          reason: 'a light phone draws the light set, as the user filed it');
      expect(card.nextAssetPath, isIn(Wallpapers.light),
          reason: 'the next one warmed is from the same set');
      expect(card.nextAssetPath, isNot(card.assetPath));
      expect(card.fit, BoxFit.cover,
          reason: 'the card is not 2:1, so contain would letterbox it');
    });

    testWidgets('it holds the photograph for ten seconds and then changes it',
        (tester) async {
      // The interval is read from the token the screen passes in, so a change to
      // `AppDurations.wallpaper` is what this test would have to be re-read for
      // — it does not carry a private copy of the number.
      await _pumpApp(tester, harness.repository);
      expect(AppDurations.wallpaper, const Duration(seconds: 10));

      String shown() =>
          tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;
      final first = shown();

      await tester.pump(const Duration(seconds: 9));
      expect(shown(), first, reason: 'it changed early');

      await tester.pump(const Duration(seconds: 1));
      expect(shown(), isNot(first), reason: 'ten seconds passed and it did not');
      // The fade is still running, so the previous frame is on screen too.
      expect(find.byType(Image), findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('the label, the term and the phonetic sit on the scrim, and '
        'the scrim stops above the button', (tester) async {
      await _pumpApp(tester, harness.repository);

      final surface = find.ancestor(
        of: inHome(_meaningButton),
        matching: find.byType(AppSurface),
      );
      final card = tester.getRect(surface);
      double bandOf(Finder text) {
        final r = tester.getRect(text);
        return (r.bottom - card.top) / card.height;
      }

      // Measured off this very tree, so the constant `WallpaperScrim.holdFraction`
      // is checked against the layout it exists for rather than against a
      // comment about a layout that might have moved.
      expect(bandOf(inHome(_wordOfTheDayLabel)), lessThan(WallpaperScrim.holdFraction));
      expect(bandOf(inHome(WordOfTheDay.pick(_fixtureEntries, DateTime.now()).term)),
          lessThan(WallpaperScrim.holdFraction));
      expect(
        bandOf(inHome(_meaningButton)),
        greaterThan(WallpaperScrim.holdFraction),
        reason: 'the button is an opaque amber pill; it needs no scrim, and '
            'one drawn over it would dim the picture for nothing',
      );

      // And the scrim really is a gradient that reaches zero at the bottom.
      // **Found by its gradient, not by being the first DecoratedBox** — the
      // card contains several (the button's own among them) and `.first` picked
      // one of those, which is how the first version of this assertion died on
      // a null `gradient`.
      final gradients = <Gradient>[];
      for (final element in find
          .descendant(of: surface, matching: find.byType(DecoratedBox))
          .evaluate()) {
        final decoration = (element.widget as DecoratedBox).decoration;
        if (decoration is BoxDecoration && decoration.gradient != null) {
          gradients.add(decoration.gradient!);
        }
      }
      expect(gradients, hasLength(1),
          reason: 'the card carries exactly one scrim');
      final gradient = gradients.single as LinearGradient;
      expect(gradient.colors.last.a, 0.0);
      expect(gradient.colors.first.a, WallpaperScrim.topAlpha);
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
      await realTurnThenSettle(tester);

      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty);
      expect(inHome(_tiles[0][0]), findsOneWidget);
    });

    testWidgets('the clear button is not drawn while the field is empty',
        (tester) async {
      await _pumpApp(tester, harness.repository);

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('the clear button appears with the first keystroke, not after '
        'the debounce', (tester) async {
      // Driven by the controller's query this button waited 250 ms for a
      // character the user had already typed: 0 clear buttons before typing,
      // 0 at +100 ms, 1 only once the debounce had fired. The field's own text
      // is the thing the button erases, so that is what it now reads.
      await _pumpApp(tester, harness.repository);
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.enterText(find.byType(TextField), 'b');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.close), findsOneWidget,
          reason: 'the clear button must not wait for the debounce');
    });

    testWidgets('a field holding only spaces shows no clear button',
        (tester) async {
      await _pumpApp(tester, harness.repository);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing,
          reason: 'spaces are not something to clear');
    });
  });

  group('the quick-launch grid', () {
    /// Asserts the tile *switched the bar* rather than pushing a route.
    ///
    /// The distinction is the whole point of the test and it has two halves: the
    /// bar's `selectedIndex` must have moved, and Home must be **gone from the
    /// tree**. A push leaves `HomeScreen` mounted underneath the pushed route and
    /// leaves `selectedIndex` at 0, so either half alone would pass for the
    /// behaviour this replaced.
    ///
    /// `skipOffstage: false` is load-bearing: the default skips offstage widgets,
    /// and a route pushed over Home makes it offstage — so the default finder
    /// reports "no HomeScreen" for a push and would pass this test for the wrong
    /// reason.
    void expectSwitchedTo(WidgetTester tester, int index, Type screen) {
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, index,
          reason: 'the bar did not follow the tile');
      expect(find.byType(screen), findsOneWidget);
      expect(find.byType(HomeScreen, skipOffstage: false), findsNothing,
          reason: 'Home is still in the tree, so a route was pushed over it');
    }

    testWidgets('بطاقات التعلم switches the bar to the deck', (tester) async {
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[0][0]));
      await tester.pumpAndSettle();
      // The tile switched the bar rather than pushing, so the destination
      // mounted for the first time and its own read is now in flight. A body that
      // ends here leaves that read running - found by the slow-database sweep,
      // which turned this into `A Timer is still pending even after the widget
      // tree was disposed` in all three of the tiles below.
      await settleDatabase(tester);

      expectSwitchedTo(tester, 1, FlashcardsScreen);
    });

    testWidgets('الاختبارات switches the bar to the quiz setup', (tester) async {
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[1][0]));
      await tester.pumpAndSettle();
      // As above: the destination's own read, drained before the body ends.
      await settleDatabase(tester);

      expectSwitchedTo(tester, 2, QuizSetupScreen);
    });

    testWidgets('إحصائياتك pushes statistics and leaves the bar where it was',
        (tester) async {
      // **A deliberate decision, replacing a placeholder this file used to pin.**
      // This test previously asserted `expectSwitchedTo(tester, 3, MoreScreen)` —
      // that the tile selected bar index 3, which is `المزيد`. It did so because
      // `المزيد` was still a placeholder with nothing behind it, and it was
      // flagged in review as a risk inherited by accident: it pinned a number
      // that stood for "somewhere else", not for a decision about statistics.
      //
      // The decision, and the evidence for it: `docs/design/brand-reference.png`
      // draws the bottom bar with exactly four items — الرئيسية, البطاقات,
      // الاختبارات, المزيد — in the light phone and again in the dark one, and
      // statistics is not among them in either. The same artwork draws a fourth
      // Home grid tile carrying the bar-chart glyph, and this is it. So
      // statistics is a route pushed from the grid, exactly as `المفضلة` is, and
      // index 3 stays `المزيد`.
      //
      // The push/switch distinction is asserted in both directions, because
      // either half alone passes for the other: a push leaves `HomeScreen`
      // mounted but offstage and the bar at 0, and a tab switch takes
      // `HomeScreen` out of the tree and moves the bar.
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[3][0]));
      await tester.pumpAndSettle();
      // The pushed screen issues its own read from `initState`, and
      // `pumpShell`'s two turns happened before it existed.
      await settleDatabase(tester);

      expect(find.byType(StatsScreen), findsOneWidget);
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget,
          reason: 'a push leaves Home mounted underneath; a tab switch removes it');
      expect(
        tester
            .widget<NavigationBar>(
                find.byType(NavigationBar, skipOffstage: false))
            .selectedIndex,
        0,
        reason: 'statistics is not one of the bar\'s four destinations',
      );
      expect(find.byType(MoreScreen, skipOffstage: false), findsNothing,
          reason: 'المزيد is a different destination, not a stand-in for stats');
    });

    testWidgets('the bar follows the tile and Back is not needed to return',
        (tester) async {
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[0][0]));
      await tester.pumpAndSettle();
      // **Task 15, and a timing assumption this test made implicitly.**
      // `_tiles[0][0]` is `بطاقات التعلم`, the one grid tile that is a **bar
      // destination**, and as of Task 15 it is the one that mounts a database
      // read of its own: `FlashcardsScreen` reads the pack to learn how many
      // cards the deck has. `pumpAndSettle` does not drive the real event loop —
      // only `runAsync` does — so without this turn the read is still in flight
      // when the test body ends, and the run fails with `A Timer is still pending
      // even after the widget tree was disposed` followed by
      // `SqfliteFfiException(error, Bad state: This database has already been
      // closed)`, thrown *after* the test had completed.
      //
      // Measured, not assumed: with `_DeckOwner` issuing **no read at all** this
      // test passes, and with the read restored and this line removed it fails.
      // So the read is what the wait is for — and the read is not optional, since
      // a deck cannot be dealt without the pack's words.
      //
      // This is the same helper, and the same reason, as `_openDestination` in
      // `home_shell_test.dart`, whose own doc comment names this situation: "a
      // destination or widget that mounts its own read needs only this".
      await settleDatabase(tester);
      expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);

      // Back through the bar, not through the navigator: the user is changing
      // tabs, not unwinding a route.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('الرئيسية'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
    });

    testWidgets('المفضلة pushes, because it is not a bar destination',
        (tester) async {
      // Favourites is deliberately not a bottom-bar tab, per the artwork. The
      // tile is one of the two doors the brand draws to it, so it must stay a
      // push: there is no tab for it to switch to.
      _useAPhone(tester);
      await _pumpApp(tester, harness.repository);
      await tester.tap(inHome(_tiles[2][0]));
      await tester.pumpAndSettle();
      // `FavoritesScreen` reads the saved words in its `initState`, and it
      // mounted on this tap. Drained before the body ends, for the reason the
      // other two tiles carry - and the sweep caught this one twice over: the
      // read outlived the test and came back as `Bad state: This database has
      // already been closed` on `SELECT entry_id FROM favorites ...`, thrown
      // after the test had completed.
      await settleDatabase(tester);

      expect(find.byType(FavoritesScreen), findsOneWidget);
      // Home is still in the tree underneath — offstage, because a route is now
      // over it. That is what a push means here, and it is the one tile where it
      // is correct. `skipOffstage: false` is what makes this assertion say
      // something: the default finder would report zero and pass a push test
      // with a tab switch in it.
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
      // The bar is on the Home route underneath, so it is offstage too and the
      // finder has to be told not to skip it.
      expect(
        tester
            .widget<NavigationBar>(
                find.byType(NavigationBar, skipOffstage: false))
            .selectedIndex,
        0,
      );
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
