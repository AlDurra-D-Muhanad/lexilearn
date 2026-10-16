import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';

import '../helpers/test_env.dart';

/// The one Home tile that pushes a route rather than selecting a bar
/// destination, and the label on it.
///
/// The tap is how this file reaches Stats: `showDialog`-free navigation aside,
/// the app's only entry to the screen is this tile, so a reference image
/// captured any other way would be a picture of something the user cannot get
/// to. See `lib/ui/home/home_screen.dart` → `_QuickLaunchGrid`.
const _statsTile = 'إحصائياتك';

/// `pumpShell` mounts `LexiLearnApp(repository:)` — the real app — so this file
/// does not import `app.dart` itself; it mounts through the shared helper like
/// every other screen test, for the same fake-async reason.

/// The pack the reference image is drawn from.
///
/// The artwork's own words, so the committed PNG can be put next to
/// `docs/design/brand-reference.png` and compared without translating anything
/// first. Deterministic and in-memory — the golden depends on the entries, not on
/// whatever `assets/packs/` happens to hold.
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
}

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
