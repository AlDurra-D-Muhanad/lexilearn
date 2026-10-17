import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';

import '../helpers/test_env.dart';

/// The chrome this screen is titled with, and its two optional section headings.
const _title = 'تفاصيل الكلمة';
const _synonymsHeading = 'المترادفات';
const _examplesHeading = 'أمثلة أخرى';
const _add = 'أضف إلى المفضلة';
const _remove = 'إزالة من المفضلة';

/// What the bundled dataset actually holds: a term and a translation, and
/// nothing else. `English.txt` carries no phonetic, no part of speech, no
/// synonyms and no examples, so this is the *common* shape and the rich one
/// below is the hypothetical.
const _bare = VocabEntry(
  id: 'fever-1',
  term: 'fever',
  translations: <String>['حمى'],
);

/// The artwork's word: `docs/design/brand-reference.md` §4ب names
/// `serenity` / `/səˈrenəti/` / `noun` / `الهدوء والسكينة` /
/// `peace · tranquility · calmness`, and two example sentences.
const _rich = VocabEntry(
  id: 's-1',
  term: 'serenity',
  phonetic: '/səˈrenəti/',
  partOfSpeech: 'noun',
  translations: <String>['الهدوء والسكينة'],
  synonyms: <String>['peace', 'tranquility', 'calmness'],
  examples: <String>[
    'The room was filled with serenity.',
    'Meditation brings inner serenity.',
  ],
);

/// The pack the harness installs for the route tests and the Home test.
///
/// The word-of-the-day card shows one of these, and the Home test does not care
/// which — it taps the card's button, not a named word.
const _pack = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(
      id: 'serenity-1',
      term: 'serenity',
      translations: <String>['الهدوء والسكينة'],
      phonetic: '/səˈrenəti/',
    ),
    VocabEntry(
      id: 'ambition-1',
      term: 'ambition',
      translations: <String>['طموح'],
    ),
  ],
);

/// The label on the word-of-the-day card's button, as
/// `test/ui/home_screen_test.dart` spells it.
const _meaningButton = 'معرفة المعنى';

/// Everything inside the word detail screen and nothing outside it.
Finder inWord(String text) =>
    find.descendant(of: find.byType(WordDetailScreen), matching: find.text(text));

/// The card that holds [text].
Finder wordCard(String text) =>
    find.ancestor(of: inWord(text), matching: find.byType(AppSurface));

/// Mounts the screen the way the app does: the brand theme and the app-wide RTL
/// direction, both from `LexiLearnApp`. A bare `MaterialApp` would leave the
/// screen on Material's own palette and the test asserting brand tokens would be
/// asserting nothing.
Widget _host(
  VocabEntry entry, {
  bool isFavorite = false,
  VoidCallback? onToggleFavorite,
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: WordDetailScreen(
        entry: entry,
        isFavorite: isFavorite,
        onToggleFavorite: onToggleFavorite ?? () {},
      ),
    );

void main() {
  group('the route that owns the favourite state', () {
    late TestHarness harness;

    setUp(() async =>
        harness = await TestHarness.create(packs: const <VocabPack>[_pack]));
    tearDown(() => harness.dispose);

    Widget route({required VocabEntry entry}) => Provider<VocabRepository>.value(
          value: harness.repository,
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            builder: (context, child) =>
                Directionality(textDirection: TextDirection.rtl, child: child!),
            home: WordDetailRoute(entry: entry, packKey: 'en_ar'),
          ),
        );

    /// A write followed by the heart's own rebuild, and the real event loop both
    /// need. The tap writes `setFavorite` and the optimistic `setState` that puts
    /// the heart in is synchronous, so one settle is enough here — unlike the
    /// favourites list, which then issues a *second* read.
    Future<void> tapHeart(WidgetTester tester) async {
      await tester.tap(find.byType(FavoriteButton));
      await settleDatabase(tester);
    }

    testWidgets('opens an unsaved word with an empty heart', (tester) async {
      await tester.pumpWidget(route(entry: _pack.entries[0]));
      await settleDatabase(tester);

      expect(find.byType(WordDetailScreen), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('opens an already-saved word with a filled one', (tester) async {
      // `runAsync`, not a bare `await`. A `testWidgets` body runs in a fake-async
      // zone where a real sqflite future never completes — and the failure mode
      // is not an error, it is a hang until the ten-minute timeout. Measured: this
      // line took the whole file to `TIMEOUT after 300s`, stopping at
      // `opens an already-saved word with a filled one`. See
      // `docs/engineering-standards.md` §5.
      await tester.runAsync(() => harness.repository.setFavorite(
          packKey: 'en_ar', entryId: 'serenity-1', isFavorite: true));

      await tester.pumpWidget(route(entry: _pack.entries[0]));
      await settleDatabase(tester);

      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('the heart fills on tap and the write lands', (tester) async {
      await tester.pumpWidget(route(entry: _pack.entries[0]));
      await settleDatabase(tester);

      await tapHeart(tester);
      expect(find.byIcon(Icons.favorite), findsNWidgets(2));

      // **The database, not just the pixels.** The heart is filled
      // optimistically, so a test that stopped here would pass on a screen whose
      // write never reached SQLite.
      final saved = await readOutsideFakeAsync(tester,
          () => harness.repository.isFavorite(packKey: 'en_ar', entryId: 'serenity-1'));
      expect(saved, isTrue);

      // And back the other way.
      await tapHeart(tester);
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));
      final after = await readOutsideFakeAsync(tester,
          () => harness.repository.isFavorite(packKey: 'en_ar', entryId: 'serenity-1'));
      expect(after, isFalse);
    });

    testWidgets('a write that fails puts the heart back', (tester) async {
      await tester.pumpWidget(route(entry: _pack.entries[0]));
      await settleDatabase(tester);

      // Close the database underneath the repository, so the write the tap fires
      // is the one that fails. Nothing else here touches it, and nothing is
      // primed: a "just prove it is broken" call would leave its own
      // `database_closed` exception in flight, which is the one thing
      // `takeException` at the end of this test is there to catch.
      await readOutsideFakeAsync(tester, harness.dispose);

      await tapHeart(tester);

      // The optimistic claim is withdrawn rather than left standing: the screen
      // never says a word is saved when the database refuses to keep it.
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('reached from Home', () {
    late TestHarness harness;

    // Built here, **not inside the test body**. `TestHarness.create` opens a real
    // database and a `testWidgets` body runs in a fake-async zone in which a real
    // future never completes — which does not fail, it hangs to the ten-minute
    // timeout. Measured: with `TestHarness.create` awaited inside the body this
    // group took the whole file to `TIMEOUT after 300s`, stopping at the first
    // line of this test. The same one-line reason `pumpShell` exists; see
    // `docs/engineering-standards.md` §5.
    setUp(() async =>
        harness = await TestHarness.create(packs: const <VocabPack>[_pack]));
    tearDown(() => harness.dispose);

    testWidgets('the معرفة المعنى button opens it and leaves the bar where it was',
        (tester) async {
      // `HomeShell._openWordDetail` used to be an empty body with a comment
      // saying this task would fill it in. A no-op that says it is waiting for
      // the thing that is supposed to do it is exactly the false comment
      // `docs/engineering-standards.md` §1 is about, so the tap is what pins it.
      useAPhone(tester);
      await pumpShell(tester, harness.repository);
      await tester.tap(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.text(_meaningButton),
      ));
      await tester.pumpAndSettle();
      // The pushed route issues its own read from `initState`, and `pumpShell`'s
      // two turns happened before it existed.
      await settleDatabase(tester);

      expect(find.byType(WordDetailScreen), findsOneWidget);
      expect(inWord(_title), findsOneWidget);
      // **Whichever word the calendar picked**, it is one of the pack's. The word
      // of the day moves with the date, so naming a single entry here is a
      // calendar-dependent test — and it failed for exactly that reason once,
      // reporting a missing word rather than a missing screen.
      expect(
        find.descendant(
          of: find.byType(WordDetailScreen),
          matching: find.textContaining(RegExp(r'^(serenity|ambition)$')),
        ),
        findsOneWidget,
      );
      // `skipOffstage: false`: a pushed route leaves the previous one mounted and
      // offstage, and the default finder reports "nothing there" for exactly the
      // state being asserted.
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
      expect(
        tester
            .widget<NavigationBar>(
                find.byType(NavigationBar, skipOffstage: false))
            .selectedIndex,
        0,
        reason: 'the word detail is a route, not a bottom-bar destination',
      );
    });
  });

  group('the word itself', () {
    testWidgets('shows the term LTR and the meaning RTL', (tester) async {
      await tester.pumpWidget(_host(_rich));

      expect(tester.widget<Text>(inWord('serenity')).textDirection,
          TextDirection.ltr);
      expect(tester.widget<Text>(inWord('الهدوء والسكينة')).textDirection,
          TextDirection.rtl);
    });

    testWidgets('names the brand Latin face for every Latin run', (tester) async {
      await tester.pumpWidget(_host(_rich));

      // Tajawal carries Latin glyphs of its own, so a term left on the ambient
      // family would render in Tajawal's Latin and read as an accident.
      for (final text in <String>[
        'serenity',
        '/səˈrenəti/',
        'The room was filled with serenity.',
      ]) {
        expect(tester.widget<Text>(inWord(text)).style?.fontFamily, 'Inter',
            reason: '"$text" is a Latin run');
      }
    });

    testWidgets('a word with no extra sections says so with no stranded headings',
        (tester) async {
      await tester.pumpWidget(_host(_bare));

      expect(inWord('fever'), findsOneWidget);
      expect(inWord('حمى'), findsOneWidget);

      // An always-visible heading over nothing would be a lie, and the bundled
      // dataset has none of this data at all — so the common case must render
      // the bare word and nothing else.
      expect(inWord(_synonymsHeading), findsNothing);
      expect(inWord(_examplesHeading), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows pronunciation, part of speech, synonyms and examples',
        (tester) async {
      await tester.pumpWidget(_host(_rich));

      expect(inWord('/səˈrenəti/'), findsOneWidget);
      expect(inWord('noun'), findsOneWidget);
      expect(inWord(_synonymsHeading), findsOneWidget);
      for (final synonym in <String>['peace', 'tranquility', 'calmness']) {
        expect(inWord(synonym), findsOneWidget);
      }
      expect(inWord(_examplesHeading), findsOneWidget);
      // Both of the artwork's sentences, not just the first.
      expect(inWord('The room was filled with serenity.'), findsOneWidget);
      expect(inWord('Meditation brings inner serenity.'), findsOneWidget);
    });

    testWidgets('the speaker glyph is a glyph, not a control', (tester) async {
      await tester.pumpWidget(_host(_rich));

      // The artwork draws 🔊 beside the pronunciation. Text-to-speech is out of
      // scope by user decision, so it is an `Icon` and not a button: no tap
      // target, nothing that could start playback.
      final glyph = tester.widget<Icon>(find.byIcon(Icons.volume_up_rounded));
      expect(glyph.color, AppColors.accent);
      expect(glyph.semanticLabel, isNull);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.volume_up_rounded),
          matching: find.byType(InkResponse),
        ),
        findsNothing,
        reason: 'an IconButton would be an InkWell above it',
      );
    });
  });

  group('the favourite control', () {
    testWidgets('is a border heart in the secondary ink when not favourited',
        (tester) async {
      await tester.pumpWidget(_host(_bare));

      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2),
          reason: 'the AppBar action and the button under the body');
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(
        tester.widget<Icon>(find.descendant(
            of: find.byType(FavoriteButton), matching: find.byType(Icon))).color,
        AppColors.textSecondaryLight,
      );
    });

    testWidgets('is a filled heart in the accent when favourited', (tester) async {
      await tester.pumpWidget(_host(_bare, isFavorite: true));

      expect(find.byIcon(Icons.favorite), findsNWidgets(2),
          reason: 'the AppBar action and the button under the body');
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(
        tester.widget<Icon>(find.descendant(
            of: find.byType(FavoriteButton), matching: find.byType(Icon))).color,
        AppColors.accent,
      );
    });

    testWidgets('taps on the action call back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(_bare, onToggleFavorite: () => taps++));

      await tester.tap(find.byType(FavoriteButton));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('the bottom action is a full-width pill that says what it does',
        (tester) async {
      await tester.pumpWidget(_host(_bare));
      expect(find.widgetWithText(FilledButton, _add), findsOneWidget);
      final style = tester.widget<FilledButton>(find.byType(FilledButton)).style;
      expect(style?.shape?.resolve(<WidgetState>{}), isA<StadiumBorder>());

      await tester.pumpWidget(_host(_bare, isFavorite: true));
      expect(find.widgetWithText(FilledButton, _remove), findsOneWidget);
      expect(find.widgetWithText(FilledButton, _add), findsNothing);

      // Full width, measured on the button box: the artwork's primary action runs
      // the width of the content column.
      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
      expect(tester.getSize(find.byType(FilledButton)).width,
          closeTo(screenWidth - 2 * AppSpacing.m, 0.5));
    });
  });

  group('the brand rules', () {
    testWidgets('the accent is never body text', (tester) async {
      await tester.pumpWidget(_host(_rich, isFavorite: true));

      // `design_tokens.dart` permits `#F59E0B` for icons and fills only, because
      // its contrast against `#F8F7F5` is too low for something a user reads.
      // Checked over every `Text` on screen rather than over a handful, so
      // recolouring one role cannot slip past it.
      final amberTexts = find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.color == AppColors.accent,
        description: 'a Text painted in the accent',
      );
      expect(amberTexts, findsNothing);
    });

    testWidgets('every card is an AppSurface and nothing is a bare Card',
        (tester) async {
      await tester.pumpWidget(_host(_rich));

      expect(wordCard('serenity'), findsOneWidget);
      expect(wordCard(_synonymsHeading), findsOneWidget);
      expect(wordCard(_examplesHeading), findsOneWidget);
      // The other half of the same rule: a bare `Card` renders a hard black
      // keyline in this rasteriser, measured at 29,111 pixels once.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the dark theme reaches the dark tokens', (tester) async {
      await tester.pumpWidget(_host(_rich, brightness: Brightness.dark));

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, AppColors.backgroundDark);
      expect(bar.surfaceTintColor, Colors.transparent);
      // The headword's ink is the dark mode's, not the light mode's — a screen
      // that rendered light ink on a dark surface would pass every other
      // assertion here.
      expect(tester.widget<Text>(inWord('serenity')).style?.color,
          AppColors.textDark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the title is on the background, not on a raised surface',
        (tester) async {
      await tester.pumpWidget(_host(_bare));

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, AppColors.backgroundLight);
      expect(bar.surfaceTintColor, Colors.transparent);
      expect(inWord(_title), findsOneWidget);
    });
  });
}