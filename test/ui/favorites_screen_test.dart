import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/favorites/favorites_screen.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';

import '../helpers/test_env.dart';

/// The chrome, in Arabic.
const _title = 'المفضلة';
const _emptyHeadline = 'لا توجد كلمات مفضلة';
const _emptySupporting = 'اضغط القلب في تفاصيل الكلمة لحفظها هنا.';
const _loadFailed = 'تعذّر تحميل المفضلة.';
const _retry = 'إعادة المحاولة';
const _removeTitle = 'إزالة من المفضلة؟';
const _remove = 'إزالة';
const _cancel = 'إلغاء';

/// Home's quick-launch tile, as `test/ui/home_screen_test.dart` spells it.
const _tileFavorites = 'المفضلة';

/// Two packs sharing the **same entry ids**, so only a `pack_key` filter can tell
/// their favourites apart. `stats_screen_test.dart` uses the same fixture for the
/// same reason.
const _pack = VocabPack(
  schemaVersion: 1,
  packId: 'p',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['ألف']),
    VocabEntry(id: 'b', term: 'beta', translations: <String>['بيتا']),
    VocabEntry(id: 'c', term: 'gamma', translations: <String>['جاما']),
  ],
);

const _otherPack = VocabPack(
  schemaVersion: 1,
  packId: 'other',
  title: 'English to Turkish',
  sourceLanguage: 'en',
  targetLanguage: 'tr',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['alfa']),
    VocabEntry(id: 'b', term: 'beta', translations: <String>['beta']),
    VocabEntry(id: 'c', term: 'gamma', translations: <String>['gama']),
  ],
);

/// The word both packs call `a`, so a Home-pushed screen lists it whichever pack
/// the shell resolved — the two are told apart by their translations.
const _alpha = 'alpha';

/// Everything inside the favourites screen and nothing outside it.
Finder inFav(String text) => find.descendant(
    of: find.byType(FavoritesScreen), matching: find.text(text));

/// The card holding the row for [term].
///
/// **Scoped to one row, because a term and its translation can both appear on
/// screen** — and an unscoped `find.text('ألف')` would match a translation as
/// readily as a row.
Finder rowCard(String term) => find.ancestor(
      of: inFav(term),
      matching: find.byType(AppSurface),
    );

/// The heart on the row for [term].
Finder rowHeart(String term) => find.descendant(
      of: rowCard(term),
      matching: find.byType(FavoriteButton),
    );

/// Writes to the database from inside a `testWidgets` body, before anything is
/// mounted or after a screen has finished reading.
///
/// `tester.runAsync` is what makes it complete at all: a `testWidgets` body runs
/// in a fake-async zone where a real sqflite future never answers. Awaited bare,
/// it does not fail — it hangs to the ten-minute timeout.
Future<void> _seed(
  WidgetTester tester,
  Future<void> Function() write,
) async =>
    tester.runAsync(write);

/// **A write followed by the screen's own re-read, which is two sequential
/// database round trips, not one.**
///
/// Tapping a row's heart writes `setFavorite` and *then* the screen issues a
/// fresh `favorites` read — and the second is not even issued until the first has
/// answered. One `settleDatabase` covers one round trip and not reliably two
/// when the whole suite is running in parallel.
///
/// This was measured on Stats, where the same shape exists: with a single
/// settle, *confirming clears the tiles and the session list together* failed on
/// a full-suite run and passed every time the file ran alone — the screen was
/// still showing the pre-reset read, not a failed reset. Three turns is that
/// file's budget and the same reason; it is bounded and it decides nothing, the
/// assertions in the tests that call it are what decide pass or fail.
Future<void> _writeAndRelist(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  for (var turn = 0; turn < 3; turn++) {
    await settleDatabase(tester);
  }
}

/// A tap that reaches the database, and the one real turn that lets it land.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settleDatabase(tester);
}

/// Mounts `FavoritesScreen` on its own — no `HomeShell`, no bottom bar.
///
/// **The bar has four destinations and none of them is this one**, so nothing in
/// the app pushes this screen for a test to ride on except the Home tile, and
/// this is the shape that proves the screen needs neither. The repository comes
/// from `provider`, the theme and the RTL direction from the app.
Widget _host(
  VocabRepository repository, {
  required String packKey,
  ValueChanged<VocabEntry>? onOpenWord,
  Brightness brightness = Brightness.light,
}) =>
    Provider<VocabRepository>.value(
      value: repository,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: FavoritesScreen(
          packKey: packKey,
          onOpenWord: onOpenWord ?? (_) {},
        ),
      ),
    );

/// Saves a favourite, then mounts the screen and waits for its read.
Future<void> _pumpFavorites(
  WidgetTester tester,
  VocabRepository repository, {
  required String packKey,
  ValueChanged<VocabEntry>? onOpenWord,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(_host(
    repository,
    packKey: packKey,
    onOpenWord: onOpenWord,
    brightness: brightness,
  ));
  await settleDatabase(tester);
}

/// Saves [entryId] as a favourite in [packKey].
Future<void> _favorite(
  WidgetTester tester,
  VocabRepository repository, {
  required String packKey,
  required String entryId,
}) =>
    _seed(
      tester,
      () => repository.setFavorite(
        packKey: packKey,
        entryId: entryId,
        isFavorite: true,
      ),
    );

void main() {
  late TestHarness harness;

  /// One test closes the harness itself to force a read to fail, and `tearDown`
  /// must not close it a second time.
  var closed = false;

  setUp(() async {
    closed = false;
    harness = await TestHarness.create(packs: const <VocabPack>[_pack, _otherPack]);
  });

  tearDown(() async {
    if (!closed) await harness.dispose();
  });

  group('the list itself', () {
    testWidgets('an empty favourites list says so in words', (tester) async {
      // **Mounted directly, not through `HomeShell`.** The bottom bar has four
      // destinations — الرئيسية, البطاقات, الاختبارات, المزيد — and favourites
      // is not one of them, so this screen is pushed from Home's grid tile. The
      // plan's own step calls this out, and it is the only thing that can catch
      // a screen that only works as somebody else's child.
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      expect(inFav(_title), findsOneWidget);
      expect(inFav(_emptyHeadline), findsOneWidget);
      expect(inFav(_emptySupporting), findsOneWidget);
      // Not a blank page, and not a row of zeros — a count of 0 next to nothing
      // is indistinguishable from "the read failed".
      expect(find.text('0'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(AppSurface), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists every favourite in the pack', (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'c');

      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      expect(inFav(_alpha), findsOneWidget);
      expect(inFav('gamma'), findsOneWidget);
      // And the one that is not saved is not there.
      expect(inFav('beta'), findsNothing);
      expect(inFav(_emptyHeadline), findsNothing);
    });

    testWidgets('counts no other pack, even one holding the same word id',
        (tester) async {
      // Same ids on purpose: only a `pack_key` filter tells these apart, and a
      // filter on the entry id alone would show `alfa` here.
      await _favorite(tester, harness.repository, packKey: 'other', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'other', entryId: 'b');

      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      expect(inFav(_emptyHeadline), findsOneWidget);
      expect(inFav('alfa'), findsNothing);
      expect(inFav('beta'), findsNothing);
      expect(inFav(_alpha), findsNothing);
    });

    testWidgets('tapping a row calls onOpenWord with that entry', (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'c');

      final opened = <VocabEntry>[];
      await _pumpFavorites(
        tester,
        harness.repository,
        packKey: 'p',
        onOpenWord: opened.add,
      );

      await _tap(tester, find.text('gamma'));
      expect(opened, hasLength(1));
      expect(opened.single.id, 'c');
      expect(opened.single.term, 'gamma');
      expect(opened.single.translations, <String>['جاما']);

      // And the other row, so the finder above is pinned to *the row tapped*
      // rather than to the only row there was.
      await _tap(tester, find.text(_alpha));
      expect(opened.map((entry) => entry.id), <String>['c', 'a']);
    });

    testWidgets('the heart does not open the word', (tester) async {
      // Two controls in one row, and they are not the same control. A heart that
      // also called `onOpenWord` would make "remove this word" and "read this
      // word" one gesture.
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      final opened = <VocabEntry>[];
      await _pumpFavorites(
        tester,
        harness.repository,
        packKey: 'p',
        onOpenWord: opened.add,
      );

      await _tap(tester, rowHeart(_alpha));

      expect(opened, isEmpty);
      // It asked first, which is where this tap is supposed to end up.
      expect(inFav(_removeTitle), findsOneWidget);
    });
  });

  group('removing a favourite', () {
    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'b');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      await _tap(tester, rowHeart(_alpha));
      expect(inFav(_removeTitle), findsOneWidget);

      await _tap(tester, find.widgetWithText(TextButton, _cancel));

      expect(inFav(_removeTitle), findsNothing);
      expect(inFav(_alpha), findsOneWidget);
      // The confirmation is a layer over the list, not a replacement for it, so
      // the word it asked about is still readable underneath.
      expect(inFav('ألف'), findsOneWidget);
      final stillSaved = await readOutsideFakeAsync(
        tester,
        () => harness.repository.isFavorite(packKey: 'p', entryId: 'a'),
      );
      expect(stillSaved, isTrue);
    });

    testWidgets('confirming takes the word off the list and the disk',
        (tester) async {
      // **This is the test that makes the refresh load-bearing.** The tap writes
      // `setFavorite` and the screen then issues a *second* read; a screen that
      // removed the row optimistically and never re-read would pass every other
      // test in this file and fail here on the database assertion alone.
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'b');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      await _tap(tester, rowHeart(_alpha));
      await _writeAndRelist(tester, find.widgetWithText(FilledButton, _remove));

      expect(inFav(_removeTitle), findsNothing);
      // The list is repopulated from the database, not patched in memory: the
      // other row survives, and the removed one is gone.
      expect(inFav(_alpha), findsNothing);
      expect(inFav('beta'), findsOneWidget);
      expect(
        find.text('0'),
        findsNothing,
        reason: 'one favourite is left, and "no favourites" would be a lie',
      );

      final ids = await readOutsideFakeAsync(
          tester, () => harness.repository.favorites('p'));
      expect(ids.map((entry) => entry.id), <String>['b']);
    });

    testWidgets('removing the last word falls back to the empty state',
        (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      await _tap(tester, rowHeart(_alpha));
      await _writeAndRelist(tester, find.widgetWithText(FilledButton, _remove));

      expect(inFav(_emptyHeadline), findsOneWidget);
      expect(inFav(_alpha), findsNothing);
    });

    testWidgets('leaves another pack’s favourite alone', (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'other', entryId: 'a');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      await _tap(tester, rowHeart(_alpha));
      await _writeAndRelist(tester, find.widgetWithText(FilledButton, _remove));

      expect(inFav(_alpha), findsNothing);
      final other = await readOutsideFakeAsync(
          tester, () => harness.repository.favorites('other'));
      expect(other.map((entry) => entry.id), <String>['a'],
          reason: 'the same word id is saved in the other pack');
    });

    testWidgets('the system back cancels the confirmation rather than leaving the '
        'screen', (tester) async {
      // Saved in **both** packs, because `HomeShell` resolves whichever pack
      // sorts first and this test must not depend on which: same id, either pack,
      // the row below is the same row.
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'other', entryId: 'a');

      // Pushed, because `handlePopRoute` is about the *navigator* and a screen
      // mounted as `MaterialApp.home` has no route underneath to come back to.
      useAPhone(tester);
      await pumpShell(tester, harness.repository);
      await tester.tap(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.text(_tileFavorites),
      ));
      await tester.pumpAndSettle();
      // The pushed screen issues its own read from `initState`, and
      // `pumpShell`'s two turns happened before it existed.
      await settleDatabase(tester);
      expect(find.byType(FavoritesScreen), findsOneWidget);

      await _tap(tester, rowHeart(_alpha));
      expect(inFav(_removeTitle), findsOneWidget);

      // Blocked, so the route stays and the screen is still there.
      //
      // **The return value does not say the route popped, and is not asserted as
      // if it did.** `NavigatorState.maybePop` returns `true` for
      // `RoutePopDisposition.doNotPop` as well as for a real pop — it means "the
      // pop was handled", and being blocked on purpose counts as handled.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue,
          reason: 'the pop was handled — by being blocked, not by navigating');
      expect(find.byType(FavoritesScreen), findsOneWidget,
          reason: 'the route did not pop; back did not navigate away');
      expect(inFav(_removeTitle), findsNothing,
          reason: 'back dismissed the confirmation rather than being swallowed');
      expect(inFav(_alpha), findsOneWidget, reason: 'and it removed nothing');
    });
  });

  group('reached from Home', () {
    testWidgets('the المفضلة tile opens it and leaves the bar where it was',
        (tester) async {
      // Ruling: favourites is not a bottom-bar destination. The artwork's bar
      // draws exactly four items — الرئيسية, البطاقات, الاختبارات, المزيد — and
      // `lib/ui/home_shell.dart` documents why in the comment this task must not
      // delete.
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'other', entryId: 'a');

      // The surface is sized first: on the default 800×600 the tile is in the
      // grid's second row and therefore off-screen, and `tap` throws on it.
      useAPhone(tester);
      await pumpShell(tester, harness.repository);
      await tester.tap(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.text(_tileFavorites),
      ));
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(find.byType(FavoritesScreen), findsOneWidget);
      expect(inFav(_alpha), findsOneWidget);
      // `skipOffstage: false` throughout: a pushed route leaves the previous one
      // mounted and offstage, and the default finder would report "nothing there"
      // for exactly the state being asserted.
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
      expect(
        tester
            .widget<NavigationBar>(
                find.byType(NavigationBar, skipOffstage: false))
            .selectedIndex,
        0,
        reason: 'favourites is not a bottom-bar destination',
      );
    });

    testWidgets('tapping a row from Home opens the word detail', (tester) async {
      // **This is the test that pins the callback.** The `المفضلة` tile is the
      // only place in `lib/` that builds a `FavoritesScreen`, and it used to pass
      // `onOpenWord: (_) {}` — so tapping a saved word from Home did nothing at
      // all, and every other test in this file kept passing because they mount
      // the screen with their own recorder.
      //
      // Driven through the real app on purpose: a test that pumped
      // `FavoritesScreen` directly with a recording callback would pass whatever
      // the tile passes, which is exactly what was wrong.
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'other', entryId: 'a');

      useAPhone(tester);
      await pumpShell(tester, harness.repository);
      await tester.tap(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.text(_tileFavorites),
      ));
      await tester.pumpAndSettle();
      await settleDatabase(tester);
      expect(find.byType(FavoritesScreen), findsOneWidget);
      expect(inFav(_alpha), findsOneWidget);

      await tester.tap(inFav(_alpha));
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(find.byType(WordDetailScreen), findsOneWidget,
          reason: 'the row handed its entry to the shell, which pushed the detail');
      expect(find.byType(FavoritesScreen), findsNothing,
          reason: 'the detail replaced the list rather than stacking under it');
    });
  });

  group('a failed read', () {
    testWidgets('says so, and does not claim the pack is empty',
        (tester) async {
      // Close the database **before** mounting, so the screen's own start-up read
      // is the one that fails. `readOutsideFakeAsync` on the close, not a bare
      // `await`: a `testWidgets` body runs in a fake-async zone where a real
      // sqflite future never answers, and this one is a real close.
      closed = true;
      await readOutsideFakeAsync(tester, harness.dispose);

      await tester.pumpWidget(_host(harness.repository, packKey: 'p'));
      await settleDatabase(tester);

      expect(inFav(_loadFailed), findsOneWidget);
      expect(inFav(_emptyHeadline), findsNothing,
          reason: 'a broken read is not a fresh install');
      expect(find.text(_retry), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the brand rules', () {
    testWidgets('every row is an AppSurface and nothing is a bare Card',
        (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'b');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      expect(rowCard(_alpha), findsOneWidget);
      expect(rowCard('beta'), findsOneWidget);
      // The other half of the same rule: a bare `Card` renders a hard black
      // keyline in this rasteriser, measured at 29,111 pixels once.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the heart is the accent, and the accent is never body text',
        (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      // Every row here is a favourite, so every heart is filled and amber —
      // `design_tokens.dart` permits `#F59E0B` for icons and fills only.
      expect(
        tester.widget<Icon>(find.descendant(
            of: rowHeart(_alpha), matching: find.byType(Icon))).color,
        AppColors.accent,
      );
      expect(find.byIcon(Icons.favorite_border), findsNothing);

      // …and nothing the user *reads* is in it.
      final amberTexts = find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.color == AppColors.accent,
        description: 'a Text painted in the accent',
      );
      expect(amberTexts, findsNothing);
    });

    testWidgets('the term is a Latin run and its translation is not',
        (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _pumpFavorites(tester, harness.repository, packKey: 'p');

      final term = tester.widget<Text>(inFav(_alpha));
      expect(term.textDirection, TextDirection.ltr);
      expect(term.style?.fontFamily, 'Inter');
      expect(tester.widget<Text>(inFav('ألف')).textDirection, TextDirection.rtl);
    });

    testWidgets('the dark theme reaches the dark tokens', (tester) async {
      await _favorite(tester, harness.repository, packKey: 'p', entryId: 'a');
      await _pumpFavorites(tester, harness.repository, packKey: 'p',
          brightness: Brightness.dark);

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, AppColors.backgroundDark);
      expect(bar.surfaceTintColor, Colors.transparent);
      final surface = tester.widget<AppSurface>(rowCard(_alpha));
      expect(surface.fill, isNull,
          reason: 'a neutral surface, so it carries the dark hairline');
      expect(tester.takeException(), isNull);
    });
  });
}