import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/app.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/quiz_question.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/dictionary/attribution_screen.dart';
import 'package:lexilearn/ui/dictionary/dictionary_controller.dart';
import 'package:lexilearn/ui/dictionary/dictionary_word_screen.dart';
import 'package:lexilearn/ui/flashcards/flashcard_controller.dart';
import 'package:lexilearn/ui/flashcards/flashcards_screen.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_controller.dart';
import 'package:lexilearn/ui/quiz/quiz_result_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_setup_screen.dart';
import 'package:lexilearn/ui/settings/app_info_screen.dart';
import 'package:lexilearn/ui/wallpaper/nature_photo.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';

import '../data/dictionary/dictionary_test_env.dart';
import '../helpers/test_env.dart';

/// The one Home tile that pushes a route rather than selecting a bar
/// destination, and the label on it.
///
/// The tap is how this file reaches Stats: `showDialog`-free navigation aside,
/// the app's only entry to the screen is this tile, so a reference image
/// captured any other way would be a picture of something the user cannot get
/// to. See `lib/ui/home/home_screen.dart` → `_QuickLaunchGrid`.
const _statsTile = 'إحصائياتك';

/// The other tile that pushes rather than switching a tab. Favourites is not a
/// bottom-bar destination either, for the reason `home_shell.dart` documents.
///
/// `FavoritesScreen` itself is deliberately **not** imported here even though the
/// favourites shot below pushes it. Nothing in these images is asserted by type —
/// the shots are compared as pixels — and an unused import is an analyzer warning.
/// `test/ui/favorites_screen_test.dart` is where that screen is pinned.
const _favoritesTile = 'المفضلة';

/// The query that drives the search field, so the reference image shows a
/// **named** word rather than whichever one the calendar picked.
const _searchQuery = 'serenity';

/// `pumpShell` mounts `LexiLearnApp(repository:)` — the real app — so this file
/// does not import `app.dart` itself; it mounts through the shared helper like
/// every other screen test, for the same fake-async reason.

/// The pack the reference images are drawn from.
///
/// The artwork's own words, so the committed PNGs can be put next to
/// `docs/design/brand-reference.png` and compared without translating anything
/// first. Deterministic and in-memory — the golden depends on the entries, not on
/// whatever `assets/packs/` happens to hold.
///
/// **Task 14 added three fields to `serenity-1`, and they touch nothing already
/// captured.** The word detail screen is the first thing in the app to render a
/// part of speech, synonyms and examples, and a reference image that cannot show
/// its own optional sections is not one. The Home card draws only the term and
/// the phonetic, so `home_shell_user_shot.png` is unaffected by the data.
///
/// **Verified, and the first version of this comment was wrong about it.**
/// Regenerating the shell shot alongside the new four *did* rewrite the file —
/// 13,176 differing pixels, confined to logical `x 189–318, y 217–264`, which is
/// the card's term line. Cropping both showed the reason: the committed PNG reads
/// `fervour /fɜːvə/` and today's render reads `clarity /klærəti/`. That is
/// `WordOfTheDay.pick` moving with the calendar, which the shell shot's own
/// comment calls out as "the screen behaving correctly … not a reason to
/// regenerate" — so the file was restored with `git checkout` and left alone.
/// `stats_screen_user_shot_{light,dark}.png` came back byte-identical from the
/// same run, which is the part that says the three new fields really are inert
/// on Home: statistics reads no entry fields at all.
const _goldenPack = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(
      id: 'serenity-1',
      term: 'serenity',
      translations: <String>['الهدوء والسكينة', 'السكينة'],
      phonetic: '/səˈrenəti/',
      partOfSpeech: 'noun',
      synonyms: <String>['peace', 'tranquility'],
      examples: <String>['The room was filled with serenity.'],
    ),
    VocabEntry(
      id: 'ambition-1',
      term: 'ambition',
      translations: <String>['طموح'],
      phonetic: '/æmˈbɪʃən/',
    ),
    VocabEntry(
      id: 'fervour-1',
      term: 'fervour',
      translations: <String>['حماس'],
      phonetic: '/fɜːvə/',
    ),
    VocabEntry(
      id: 'clarity-1',
      term: 'clarity',
      translations: <String>['وضوح'],
      phonetic: '/klærəti/',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter test` ships the declared font files into the test asset bundle and
  // writes them into FontManifest.json, but it does not register them with the
  // text engine. Without this, every glyph rasterises as a tofu box and the
  // golden shows layout and colour but no type at all — which would make it
  // useless for judging the one thing this design system is really about.
  setUpAll(_loadBundledFonts);

  // Built here, not inside the test body: `TestHarness.create` awaits real
  // sqflite futures, and a `testWidgets` body runs in a fake-async zone where a
  // real future never completes on its own. The same one-line reason
  // `pumpShell` exists, and every other test file builds its harness in `setUp`.
  late TestHarness harness;

  setUp(() async =>
      harness = await TestHarness.create(packs: const <VocabPack>[_goldenPack]));

  tearDown(() => harness.dispose());

  testWidgets('home shell user shot', (tester) async {
    // The artwork's phone: 1080×2340 at 3×, which is 360×780 logical.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // The real app, not a stand-in. This file used to build a local preview
    // widget and carry a comment saying Task 9 would replace it — which never
    // happened, and left the reference image disagreeing with the navigation that
    // actually ships: `checklist_rtl_outlined` where the bar draws
    // `check_box_outlined`, `more_horiz_rounded` where it draws `apps`, and the
    // label `بطاقات` where it draws `البطاقات`. Every screen task was told to
    // copy this file, so a stale preview here was a stale preview everywhere.
    //
    // `pumpShell` waits for both start-up reads — the shell's, and the Home
    // screen's own, which cannot begin until the shell has resolved the pack key.
    await pumpShell(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_shell_user_shot.png'),
      // Golden pixels depend on the platform's font rasteriser. Windows uses
      // Segoe UI, Linux CI uses Roboto, so a byte-identical match across the two
      // is impossible by construction. Any screen task changing a colour,
      // spacing, or type size regenerates this on purpose with
      // `--update-goldens` and the reviewer judges the PNG by eye — and by the
      // pixel census in `docs/design/style-direction.md`, not by the thumbnail.
      //
      // That census is what caught the search field: this image once carried a
      // 1px `#6B7280` ring around the field where the brand specifies `#E5E7EB`,
      // because Material 3 paints a filled input's outline with
      // `colorScheme.onSurfaceVariant`. It looked like nothing in a thumbnail.
      //
      // The word of the day moves with the calendar, so this image legitimately
      // differs from yesterday's. That is the screen behaving correctly; it is
      // not a reason to regenerate.
      //
      // This `skip:` also means `--update-goldens` will NOT write the file. To
      // regenerate: comment this line out, run with `--update-goldens`, look at
      // the PNG, then put the line back.
      skip: 'platform-dependent; run locally with --update-goldens and inspect the PNG',
    );
  });

  // --- the statistics screen -----------------------------------------------------
  //
  // Two shots, light and dark, and both are here because the screen's dark mode
  // is a different set of brand tokens and not a filter over the light one: the
  // accuracy track, the three badge verdicts, the card hairlines and the reset
  // pill each name a different hex in `AppColors` per brightness. A single light
  // image would leave every one of those dark values unrendered and unreviewed.
  //
  // Reached through the Home tile rather than by mounting `StatsScreen` in a
  // stand-in app, for the reason in [_statsTile].
  testWidgets('stats screen user shot, light', (tester) async {
    // The artwork's phone: 1080×2340 at 3×, which is 360×780 logical — the same
    // size the shell shot uses, and the reason `useAPhone` exists.
    useAPhone(tester);
    await _seedStats(tester, harness.repository);
    await _openStats(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stats_screen_user_shot_light.png'),
      skip: _goldenSkipReason,
    );
  });

  testWidgets('stats screen user shot, dark', (tester) async {
    useAPhone(tester);
    // `LexiLearnApp` leaves `themeMode` at its default, so the theme follows the
    // platform brightness. Overriding the dispatcher is how the app itself would
    // see a dark device — a stand-in app with `themeMode: ThemeMode.dark` would
    // be a different app, not a different phone.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _seedStats(tester, harness.repository);
    await _openStats(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stats_screen_user_shot_dark.png'),
      skip: _goldenSkipReason,
    );
  });

  // --- favourites and the word detail ------------------------------------------
  //
  // Four images, and both screens get a light and a dark one for the reason the
  // statistics shots do: each names a different set of brand tokens per
  // brightness — the card hairlines, the neutral surface, the text ink and the
  // amber heart — so a single image would leave half of them unrendered.
  //
  // Both are **pushed routes reached through the real app**, not mounted in a
  // stand-in, for the reason `[_statsTile]` gives: a reference image captured any
  // other way would be a picture of something the user cannot get to.
  testWidgets('favorites screen user shot, light', (tester) async {
    useAPhone(tester);
    await _seedFavorites(tester, harness.repository);
    await _openFavorites(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/favorites_screen_user_shot_light.png'),
      skip: _goldenSkipReason,
    );
  });

  testWidgets('favorites screen user shot, dark', (tester) async {
    useAPhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _seedFavorites(tester, harness.repository);
    await _openFavorites(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/favorites_screen_user_shot_dark.png'),
      skip: _goldenSkipReason,
    );
  });

  testWidgets('word detail user shot, light', (tester) async {
    useAPhone(tester);
    await _openWordDetail(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/word_detail_user_shot_light.png'),
      skip: _goldenSkipReason,
    );
  });

  testWidgets('word detail user shot, dark', (tester) async {
    useAPhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _openWordDetail(tester, harness.repository);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/word_detail_user_shot_dark.png'),
      skip: _goldenSkipReason,
    );
  });

  // --- the flashcard deck -------------------------------------------------------
  //
  // Two images, and **both are seeded**, which is the difference from every shot
  // above it and the reason this pair is worth having at all.
  //
  // The deck is dealt unseeded on the app's path, and it must be — a fixed seed
  // inside `FlashcardsScreen` would give every user the identical deck, which is
  // the opposite of what a vocabulary app is for. But the light and the dark shot
  // are **separate runs with separate harnesses**, so unseeded they would show
  // *different words*, and a reviewer comparing them to check the one thing this
  // screen's artwork actually specifies — `أعرف` purple in light, **amber in
  // dark** (`docs/design/brand-reference.md` §4ج) — would be comparing two
  // screens rather than two modes. So the controller is handed in already dealt,
  // which `FlashcardsScreen` reads exactly the way `StatsScreen` reads an optional
  // `StatsController`.
  //
  // The state captured is the artwork's own frame: the counter at `3/10`, the
  // term `serenity` with its pronunciation, the meaning shown, and all three
  // controls present — which is what `brand-reference.png` draws on both phones.
  testWidgets('flashcards screen user shot, light', (tester) async {
    useAPhone(tester);
    await _openDeck(tester, wallpaperSeed: _wallpaperSeed);
    expect(_panelPhoto(tester), _expectedPhoto(Brightness.light));
    await _letThePhotographLoad(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/flashcards_screen_user_shot_light.png'),
      skip: _goldenSkipReason,
    );
  });

  testWidgets('flashcards screen user shot, dark', (tester) async {
    useAPhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _openDeck(tester, wallpaperSeed: _wallpaperSeed);
    expect(_panelPhoto(tester), _expectedPhoto(Brightness.dark));
    await _letThePhotographLoad(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/flashcards_screen_user_shot_dark.png'),
      skip: _goldenSkipReason,
    );
  });

  // --- the screens that had no reference image at all ----------------------------
  //
  // **This group exists because of what a missing golden costs, and that was
  // measured rather than argued.** The quiz shipped a defect that survived fifteen
  // review-clean tasks, 415 tests and nine images, and it was caught by a person
  // running the app on a real phone — because `tool/golden_census.ps1` reads the
  // images *this file* writes, and this file never mentioned the quiz. A screen
  // the census does not read is a screen nothing checks.
  //
  // The audit found four such screens: `MoreScreen`, `QuizSetupScreen` and
  // `QuizResultScreen` had **no** image in either mode, and `HomeScreen` had no
  // image of its own — only the shell's, which happens to show it in light. Ten
  // images here, five screens × two modes, plus `AppInfoScreen`, the screen this
  // round added.
  //
  // **Every one is reached through the real app**, by tapping the bar or the
  // menu, for the reason `[_statsTile]` gives: a reference image captured any
  // other way would be a picture of something the user cannot get to.
  for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('home screen user shot, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);
      await pumpShell(
        tester,
        harness.repository,
        wallpaperSeed: _wallpaperSeed,
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      // **The photograph is pinned, not merely asserted to be one of the set.**
      // Without the seed above, every regeneration would photograph a different
      // file and the reference image would be stale for no reason - the same
      // objection this file records about the word of the day moving with the
      // calendar.
      expect(
        _panelPhoto(tester),
        _expectedPhoto(brightness),
        reason: 'the seeded rotation must be the one this image was taken with',
      );
      await _letThePhotographLoad(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_screen_user_shot_$mode.png'),
        skip: _goldenSkipReason,
        );
    });

    testWidgets('more screen user shot, $mode', (tester) async {
      // **The screen this round most needed one.** `MoreScreen` is a bar
      // destination with `isDark ? … : …` throughout — the same shape of code
      // that hid the quiz's dark-mode defect — and it is the app's settings
      // surface, where a colour regression is least likely to be noticed by
      // looking at it.
      useAPhone(tester);
      await _setMode(tester, brightness);
      await _openBarDestination(tester, harness.repository, Icons.apps);
      expect(find.byType(MoreScreen), findsOneWidget);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more_screen_user_shot_$mode.png'),
        skip: _goldenSkipReason,
        );
    });

    testWidgets('quiz setup screen user shot, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);
      await _openBarDestination(
          tester, harness.repository, Icons.check_box_outlined);
      expect(find.byType(QuizSetupScreen), findsOneWidget);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/quiz_setup_screen_user_shot_$mode.png'),
        skip: _goldenSkipReason,
        );
    });

    testWidgets('quiz result screen user shot, $mode', (tester) async {
      // Reached by *finishing* a two-question quiz rather than by mounting
      // `QuizResultScreen` on its own, so the reference image is the state a user
      // actually lands in. The deal is seeded and the score asserted, because an
      // image reading "0 / 2" would still look plausible.
      useAPhone(tester);
      await _setMode(tester, brightness);
      await _openQuiz(tester, harness.repository);
      // **Answer *and advance*, twice, both correctly.**
      //
      // Two traps this shot fell into, both measured:
      //
      // * Answering twice **without advancing in between** silently grades
      //   question 1 twice — `_answerQuiz` taps an option, an answered option is
      //   inert (`onTap: answered ? null : ...`), and `controller.question` is
      //   still question 1. The result screen would never have appeared, and the
      //   reference image would have been an image of nothing.
      // * Reusing `_answerQuiz` for the **second** question fails, because it
      //   asserts the advance button reads `التالي` — and after the first
      //   `next()`, `_questionNumber` has reached `_questionCount`, so it reads
      //   `إنهاء`. Its answer is copied inline here rather than changing a helper
      //   three committed reference images depend on.
      for (var i = 0; i < 2; i++) {
        final controller = _controllerOf(tester);
        final question = controller.question!;
        await tester.tap(find.text(question.options[question.correctIndex].text));
        await settleDatabase(tester);
        // The 150ms cross-fade, for the reason `_answerQuiz` gives: a photograph
        // taken mid-fade is of a colour the app does not settle on.
        await tester.pump(AppDurations.fast);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(
          FilledButton,
          controller.isLastQuestion ? _finishQuiz : _advanceQuiz,
        ));
        await settleDatabase(tester);
      }

      // **The score is asserted, not photographed.** A reference image reading
      // `0 / 2` would look exactly as plausible as one reading `2 / 2`, and the
      // census cannot tell them apart — it reads colours, not glyphs.
      expect(_controllerOf(tester).correctCount, 2,
          reason: 'both answers were correct, so the image shows 2 / 2');
      expect(find.byType(QuizResultScreen), findsOneWidget);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/quiz_result_screen_user_shot_$mode.png'),
        skip: _goldenSkipReason,
        );
    });

    testWidgets('app info screen user shot, $mode', (tester) async {
      // The screen this round added, given the same treatment from birth rather
      // than from the next task that notices it is missing.
      useAPhone(tester);
      await _setMode(tester, brightness);
      await pumpShell(tester, harness.repository);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_appInfoMenuLabel));
      await tester.pumpAndSettle();

      expect(find.byType(AppInfoScreen), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_info_screen_user_shot_$mode.png'),
        skip: _goldenSkipReason,
        );
    });
  }

  // --- the dictionary ------------------------------------------------------------
  //
  // **Six images, and they are the screens this round added.** The
  // dictionary's own search results, its word screen and its attribution
  // screen, each in both modes, because each of them names a different set of
  // brand tokens per brightness and because a screen the census does not read
  // is a screen nothing checks.
  //
  // **Their own harness, and the reason is the same as `_openDeck`'s.** The
  // shared harness has no dictionary, so the shell would resolve the starter
  // pack and the search field would search the wrong thing. The dictionary
  // harness attaches the shipped artefact's engine to its repository, and the
  // shell then resolves the **dictionary** as the active pack — which is the
  // default in the shipping app, and is what these images are of.
  for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('dictionary search user shot, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);
      await _openDictionary(tester);
      await _typeDictionaryQuery(tester);
      // **The result is asserted, not photographed.** A reference image that
      // showed an empty search would look exactly as plausible as one that
      // showed a word.
      expect(find.text(_dictionaryQuery), findsWidgets);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/dictionary_search_user_shot_$mode.png'),
        skip: _goldenSkipReason,
      );
    });

    testWidgets('dictionary word user shot, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);
      await _openDictionary(tester);
      await _openDictionaryWord(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/dictionary_word_user_shot_$mode.png'),
        skip: _goldenSkipReason,
      );
    });

    testWidgets('attribution screen user shot, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);
      await _openDictionary(tester);
      await _openAttribution(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attribution_screen_user_shot_$mode.png'),
        skip: _goldenSkipReason,
      );
    });
  }

  // --- the quiz ----------------------------------------------------------------
  //
  // **Six images, and this pair of screens is the reason the whole file has a
  // lesson attached to it.** The quiz shipped a defect that fifteen review-clean
  // tasks, 415 tests and nine goldens did not catch, because there was **no quiz
  // golden**: `tool/golden_census.ps1` reads the images this file writes, so a
  // screen it never mentions is a screen nothing checks. It was found by running
  // the app on a real phone that happened to be in dark mode, where the quiz
  // painted `#16A34A` and `#DC2626` — the *light* verdict tokens — because four
  // call sites named them without reading the theme, two of them `const` Icons
  // that therefore could not read it at all.
  //
  // So: **three states in both modes**, not one. A single image per mode would
  // have photographed the unanswered question, where the defect does not exist.
  //
  // | state | what it proves about a reviewer looking at the PNG |
  // |---|---|
  // | unanswered | four neutral rows, no verdict colour anywhere |
  // | answered correctly | the right row is **filled green** with a tick, not a green border on a purple field |
  // | answered wrongly | the picked row is filled red, the right one is filled green, both with a glyph |
  //
  // The answered states are the only ones that can regress, and they are in both
  // modes because every verdict colour is mode-aware now.
  for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('quiz screen user shot, unanswered, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);

      await _openQuiz(tester, harness.repository);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/quiz_screen_unanswered_user_shot_$mode.png'),
        skip: _goldenSkipReason,
      );
    });

    testWidgets('quiz screen user shot, answered correctly, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);

      final question = await _openQuiz(tester, harness.repository);
      await _answerQuiz(tester, question, question.correctIndex);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/quiz_screen_correct_user_shot_$mode.png'),
        skip: _goldenSkipReason,
      );
    });

    testWidgets('quiz screen user shot, answered wrongly, $mode', (tester) async {
      useAPhone(tester);
      await _setMode(tester, brightness);

      final question = await _openQuiz(tester, harness.repository);
      await _answerQuiz(tester, question, _firstWrongIndex(question));

      // Both verdicts have to be on screen at once here, which is the state the
      // user photographed: a wrong pick, the right answer revealed beside it.
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/quiz_screen_wrong_user_shot_$mode.png'),
        skip: _goldenSkipReason,
      );
    });
  }
}

/// The overflow menu's app-info entry, as `app_overflow_menu.dart` spells it.
const String _appInfoMenuLabel = 'معلومات التطبيق';

/// The overflow menu's attribution entry, as `app_overflow_menu.dart` spells
/// it.
///
/// **النسب**, and the wording is the ruling's: the row names the licences and
/// the credits, and the screen it opens is titled «المصادر والنسب».
const String _attributionMenuLabel = 'النسب';

/// The query the dictionary search is driven with, so the reference image
/// shows a **named** word rather than whichever one the dictionary offered.
const String _dictionaryQuery = 'child';

/// The dictionary's own harness: the shipped artefact, opened, with its
/// engine attached to the repository.
///
/// **Its own harness, and the reason is the same as `_openDeck`'s.** The
/// shared harness has no dictionary, so the shell resolves the starter pack
/// and every destination is scoped to it. Attaching the dictionary's engine
/// makes `packs()` answer with the dictionary first, which makes the
/// dictionary the active pack — which is the default in the shipping app and
/// is what these images are of.
class _DictionaryHarness {
  _DictionaryHarness(this.harness, this.controller, this.entry);

  final TestHarness harness;
  final DictionaryController controller;
  final DictionaryEntry entry;
}

/// Opens the shipped dictionary and mounts the app on it.
Future<_DictionaryHarness> _openDictionary(WidgetTester tester) async {
  // **Every real read in here goes through `runAsync`.** A `testWidgets` body
  // runs in a fake-async zone, and a real sqflite future never completes
  // there — the failure mode is a ten-minute hang with no message naming the
  // cause (`docs/engineering-standards.md` §5).
  final fixture = await tester.runAsync(DictionaryFixture.open);
  addTearDown(fixture!.close);

  final dictionaryHarness = await tester.runAsync(
    () => TestHarness.create(packs: const <VocabPack>[_goldenPack]),
  );
  addTearDown(dictionaryHarness!.dispose);

  // **The engine is attached to the repository**, so the shell's own start-up
  // read resolves the dictionary as the active pack. Nothing about the
  // dictionary is hard-coded into the shell.
  dictionaryHarness.repository.attachDictionary(fixture.engine);

  final controller = DictionaryController.ready(fixture.engine);
  addTearDown(controller.dispose);
  // **The attribution is read here, outside the fake-async zone.** The menu
  // awaits it, and a real sqflite future never completes inside a
  // `testWidgets` body — so the read is done here and the menu's await
  // answers at once.
  await tester.runAsync(controller.attribution);

  await pumpShell(
    tester,
    dictionaryHarness.repository,
    wallpaperSeed: _wallpaperSeed,
    dictionary: controller,
  );

  final entry = (await tester.runAsync(
    () => fixture.store.entryByNorm(_dictionaryQuery),
  ))!;
  return _DictionaryHarness(dictionaryHarness, controller, entry);
}

/// Types the dictionary's query into Home's search field.
///
/// **The dictionary's own settle, and the reason it is needed.** The shared
/// `settleDatabase` counts the **app** database's operations; a dictionary
/// read is on another file and is not one of them, so the shared settle can
/// return while the dictionary is still answering — and the reference image
/// would photograph the word «جارٍ البحث…» instead of a result. This gives
/// the reply a real turn and pumps until the results are there, which is the
/// same dance the shared helper performs for the app database.
Future<void> _typeDictionaryQuery(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), _dictionaryQuery);
  await tester.pump(AppDurations.standard);
  for (var round = 0; round < 50; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.text(_dictionaryQuery).evaluate().length > 1) return;
  }
  fail('the dictionary search for "$_dictionaryQuery" never answered');
}

/// Opens the dictionary's word screen for the entry the search found.
Future<void> _openDictionaryWord(WidgetTester tester) async {
  await _typeDictionaryQuery(tester);
  final row = find.descendant(
    of: find.byType(ListView),
    matching: find.text(_dictionaryQuery),
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
  await settleDatabase(tester);
  expect(find.byType(DictionaryWordScreen), findsOneWidget,
      reason: 'the result row opens the dictionary word screen');
}

/// Opens the attribution screen through the overflow menu.
Future<void> _openAttribution(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_attributionMenuLabel));
  await tester.pumpAndSettle();
  await settleDatabase(tester);
  expect(find.byType(AttributionScreen), findsOneWidget,
      reason: 'the menu opens the dictionary attribution screen');
}

/// The quiz's advance button, as `quiz_screen.dart` spells it, on every question
/// but the last.
const String _advanceQuiz = 'التالي';

/// The advance button on the last question, which is a different word.
///
/// `QuizController.isLastQuestion` is `_questionNumber >= _questionCount`, and
/// `_questionNumber` advances in `next()` — so the counter reaches the question
/// count exactly when the *next* question is dealt, not when the current one is
/// answered. Measured: a shot that assumed `التالي` throughout found **no**
/// matching widget on the second question.
const String _finishQuiz = 'إنهاء';

/// Taps a bottom-bar destination by its icon and lets its own reads land.
///
/// Shared by every destination shot, because three copies of the same two waits
/// is how one of them ends up with the previous one's read count. Each
/// destination issues a read from `initState`, so `pumpShell`'s two turns
/// happened before it existed.
Future<void> _openBarDestination(
  WidgetTester tester,
  VocabRepository repository,
  IconData icon,
) async {
  await pumpShell(tester, repository);
  await tester.tap(find.byIcon(icon));
  await tester.pumpAndSettle();
  await settleDatabase(tester);
  await settleDatabase(tester);
}

/// The controller behind the quiz currently on screen.
///
/// Read from the tree rather than captured from [_openQuiz], because the result
/// shot drives the quiz it finds rather than the one that helper built.
QuizController _controllerOf(WidgetTester tester) =>
    Provider.of<QuizController>(tester.element(find.byType(QuizScreen)),
        listen: false);

/// Puts the phone in [brightness] the way the app itself would see it.
///
/// Overriding the dispatcher rather than mounting `themeMode: ThemeMode.dark`,
/// for the reason the statistics dark shot gives: `LexiLearnApp` leaves
/// `themeMode` at its default, so a stand-in with a forced mode would be a
/// different app rather than a different phone. Shared by the six quiz shots
/// rather than copied into each — the same reason `pumpShell` and
/// `useAPhone` are shared.
Future<void> _setMode(WidgetTester tester, Brightness brightness) async {
  if (brightness == Brightness.light) return;
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Opens the quiz over the real shell, with a **seeded** controller.
///
/// **Why this pushes the route rather than driving the setup screen, and what
/// that costs.** `QuizSetupScreen._start` builds its own `QuizController` with no
/// `random:` (quiz_setup_screen.dart:133-137), so a quiz reached through the app
/// deals a *different question every run* — and `_goldenPack` has four entries,
/// so both the answer and the option order would move. A reference image that
/// reads a different word on every regeneration is a reference nobody can compare
/// against, which is the same objection `[_openWordDetail]` records about the
/// word-of-the-day card.
///
/// So the controller is handed in already dealt, exactly as `_openDeck` does for
/// the flashcard deck, and the deal is **asserted** afterwards (term, option
/// count, correct index) so a seed that stopped producing this question fails
/// loudly instead of quietly photographing a different one. The screen, the
/// shell, the bar, the theme and the route are the real ones; only the
/// construction of the route is the test's, and it is the same trade `_openDeck`
/// already makes and documents.
///
/// Returns the question it dealt, so each caller can answer it by index.
Future<QuizQuestion> _openQuiz(
  WidgetTester tester,
  VocabRepository repository,
) async {
  final controller = QuizController(
    repository: repository,
    packKey: _goldenPack.packId,
    questionCount: _quizQuestionCount,
    random: Random(_quizSeed),
  );
  addTearDown(controller.dispose);

  // `runAsync` because `start()` is a real SQLite read, and a `testWidgets` body
  // runs in a fake-async zone where a real future never answers — the same
  // one-line reason the harness is built in `setUp`. Awaited here rather than
  // fired and delayed, because the deal has to be known before the tree is
  // mounted for the assertions below to mean anything.
  await tester.runAsync(controller.start);

  final question = controller.question!;
  expect(question.answer.term, 'serenity',
      reason: 'seed $_quizSeed asks serenity-1 first off [_goldenPack]');
  expect(question.options, hasLength(4));

  await pumpShell(tester, repository);
  Navigator.of(tester.element(find.byType(HomeScreen))).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<QuizController>.value(
        value: controller,
        child: const QuizScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await settleDatabase(tester);

  // Asserting the tree rather than trusting the push: a screen that never arrived
  // would photograph the shell, and the census cannot tell — it reads colours,
  // not identity. `docs/engineering-standards.md` §6.
  expect(find.byType(QuizScreen), findsOneWidget);
  return question;
}

/// The index of an option that is not the answer.
///
/// By identity, from `QuizQuestion.isCorrect`, for the reason
/// `test/ui/quiz_screen_test.dart` gives for its own copy: a helper that compared
/// option *text* would agree with a grader that compares text.
int _firstWrongIndex(QuizQuestion question) {
  for (var i = 0; i < question.options.length; i++) {
    if (!question.isCorrect(i)) return i;
  }
  throw StateError('the generated question had no wrong option');
}

/// Taps the option at [index] and lets the verdict render.
///
/// `settleDatabase` rather than a bare `pump`: the tap's `onTap` discards the
/// `answer()` future, and the repository write behind it has to land on the real
/// loop before the next test tears the harness down. It is the same shape as
/// `test/ui/quiz_screen_test.dart`'s `_tap`, and it is **not** copied from there:
/// this file's version additionally settles the 150ms `AnimatedContainer` cross-
/// fade, because a photograph taken mid-fade would be of a colour the app does
/// not settle on.
Future<void> _answerQuiz(
  WidgetTester tester,
  QuizQuestion question,
  int index,
) async {
  await tester.tap(find.text(question.options[index].text));
  await settleDatabase(tester);
  await tester.pump(AppDurations.fast);
  await tester.pumpAndSettle();
  expect(find.text('التالي'), findsOneWidget,
      reason: 'the answer is committed, so the screen has moved on');
}

/// The seed that deals `serenity-1` first off [_goldenPack].
///
/// One constant for all six shots so the light and the dark images are the same
/// screen in two modes and not two different screens. **Verified by the
/// assertion inside [_openQuiz]**, not trusted: a generator change that moved
/// this would fail that test rather than quietly redrawing six reference images.
const int _quizSeed = 7;

/// Long enough for the "answered wrongly" state to be reachable in one screenful
/// and short enough that the second question is never asked for a reference image.
const int _quizQuestionCount = 2;

/// Why every golden in this file is `skip:`-ed, and how to regenerate one.
///
/// The full explanation is on the shell shot above; this is the short form so
/// each of the three does not repeat six lines of it. **A `skip:` also stops
/// `--update-goldens` from writing**, so regenerating means commenting the
/// `skip:` out, running with `--update-goldens`, looking at the PNG, then putting
/// the line back.
const String _goldenSkipReason =
    'platform-dependent; run locally with --update-goldens and inspect the PNG';

/// Seeds enough history for the statistics screen to have something to draw.
///
/// Ten answers and three sessions, chosen so the shot shows all three score
/// verdicts the screen can render and a non-trivial ring:
/// `serenity-1` 5 right (past the mastery floor), `ambition-1` 3 right and 1
/// wrong, `fervour-1` 1 wrong — **8 of 10, so 80%**, which is what the accuracy
/// ring will read. The three sessions are 4/4, 4/0 and 4/2, so the reference
/// image carries a success ring, an error ring and a hairline one together.
///
/// The writes go through `tester.runAsync` because a `testWidgets` body runs in
/// a fake-async zone where a real sqflite future never answers on its own — the
/// same one-line reason the harness is built in `setUp` and `pumpShell` exists.
///
/// **These timestamps render in local time, so the reference images are
/// machine-specific.** `DateTime.utc(2026, 10, 14, 12)` is `12:00` on a UTC box
/// and `15:00` on the one that generated the committed PNGs. Regenerating
/// anywhere else therefore produces a different image with nothing wrong with
/// it, and the pixel census is unaffected — it counts colours, not glyphs.
Future<void> _seedStats(WidgetTester tester, VocabRepository repository) async {
  await tester.runAsync(() async {
    Future<void> answer(
      String entryId, {
      int right = 0,
      int wrong = 0,
    }) async {
      for (var i = 0; i < right; i++) {
        await repository
            .recordAnswer(packKey: 'en_ar', entryId: entryId, wasCorrect: true);
      }
      for (var i = 0; i < wrong; i++) {
        await repository
            .recordAnswer(packKey: 'en_ar', entryId: entryId, wasCorrect: false);
      }
    }

    await answer('serenity-1', right: 5);
    await answer('ambition-1', right: 3, wrong: 1);
    await answer('fervour-1', wrong: 1);

    Future<void> session(int day, int correct) => repository.finishSession(
          packKey: 'en_ar',
          startedAt: DateTime.utc(2026, 10, day, 12),
          totalQuestions: 4,
          correctCount: correct,
        );
    await session(14, 4);
    await session(13, 0);
    await session(12, 2);
  });
}

/// Taps the `إحصائياتك` tile and lets the screen it pushes finish reading.
///
/// `useAPhone` first, from the caller: on the default 800×600 the tile is in the
/// grid's second row and `tap` throws on it.
Future<void> _openStats(WidgetTester tester, VocabRepository repository) async {
  await pumpShell(tester, repository);
  await tester.tap(
    find.descendant(of: find.byType(HomeScreen), matching: find.text(_statsTile)),
  );
  await tester.pumpAndSettle();
  // The pushed screen issues its own read from `initState`, and `pumpShell`'s
  // two turns happened before it existed.
  await settleDatabase(tester);
}

/// Saves two words, so the favourites screen has a list rather than an empty
/// state to photograph.
///
/// `tester.runAsync`, not a bare `await`: a `testWidgets` body runs in a
/// fake-async zone where a real sqflite future never answers. The write is
/// awaited inside `runAsync` rather than fired and delayed the way
/// `commitAndSettle` does, because the tree is mounted but the screen has not
/// been pushed yet and there is nothing for pumps to be useful to.
Future<void> _seedFavorites(
  WidgetTester tester,
  VocabRepository repository,
) =>
    tester.runAsync(() async {
      await repository.setFavorite(
          packKey: 'en_ar', entryId: 'serenity-1', isFavorite: true);
      await repository.setFavorite(
          packKey: 'en_ar', entryId: 'ambition-1', isFavorite: true);
    });

/// Taps the `المفضلة` tile and lets the screen it pushes finish reading.
///
/// `useAPhone` first, from the caller, for the same reason as `_openStats`.
Future<void> _openFavorites(
  WidgetTester tester,
  VocabRepository repository,
) async {
  await pumpShell(tester, repository);
  await tester.tap(
    find.descendant(
      of: find.byType(HomeScreen),
      matching: find.text(_favoritesTile),
    ),
  );
  await tester.pumpAndSettle();
  await settleDatabase(tester);
}

/// Searches for one word and taps its result, so the reference image shows a
/// **named** word.
///
/// **Not the word-of-the-day card**, and that is the point. The card shows
/// whichever entry `WordOfTheDay.pick` lands on for today's date, so a golden
/// captured through it changes with the calendar — the shell shot documents that
/// and accepts it, because the card is *about* the calendar. The word detail
/// screen is not, and a reference image that reads `ambition` on one day and
/// `serenity` on the next is a reference nobody can compare against. The search
/// row is the app's other real door into a word: `_EntryRow` → `onOpenWord` →
/// `HomeShell._openWordDetail`.
///
/// **The wait after the debounce is `realTurnThenSettle`, not `settleDatabase`**,
/// because Home's results list sits behind an indeterminate spinner; the
/// measurement is on that helper. This file used to carry a private copy of it,
/// and it was the *second* copy — `home_screen_test.dart`'s `_search` did the
/// same two lines in the same order without knowing. Moved to
/// `test/helpers/test_env.dart` in Task 14's fix round.
Future<void> _openWordDetail(
  WidgetTester tester,
  VocabRepository repository,
) async {
  await pumpShell(tester, repository);

  await tester.enterText(find.byType(TextField), _searchQuery);
  // `HomeScreen`'s debounce is `AppDurations.standard`, 250 ms — the same
  // constant the implementation reads, so this is not a magic sleep.
  await tester.pump(AppDurations.standard);
  // The search is a database query of its own, issued once the debounce fires,
  // and it sits behind that spinner. See `realTurnThenSettle` in
  // `test/helpers/test_env.dart` — **not a symbol in this file**, which is what
  // this comment used to point at, after that copy was deleted in the fix round.
  await realTurnThenSettle(tester);

  // Scoped to the results list, **not** a bare `find.text`. Measured: a bare one
  // matches twice — the `EditableText` in the search field now holds the same
  // string, because the test typed it — and `tap` rejects an ambiguous target.
  await tester.tap(find.descendant(
    of: find.byType(ListView),
    matching: find.text(_searchQuery),
  ));
  await tester.pumpAndSettle();
  // The pushed route issues its own read from `initState`, and it draws no
  // spinner, so [settleDatabase] is the right helper here.
  await settleDatabase(tester);

  expect(find.byType(WordDetailScreen), findsOneWidget,
      reason: 'the result row opens the word detail route');
}

/// Registers both bundled families with the test text engine.
Future<void> _loadBundledFonts() async {
  const families = <String, List<String>>{
    'Tajawal': <String>[
      'assets/fonts/Tajawal-Regular.ttf',
      'assets/fonts/Tajawal-Medium.ttf',
      'assets/fonts/Tajawal-Bold.ttf',
    ],
    'Inter': <String>[
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
    ],
    // Icons come from the same asset bundle, so they need the same treatment or
    // every glyph in the reference image is a square.
    'MaterialIcons': <String>['fonts/MaterialIcons-Regular.otf'],
  };
  for (final family in families.entries) {
    final loader = FontLoader(family.key);
    for (final asset in family.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

/// Opens the flashcard deck through the real app, at the artwork's own state.
///
/// **Why this is not [pumpShell].** `pumpShell` mounts
/// `LexiLearnApp(repository:)` and nothing else, and the only way to hand the
/// screen a *dealt* controller is to provide one above the app — so the mount
/// differs and the helper cannot be called verbatim. It is still the same
/// screen through the same shell and the same bar; only the mount is wider.
///
/// **No copy of the fake-async dance.** Every *wait* below is the shared
/// [settleDatabase] helper, which is the primitive
/// `docs/engineering-standards.md` §5 sanctions. This file has exactly two
/// `tester.runAsync` calls, both of them the `runAsync`-to-*seed* pattern
/// `more_screen_test.dart` already documents — one opening this shot's own
/// harness, one dealing and advancing the deck — and both **await** rather than
/// fire-and-delay, because there is no tree mounted yet for pumps to be useful
/// to. That is the opposite situation from a wait, and it is the reason
/// `commitAndSettle` is the wrong helper here.
///
/// The waits, in order, and why each exists:
/// * two [settleDatabase] for the shell's start-up read and Home's, which cannot
///   begin until the shell has resolved the pack key — the same two reads
///   [pumpShell] serves;
/// * the bar tap, which is a rebuild;
/// * **three** [settleDatabase] for the deck, whose own single read is issued
///   from `initState`: `FlashcardsScreen` reads the pack once and hands the words
///   to `FlashcardController.start`, so this was **two** sequential round trips
///   until Task 15's fix round. See `FlashcardController.entries` — the reason it
///   matters is `home_screen_test.dart`, whose only bar-destination tap mounts
///   this screen and which cannot finish while a read is still in flight.
Future<void> _openDeck(WidgetTester tester, {int? wallpaperSeed}) async {
  // **Its own harness, not the shared one.** `HomeShell` resolves its active pack
  // from `PackDao.listPacks()`, which orders by `is_bundled DESC, imported_at
  // DESC`; this project's clock is pinned, so every pack in one harness shares one
  // `imported_at` and "first" is whichever SQLite happens to return. Installing
  // [_flashcardPack] into the shared harness would make the active pack a coin
  // toss for the **six shots already committed from it**, which read
  // `_activePackKey` off the shell. A harness of its own removes the tie.
  //
  // `runAsync` because `TestHarness.create` opens a real database, and a
  // `testWidgets` body runs in a fake-async zone where a real future never
  // answers — the same one-line reason the shared harness is built in `setUp`.
  final deckHarness = await tester.runAsync(
    () => TestHarness.create(packs: const <VocabPack>[_flashcardPack]),
  );
  addTearDown(deckHarness!.dispose);
  final repository = deckHarness.repository;

  final controller = FlashcardController(
    repository: repository,
    packKey: _flashcardPack.packId,
    // Ten, so the counter reads the artwork's `3/10` denominator rather than the
    // fixture's four words.
    cardCount: 10,
    random: Random(_flashcardSeed),
  );
  addTearDown(controller.dispose);

  // The deck is dealt and advanced **before** the tree is mounted, so each of
  // these real sqflite futures can be awaited rather than fired-and-delayed.
  // Asserted afterwards, because a silently different deal would photograph the
  // wrong card and the reference image would still look plausible.
  await tester.runAsync(() async {
    await controller.start();
    await controller.answer(knewIt: true);
    await controller.answer(knewIt: false);
    await controller.reveal();
  });
  expect(controller.index, 2, reason: 'the counter must read 3/10');
  expect(controller.total, 10);
  expect(controller.revealed, isTrue, reason: 'the artwork shows the meaning');
  expect(controller.current?.term, 'serenity',
      reason: 'seed $_flashcardSeed deals serenity-1 third off '
          '[_flashcardPack]');

  await tester.pumpWidget(
    ChangeNotifierProvider<FlashcardController>.value(
      value: controller,
      child: LexiLearnApp(
        repository: repository,
        wallpaperSeed: wallpaperSeed,
      ),
    ),
  );
  await settleDatabase(tester); // the shell's own start-up read
  await settleDatabase(tester); // Home's read, issued by the rebuild above

  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(_flashcardsBarLabel),
    ),
  );
  await tester.pumpAndSettle();
  for (var turn = 0; turn < 3; turn++) {
    await settleDatabase(tester);
  }

  // Asserting the tree rather than trusting the exit code: a deck that never
  // arrived would photograph `HomeScreen` and the census could not tell — it is
  // a pixel census, not an identity oracle. `docs/engineering-standards.md` §6.
  expect(find.byType(FlashcardsScreen), findsOneWidget);
  expect(find.text('3/10'), findsOneWidget);
}

/// The bottom bar's label for this destination, as `home_shell.dart` spells it.
const String _flashcardsBarLabel = 'البطاقات';

/// The seed that deals `serenity-1` **third** off [_flashcardPack].
///
/// Measured, not guessed: 60 seeds were run against this exact entry order and
/// the third card's id printed for each. Twelve of them reach `serenity-1` on
/// the third draw (12, 41, 51, 58 among them) and 12 is the first.
const int _flashcardSeed = 12;

/// **The seed that fixes which photograph each reference image shows.**
///
/// **The same number for both surfaces and both modes.** A different seed per
/// shot would photograph four unrelated pictures, and the point of a light and a
/// dark image of one screen is that they are *the same screen in two modes* -
/// which is the whole reason the deck's controller is seeded at all, recorded
/// above [_openDeck]. Pinning the photograph is the same requirement for the
/// same reason: without it, every `--update-goldens` run produces an image
/// nobody can compare against the last one.
///
/// It is **asserted**, not merely used: each shot reads the photograph off the
/// rendered tree and compares it with [_expectedPhoto], which re-derives the
/// index from the same seed against the catalog. A seed that stopped producing
/// this photograph fails loudly instead of quietly redrawing the images.
const int _wallpaperSeed = 3;

/// The photograph [_wallpaperSeed] produces in [brightness]'s set.
///
/// **Derived, not written down**, for the same reason the deck's term is
/// asserted instead of merely photographed: a hard-coded path here would be a
/// second place to update when a photograph is added or renamed.
String _expectedPhoto(Brightness brightness) {
  final set = Wallpapers.forBrightness(brightness);
  return set[Random(_wallpaperSeed).nextInt(set.length)];
}

/// The photograph the panel under test is actually showing.
String _panelPhoto(WidgetTester tester) =>
    tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;

/// Gives the photograph a **real** turn of the event loop, so the reference
/// image shows the picture rather than the surface fill behind it.
///
/// **This is not a workaround; it is the same reason `pumpShell` exists.**
/// `Image.asset` resolves through `rootBundle`, whose future never completes
/// inside a `testWidgets` fake-async zone, and `pumpAndSettle` is fake-async
/// pumps only. Home's card is built from a *second* database read that lands on
/// the last `runAsync` inside `pumpShell`, so the `Image` first resolves after
/// the last real turn and the capture photographs an unresolved frame — a solid
/// `#885CF6` panel, which is exactly what the first regeneration produced. The
/// deck shots were unaffected only because `_openDeck` happens to take five more
/// real turns after the panel mounts.
///
/// Measured, not assumed: without this call the light Home image reads a flat
/// purple card and the dark one a flat navy card, and `_panelPhoto` still
/// returns the right path — **a widget being in the tree says nothing about its
/// pixels having arrived**, which is §6's whole point about a thumbnail.
Future<void> _letThePhotographLoad(WidgetTester tester) async {
  final photo = find.byType(NaturePhoto);
  expect(photo, findsOneWidget, reason: 'this shot has a photograph in it');
  await tester.runAsync(
    () => precacheImage(
      AssetImage(_panelPhoto(tester)),
      tester.element(photo),
    ),
  );
  await tester.pumpAndSettle();
}

/// The deck's own fixture, separate from [_goldenPack].
///
/// **Twelve words so the cap at ten cards is exercised**, and so the artwork's
/// `3/10` is reachable at all: four entries would cap at four and the counter
/// would read `3/4`.
///
/// **Separate rather than shared because [_goldenPack] must not move.** Six
/// committed reference images are drawn from it. Growing it would change which
/// word `WordOfTheDay.pick` lands on for `home_shell_user_shot.png`, and
/// `search('serenity')` would then match a different number of rows for
/// `word_detail_user_shot_*.png` — `golden_test.dart` records both as
/// deliberate. A pack only this screen uses costs nothing and touches none of
/// them.
const VocabPack _flashcardPack = VocabPack(
  schemaVersion: 1,
  packId: 'deck',
  title: 'Deck',
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
      phonetic: '/æmˈbɪʃən/',
    ),
    VocabEntry(
      id: 'clarity-1',
      term: 'clarity',
      translations: <String>['وضوح'],
      phonetic: '/klærəti/',
    ),
    VocabEntry(
      id: 'courage-1',
      term: 'courage',
      translations: <String>['شجاعة'],
    ),
    VocabEntry(
      id: 'wisdom-1',
      term: 'wisdom',
      translations: <String>['حكمة'],
    ),
    VocabEntry(
      id: 'patience-1',
      term: 'patience',
      translations: <String>['صبر'],
    ),
    VocabEntry(
      id: 'mercy-1',
      term: 'mercy',
      translations: <String>['رحمة'],
    ),
    VocabEntry(
      id: 'honesty-1',
      term: 'honesty',
      translations: <String>['صدق'],
    ),
    VocabEntry(
      id: 'gratitude-1',
      term: 'gratitude',
      translations: <String>['امتنان'],
    ),
    VocabEntry(
      id: 'resolve-1',
      term: 'resolve',
      translations: <String>['عزم'],
    ),
    VocabEntry(
      id: 'grace-1',
      term: 'grace',
      translations: <String>['نعمة'],
    ),
    VocabEntry(
      id: 'trust-1',
      term: 'trust',
      translations: <String>['ثقة'],
    ),
  ],
);
