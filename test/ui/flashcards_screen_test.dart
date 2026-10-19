import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/flashcards/flashcard_controller.dart';
import 'package:lexilearn/ui/flashcards/flashcards_screen.dart';
import 'package:lexilearn/ui/settings/app_settings_controller.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:lexilearn/ui/wallpaper/nature_photo.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_catalog.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../helpers/test_env.dart';

/// The chrome and the card copy, as `lib/ui/flashcards/flashcards_screen.dart`
/// spells them. **Every one of these is read out of
/// `docs/design/brand-reference.png` §4ج and the PNG itself** — this screen is
/// the one place in the app where a committed raster is a reference and not an
/// implementer's invention, so the strings are pinned here rather than restated
/// in prose.
const _title = 'بطاقات التعلم';
const _knowIt = 'أعرف';
const _dontKnowIt = 'لا أعرف';
const _reveal = 'عرض المعنى';
const _swipeHint = 'السحب للتالي';
const _loading = 'جارٍ التحميل…';
const _finished = 'انتهت الجلسة';
const _emptyPack = 'لا توجد بطاقات بعد';

/// The artwork's own word, so the reference image can be put next to
/// `brand-reference.png` and compared without translating anything first.
const _term = 'serenity';
const _phonetic = '/səˈrenəti/';
const _meaning = 'الهدوء والسكينة';

/// Twelve words, so a ten-card deck is a real deck.
///
/// **The count is the point of the fixture.** The artwork's counter reads `3/10`
/// and `English.txt` ships 297 entries, so a deck is the pack capped at ten
/// cards; a three-word fixture would cap at three and the `3/10` could not be
/// reproduced at all.
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

/// Everything inside the flashcards screen and nothing outside it.
Finder inDeck(String text) =>
    find.descendant(of: find.byType(FlashcardsScreen), matching: find.text(text));

/// A controller the test owns, already dealt and — optionally — already revealed.
///
/// **Run before the tree is mounted, and inside `runAsync`.** `start()` reads
/// the pack, and a `testWidgets` body runs in a fake-async zone where a real
/// sqflite future never answers on its own; awaited bare, this hangs to the
/// ten-minute timeout with nothing naming the cause. The same one-line reason
/// `pumpShell` and `readOutsideFakeAsync` exist.
///
/// **The seed is chosen, not arbitrary.** `QuizGenerator` picks the answer
/// *before* it builds its distractors, so which word lands on the card is
/// decided by `_random.nextInt` on the unseen set and is the same whatever
/// `cardCount` is. Measured across 60 seeds against this exact fixture:
///
/// | seed | first card |
/// |---|---|
/// | 1 | `serenity-1` — the artwork's word, **and** the only fixture entry with a phonetic on the first card that also has one |
/// | 3 | `honesty-1` — the fixture's word with **no** phonetic |
///
/// Injecting is what makes the dealt card a known word at all. The screen owns
/// its own controller on the app's path and deals unseeded, which is correct for
/// a vocabulary app — a fixed seed in the screen would give every user the same
/// deck — and useless to a test that has to name the term it is looking for.
/// Same shape, and the same reason, as `StatsScreen`'s optional controller.
Future<FlashcardController> _dealt(
  WidgetTester tester, {
  int cardCount = 3,
  int seed = 1,
  bool revealed = false,
}) async {
  final controller = FlashcardController(
    repository: harness.repository,
    packKey: 'en_ar',
    cardCount: cardCount,
    random: Random(seed),
  );
  addTearDown(controller.dispose);
  await tester.runAsync(() async {
    await controller.start();
    if (revealed) await controller.reveal();
  });
  return controller;
}

/// Mounts the screen the way the app does — the brand theme, the app-wide RTL
/// direction — with the repository the real app's `Provider` supplies, and
/// optionally a controller the test has already dealt.
Future<void> _pumpDeck(
  WidgetTester tester, {
  String packKey = 'en_ar',
  Brightness brightness = Brightness.light,
  FlashcardController? controller,
}) async {
  await tester.pumpWidget(
    _DeckApp(
      repository: harness.repository,
      packKey: packKey,
      brightness: brightness,
      settings: createAppSettings(harness.repository),
      controller: controller,
    ),
  );
  await _settleDeck(tester);
}

/// Three real turns of the event loop, bounded.
///
/// **One read now, and this used to need two.** `FlashcardsScreen` reads the pack
/// once to learn how many cards the deck has and hands the words straight to
/// `FlashcardController.start`, so the second of those reads is gone; see
/// `FlashcardController.entries`. **Two sequential round trips is the shape that
/// bites**, though, and three turns is still the right budget for anything that
/// taps one of the three actions — each of those writes through `recordAnswer`,
/// and `docs/engineering-standards.md` §5 records that one real turn is measured
/// at 2 under load against a 3-turn budget, while a second suite running
/// concurrently **is** that load. It cost this screen one out-of-scope test edit
/// before it was halved; see `home_screen_test.dart`.
///
/// Bounded at three, and it decides nothing: every assertion after it is what
/// decides pass or fail. It only stops a test reading the screen before the
/// screen's own read has landed. Same shape and same reason as `_tap` in
/// `test/ui/more_screen_test.dart`.
Future<void> _settleDeck(WidgetTester tester) async {
  for (var turn = 0; turn < 3; turn++) {
    await settleDatabase(tester);
  }
}

/// The three controls the artwork draws together, in its order.
///
/// Shared rather than inlined, because the assertion now runs twice — against an
/// unrevealed card and against a revealed one — and it is the *pair* that says
/// something: a version of this screen that gated the answer buttons behind
/// `revealed` would pass the first and fail the second.
Future<void> _expectAllThreeControls(WidgetTester tester, String state) async {
  expect(find.widgetWithText(FilledButton, _knowIt), findsOneWidget,
      reason: 'أعرف is missing on $state');
  expect(find.widgetWithText(OutlinedButton, _dontKnowIt), findsOneWidget,
      reason: 'لا أعرف is missing on $state');
  expect(find.widgetWithText(TextButton, _reveal), findsOneWidget,
      reason: 'عرض المعنى is missing on $state');
  // And in the artwork's order, top to bottom. A `Row` would satisfy the three
  // `findsOneWidget` above while drawing them side by side.
  expect(
    _findCentreY(tester, find.widgetWithText(FilledButton, _knowIt)),
    lessThan(_findCentreY(tester, find.widgetWithText(OutlinedButton, _dontKnowIt))),
    reason: 'the answer buttons are stacked, not side by side',
  );
  expect(
    _findCentreY(tester, find.widgetWithText(OutlinedButton, _dontKnowIt)),
    lessThan(_findCentreY(tester, find.widgetWithText(TextButton, _reveal))),
  );
}

/// The vertical centre of [finder], so two can be compared for order.
double _findCentreY(WidgetTester tester, Finder finder) =>
    tester.getCenter(finder).dy;

/// A tap on one of the three card actions, followed by [_settleDeck].
///
/// `أعرف` and `لا أعرف` each write through `recordAnswer`, so a tap here is a
/// database round trip as well as a rebuild — the same bounded wait, for the
/// same reason, rather than a second copy of the loop.
Future<void> _tapAction(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settleDeck(tester);
}

late TestHarness harness;

void main() {
  setUp(() async {
    harness = await TestHarness.create(packs: const <VocabPack>[_pack]);
  });

  tearDown(() => harness.dispose());

  group('the card', () {
    testWidgets('shows the term and its pronunciation, and hides the meaning',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      // `brand-reference.md` §4ج: «الكلمة والنطق» — the word *and* the
      // pronunciation are on the face of the card, and they are the whole of it.
      expect(inDeck(_term), findsOneWidget);
      expect(inDeck(_phonetic), findsOneWidget);
      // §4ج: «رابط عرض المعنى» — the meaning is behind that link, not beside the
      // word. The artwork draws a card with the Arabic visible because a mock is
      // one frame; the control that hides it is the point of the screen.
      expect(inDeck(_meaning), findsNothing);
      expect(inDeck(_reveal), findsOneWidget);
    });

    testWidgets('the reveal link shows the meaning and records nothing',
        (tester) async {
      final controller = await _dealt(tester);
      await _pumpDeck(tester, controller: controller);

      await _tapAction(tester, find.widgetWithText(TextButton, _reveal));

      expect(inDeck(_meaning), findsOneWidget);
      expect(controller.revealed, isTrue);
      expect(controller.index, 0,
          reason: 'looking at a card is not answering it');
      final stats =
          await readOutsideFakeAsync(tester, () => harness.repository.stats('en_ar'));
      expect(stats.totalAttempts, 0);
    });

    testWidgets('a word with no phonetic omits the line rather than stranding it',
        (tester) async {
      // Seed 3 deals `honesty-1`, the fixture's word with no phonetic at all.
      // A screen that always drew the row would show an empty line under the
      // term, which is the defect `word_detail_screen.dart` was written against.
      final controller = await _dealt(tester, cardCount: 3, seed: 3);
      expect(controller.current!.term, 'honesty');
      expect(controller.current!.phonetic, isEmpty);

      await _pumpDeck(tester, controller: controller);
      await _tapAction(tester, find.widgetWithText(TextButton, _reveal));

      expect(inDeck('honesty'), findsOneWidget);
      expect(inDeck('صدق'), findsOneWidget,
          reason: 'the meaning is not what the phonetic line was standing in for');
      expect(tester.takeException(), isNull);
    });

    testWidgets('every surface is an AppSurface and nothing is a bare Card',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      // The word card and the swipe hint: the artwork draws both as rounded
      // surfaces and `docs/engineering-standards.md` §6 makes every card one.
      expect(
        find.descendant(
            of: find.byType(FlashcardsScreen), matching: find.byType(AppSurface)),
        findsNWidgets(2),
      );
      // The other half of the same rule: a bare `Card` renders a hard black
      // keyline in this rasteriser, measured at 29,111 pixels once.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the panel is one of the user\'s photographs, at the artwork\'s '
        '2:1, and not the glyph that used to stand there', (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      // §4ج: «الصورة التوضيحية: صورة طبيعة مروسة». The slot was there before the
      // photographs were; what is pinned now is that it is filled by the user's
      // own file rather than by a brand glyph.
      expect(find.byIcon(Icons.landscape_rounded), findsNothing,
          reason: 'the stand-in glyph is gone, and it must not come back');

      final photo = find.byType(NaturePhoto);
      expect(photo, findsOneWidget);
      final shown = tester.widget<NaturePhoto>(photo);
      expect(shown.assetPath, isIn(Wallpapers.light),
          reason: 'the light card draws the light set, as the user filed it');
      expect(shown.assetPath, startsWith('assets/wallpapers/'));

      // **2:1 measured off the rendered tree, not read off the constant.**
      // `_natureAspect` is 2 and every staged file is 2.0000:1, so this is the
      // assertion that the drop-in really was a drop-in: a panel at any other
      // proportion would crop or letterbox the photograph.
      final panel = tester.getRect(photo);
      expect(panel.width / panel.height, closeTo(2, 0.01),
          reason: 'the panel is ${panel.width}x${panel.height}');
    });

    testWidgets('there is no scrim on this panel: no ink is drawn on the '
        'photograph at all', (tester) async {
      // The reason is structural, and this is what says it: the term, its
      // pronunciation and its meaning are all on the surface *below* the panel.
      // Adding a scrim here would dim the picture for text that is not on it.
      await _pumpDeck(tester, controller: await _dealt(tester));

      final panel = find.ancestor(
        of: find.byType(NaturePhoto),
        matching: find.byType(ClipRRect),
      );
      expect(panel, findsWidgets, reason: 'the panel is clipped by the card');
      expect(
        find.descendant(of: panel.first, matching: find.byType(Text)),
        findsNothing,
        reason: 'nothing is drawn over the photograph, so nothing needs a scrim',
      );
      expect(
        find.descendant(of: panel.first, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
    });

    testWidgets('the dark card draws the dark set, the light card the light one',
        (tester) async {
      await _pumpDeck(
        tester,
        controller: await _dealt(tester),
        brightness: Brightness.dark,
      );
      final dark =
          tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;
      expect(dark, isIn(Wallpapers.dark));
      expect(dark, isNot(isIn(Wallpapers.light)));

      await _pumpDeck(tester, controller: await _dealt(tester));
      final light =
          tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;
      expect(light, isIn(Wallpapers.light));
      expect(light, isNot(isIn(Wallpapers.dark)));
    });

    testWidgets('the photograph changes on every card-to-card transition',
        (tester) async {
      final controller = await _dealt(tester, cardCount: 3);
      await _pumpDeck(tester, controller: controller);

      String shown() => tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;
      var seen = <String>{shown()};
      expect(seen, hasLength(1));

      for (var i = 0; i < 2; i++) {
        await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));
        await tester.pumpAndSettle();
        seen.add(shown());
        expect(seen, hasLength(i + 2),
            reason: 'the photograph did not move with the card');
      }
    });

    testWidgets('but it does not move when the meaning is revealed, because '
        'that is the same card', (tester) async {
      // The distinction the panel turns on: `reveal()` re-renders the whole
      // card, so a panel that advanced on every rebuild would change the
      // photograph out from under a word the user is reading.
      final controller = await _dealt(tester);
      await _pumpDeck(tester, controller: controller);
      final before =
          tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath;

      await _tapAction(tester, find.widgetWithText(TextButton, _reveal));
      await tester.pumpAndSettle();

      expect(inDeck(_meaning), findsOneWidget,
          reason: 'the reveal really did happen');
      expect(
        tester.widget<NaturePhoto>(find.byType(NaturePhoto)).assetPath,
        before,
      );
    });
  });

  group('the artwork\'s two buttons', () {
    testWidgets('أعرف is a full-width filled pill in the light brand purple',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, _knowIt));
      final style = button.style!;
      expect(style.backgroundColor?.resolve(<WidgetState>{}), AppColors.primaryLight,
          reason: '§4ج: «أعرف (بنفسجي بالوضع الفاتح)»');
      expect(style.shape?.resolve(<WidgetState>{}), isA<StadiumBorder>(),
          reason: 'every action in the artwork is a full pill');
      expect(tester.getSize(find.widgetWithText(FilledButton, _knowIt)).width,
          tester.getSize(find.byType(FlashcardsScreen)).width - 2 * AppSpacing.m,
          reason: 'the artwork draws it edge to edge');
    });

    /// **The one artwork detail with no counterpart anywhere else in the app.**
    ///
    /// §4ج: «زر أعرف (بنفسجي بالوضع الفاتح / **أصفر بالوضع الداكن**)». The amber
    /// is not an accident of the raster — `docs/design/brand-reference.md` §2's
    /// dark palette assigns `#F59E0B` to «الأزرار الذهبية الرئيسية», main golden
    /// buttons, so the mock and the palette agree. Everything else on this screen
    /// swaps light→dark by naming the other brightness's token; this one swaps
    /// hue, and a screen that reached for `primaryDark` here would pass every
    /// other test on this file.
    testWidgets('أعرف is the amber accent in dark mode, not the dark primary',
        (tester) async {
      await _pumpDeck(
        tester,
        brightness: Brightness.dark,
        controller: await _dealt(tester),
      );

      final style =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, _knowIt)).style!;
      expect(style.backgroundColor?.resolve(<WidgetState>{}), AppColors.accent);
      expect(style.backgroundColor?.resolve(<WidgetState>{}), isNot(AppColors.primaryDark));
      // …and the label has to stay readable on it. `#F59E0B` at full strength
      // under the dark background's own light ink would be unreadable, so the
      // amber pill carries the *background* ink, not the text one.
      expect(style.foregroundColor?.resolve(<WidgetState>{}),
          AppColors.backgroundDark);
    });

    testWidgets('لا أعرف is an outlined pill with a light border, never filled',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      final button =
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, _dontKnowIt));
      final style = button.style!;
      expect(style.side?.resolve(<WidgetState>{})?.color, AppColors.primaryLight,
          reason: '§4ج: «زر لا أعرف (مفرغ بحواف خفيفة)» — outlined, in the ink');
      expect(style.backgroundColor, isNull,
          reason: 'an outlined button that declares a fill is not outlined');
      expect(style.shape?.resolve(<WidgetState>{}), isA<StadiumBorder>());
    });

    testWidgets('the dark outlined button follows the dark amber', (tester) async {
      await _pumpDeck(
        tester,
        brightness: Brightness.dark,
        controller: await _dealt(tester),
      );

      final style = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, _dontKnowIt))
          .style!;
      expect(style.side?.resolve(<WidgetState>{})?.color, AppColors.accent);
      expect(style.foregroundColor?.resolve(<WidgetState>{}), AppColors.accent);
    });

    testWidgets('both buttons are on screen at once, as the artwork draws them',
        (tester) async {
      // **Both states, and the revealed one is the artwork's own frame.** §4ج and
      // the PNG draw all three controls together with the meaning already visible.
      // That frame is what the reference image captures, and it was unpinned: the
      // first version of this test only ever saw an *unrevealed* controller, so
      // nothing would have noticed the three controls disappearing on reveal — the
      // exact failure the plan's `revealed`-gated version of this screen ships.
      await _pumpDeck(tester, controller: await _dealt(tester));
      await _expectAllThreeControls(tester, 'an unrevealed card');

      final controller = await _dealt(tester, revealed: true);
      await _pumpDeck(tester, controller: controller);
      await _expectAllThreeControls(tester, 'a revealed card');
      expect(inDeck(_meaning), findsOneWidget,
          reason: '…and the meaning is on screen with them, which is the '
              'artwork\'s frame');
    });

    testWidgets('عرض المعنى is a link in the brand primary, not a button',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      // §2's light palette assigns the primary to «الروابط», links.
      final style =
          tester.widget<TextButton>(find.widgetWithText(TextButton, _reveal)).style!;
      expect(style.foregroundColor?.resolve(<WidgetState>{}), AppColors.primaryLight);
      expect(find.widgetWithText(FilledButton, _reveal), findsNothing);
      expect(find.widgetWithText(OutlinedButton, _reveal), findsNothing);
    });

    testWidgets('no button on this screen declares or paints an elevation shadow',
        (tester) async {
      // **Two layers, and this file only ever has the second one.**
      //
      // `more_screen_test.dart` checks the *widget's declared* `style.elevation`,
      // because those call sites carry a local `elevation: 0`. **This screen's
      // must not**: `docs/engineering-standards.md` §6 and Task 13's review found
      // that per-widget opt-out had already been forgotten on three separate
      // screens, so `AppTheme` now zeroes `elevatedButtonTheme`,
      // `filledButtonTheme` and `outlinedButtonTheme` theme-wide and the correct
      // thing here is to declare nothing at all.
      //
      // So the local value must be **absent** — `null`, not `0.0`. A `0.0` here
      // would be the deleted-in-spirit local opt-out coming back. What the button
      // *paints* is the second layer: the `Material` it builds, whose elevation
      // is the resolved value and which is what `canvas.drawShadow` would keyline.
      await _pumpDeck(tester, controller: await _dealt(tester));

      const resting = <WidgetState>{};
      const hovering = <WidgetState>{WidgetState.hovered};
      const pressed = <WidgetState>{WidgetState.pressed};

      for (final finder in <Finder>[
        find.widgetWithText(FilledButton, _knowIt),
        find.widgetWithText(OutlinedButton, _dontKnowIt),
        find.widgetWithText(TextButton, _reveal),
      ]) {
        final button = tester.widget<ButtonStyleButton>(finder);
        for (final entry in <String, Set<WidgetState>>{
          'resting': resting,
          'hovered': hovering,
          'pressed': pressed,
        }.entries) {
          expect(
            button.style?.elevation?.resolve(entry.value),
            isNull,
            reason: '${button.runtimeType} declares a local elevation in its '
                '${entry.key} state; the theme supplies this one',
          );
        }
        final material = tester.widget<Material>(
          find.descendant(of: finder, matching: find.byType(Material)).first,
        );
        expect(material.elevation, 0.0,
            reason: '${button.runtimeType} paints a Material at elevation '
                '${material.elevation}, which is a keyline');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the deck', () {
    testWidgets('the counter reads the artwork\'s fraction of the deck',
        (tester) async {
      // The screen's own owner this time, not an injected controller: the ten
      // comes from **its** decision to cap the pack, which is the thing under
      // test. Twelve entries in, ten cards out.
      await _pumpDeck(tester);

      expect(inDeck('1/10'), findsOneWidget);
      expect(inDeck(_title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the progress bar is determinate and tracks the counter',
        (tester) async {
      final controller = await _dealt(tester, cardCount: 4);
      await _pumpDeck(tester, controller: controller);

      // Deterministic, and determinate: an indeterminate `CircularProgressIndicator`
      // schedules frames forever, so `pumpAndSettle` would never return while one
      // was on screen — which is why no spinner appears anywhere on this screen.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        0.0,
      );

      await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));

      expect(inDeck('2/4'), findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        0.25,
      );
    });

    testWidgets('the counter advances to the artwork\'s 3/10', (tester) async {
      final controller = await _dealt(tester, cardCount: 10);
      await _pumpDeck(tester, controller: controller);

      await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));
      await _tapAction(tester, find.widgetWithText(OutlinedButton, _dontKnowIt));

      expect(inDeck('3/10'), findsOneWidget,
          reason: '§4ج names this counter: «مؤشر 3/10»');
    });

    testWidgets('the Latin run in the counter asks for the brand Latin and LTR',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      final text = tester.widget<Text>(inDeck('1/3'));
      expect(text.textDirection, TextDirection.ltr,
          reason: 'an RTL paragraph reorders a run of digits and a slash');
      expect(text.style?.fontFamily, 'Inter');
    });

    testWidgets('the swipe hint names the gesture in the artwork\'s pill',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      // §4ج: «إشارة السحب: << اسحب لليوم >>» — **but the PNG says something
      // else, and the PNG is the authority** (`docs/engineering-standards.md`
      // §10). Measured off the raster at 18x: both the light phone and the dark
      // phone read «السحب للتالي», the light one at crop `x 500..575, y 658..678`
      // and the dark one at `x 1120..1200, y 652..672`. The prose and the plan
      // snippet say «اسحب» / «لليوم»; the artwork says «للتالي», which is also
      // what the control does. Both phones agreeing is why this is not a
      // judgement call.
      expect(inDeck(_swipeHint), findsOneWidget);
      expect(
        find.ancestor(of: inDeck(_swipeHint), matching: find.byType(AppSurface)),
        findsOneWidget,
        reason: 'the artwork draws the hint inside a rounded pill',
      );
      // The chevrons either side of it, which are what makes it a gesture and
      // not a caption.
      expect(find.text('<<'), findsOneWidget);
      expect(find.text('>>'), findsOneWidget);
    });

    testWidgets('the swipe hint is set in the Arabic face, not the brand Latin',
        (tester) async {
      // **A `find.text` on this string cannot see the defect, and that is the
      // point.** The first version of this screen set the hint in
      // `AppText.latin`; `find.text('السحب للتالي')` matched it happily and
      // every other assertion on this file stayed green — while the committed
      // reference image showed a row of **tofu boxes**. Inter's `cmap` carries no
      // Arabic, so the string is present and nothing is legible.
      //
      // It was found by opening the generated PNG, not by any test, which is the
      // failure `docs/engineering-standards.md` §1 describes from the other side:
      // `find.text` was a claim ("this string renders") that nothing could fail.
      // The font family is now the assertion.
      //
      // The same rule, and the same reason, as `home_screen.dart`'s search field:
      // a run whose script is not the family's must name the family it belongs
      // to, and `AppText.latin` is for Latin runs only.
      await _pumpDeck(tester, controller: await _dealt(tester));

      expect(inDeck(_swipeHint), findsOneWidget);
      expect(tester.widget<Text>(inDeck(_swipeHint)).style?.fontFamily, 'Tajawal');
    });

    testWidgets('the Arabic face, not the brand Latin, on every Arabic string here',
        (tester) async {
      // **The class, not one string.** The screen shipped with «السحب للتالي» set
      // in `AppText.latin`, which rasterised as a row of tofu boxes — and
      // `find.text('السحب للتالي')` matched it happily, because a tofu row is
      // still a `Text` whose `data` is that string. Every assertion on it passed.
      // Only opening the generated PNG showed it: §1's shape from the other side,
      // a claim nothing could fail.
      //
      // So this walks **every** Arabic string the screen draws, in **each of its
      // states**. Adding `AppText.latin` to `_knowIt`, `_title` or any of the
      // other six now fails here. See `arabicRunsIn` in
      // `test/helpers/test_env.dart` for why this is a shared helper rather than
      // another per-string assertion.
      //
      // **Every state is visited deliberately**, because the strings are not all
      // on screen at once: the meaning and the controls together only while
      // revealed, the summary only once the deck is over, and `_loading` only
      // while the owner's read is in flight.
      const brandedLatin = 'Inter';
      Future<void> expectNoTofu(String state) async {
        final offenders = arabicRunsIn(tester, FlashcardsScreen)
            .where((run) => run.family == brandedLatin)
            .toList();
        expect(
          offenders,
          isEmpty,
          reason: '$state draws Arabic in $brandedLatin, whose cmap carries no '
              'Arabic — it rasterises as tofu',
        );
      }

      // While the owner's read is in flight: «جارٍ التحميل…». No settle, which is
      // the only way to see this state at all.
      await tester.pumpWidget(
        _DeckApp(
          repository: harness.repository,
          packKey: 'en_ar',
          brightness: Brightness.light,
          settings: createAppSettings(harness.repository),
        ),
      );
      await tester.pump();
      expect(inDeck(_loading), findsOneWidget,
          reason: 'this is the state the next line guards');
      await expectNoTofu('the loading state');

      final controller = await _dealt(tester);
      await _pumpDeck(tester, controller: controller);
      await expectNoTofu('a card before it is revealed');

      // **Through the real buttons, and never by awaiting the controller.**
      // `answer()` awaits `recordAnswer`, and a `testWidgets` body runs in a
      // fake-async zone where a real sqflite future never answers on its own —
      // awaited bare it hangs to the ten-minute timeout with nothing naming the
      // cause (`docs/engineering-standards.md` §5). `_tapAction` fires and gives
      // the write a real turn, which is the sanctioned shape.
      await _tapAction(tester, find.widgetWithText(TextButton, _reveal));
      expect(controller.revealed, isTrue,
          reason: 'this is the state the next line guards');
      await expectNoTofu('a card after it is revealed');

      await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));
      await _tapAction(tester, find.widgetWithText(OutlinedButton, _dontKnowIt));
      await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));
      expect(inDeck(_finished), findsOneWidget);
      await expectNoTofu('the finished deck');

      // And the empty pack, the only state that names `_emptyPack`.
      await tester.pumpWidget(
        _DeckApp(
          repository: harness.repository,
          packKey: '',
          brightness: Brightness.light,
          settings: createAppSettings(harness.repository),
        ),
      );
      await tester.pump();
      await expectNoTofu('the empty-pack state');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the counter sits at the left end and the bar fills from the right',
        (tester) async {
      // **A deliberate divergence from the artwork, so it is pinned.** The PNG
      // draws this row left-to-right on both phones — `3/10` at the *right* and
      // the fill at the track's *left* end — while the same phone's title and back
      // arrow are laid out RTL. The row is the inconsistent part and not the
      // screen, so this screen follows the app's direction, as `_Header` in
      // `home_screen.dart` does for the same reason.
      //
      // Two halves, and both are load-bearing. The **positions** say which end the
      // counter is on. The **ambient direction** is what makes the *fill* grow
      // from the right, because `LinearProgressIndicator` reverses with it —
      // reading only the positions would leave "and the fill grows from the right"
      // as an unmeasured claim, which is §1's whole subject.
      final controller = await _dealt(tester, cardCount: 4);
      await _pumpDeck(tester, controller: controller);

      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);

      final counterX = tester.getTopLeft(inDeck('1/4')).dx;
      final barLeftX = tester.getTopLeft(bar).dx;
      final barRightX = tester.getBottomRight(bar).dx;

      expect(counterX, lessThan(barLeftX),
          reason: 'the counter is at the LEFT end of the row');
      expect(counterX, lessThan(barRightX));
      expect(
        Directionality.of(tester.element(bar)),
        TextDirection.rtl,
        reason: '…and the fill grows from the RIGHT because the indicator '
            'reverses with the ambient direction',
      );
    });

    testWidgets('the speaker sits at the right of the word, as the artwork draws it',
        (tester) async {
      // **The second divergence, and the one that was simply wrong.** Both speaker
      // glyphs were on the *left* of their word, because `Row` lays its first
      // child out at the start — the right, in RTL — and the word was first.
      //
      // Verified off the raster rather than taken on trust: scanning the light
      // phone's word row for the purple glyph against the dark word ink returns
      // dark ink at `x 495..577` and then an isolated purple block carrying **no**
      // dark ink at `x 585..599` — the speaker, to the *right* of the word. At 9x
      // it is unmistakable.
      await _pumpDeck(tester, controller: await _dealt(tester));

      final speakers = find.byIcon(Icons.volume_up_rounded);
      expect(speakers, findsNWidgets(2),
          reason: 'the artwork draws one beside the word and one beside the '
              'phonetic');

      expect(
        tester.getTopLeft(speakers.at(0)).dx,
        greaterThan(tester.getTopLeft(inDeck(_term)).dx),
        reason: 'the term speaker is at the RIGHT of the term',
      );
      expect(
        tester.getTopLeft(speakers.at(1)).dx,
        greaterThan(tester.getTopLeft(inDeck(_phonetic)).dx),
        reason: 'the phonetic speaker is at the RIGHT of the phonetic, as the '
            'artwork draws it',
      );
    });

    testWidgets('the title is on the background, not on a raised surface',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, AppColors.backgroundLight);
      expect(appBar.surfaceTintColor, Colors.transparent);
    });

    testWidgets('a pack with no words says so instead of dealing an empty deck',
        (tester) async {
      await readOutsideFakeAsync(
        tester,
        () => harness.repository.importPack('{"schemaVersion":1,"packId":"empty",'
            '"title":"E","sourceLanguage":"en","targetLanguage":"ar","entries":[]}'),
      );

      await _pumpDeck(tester, packKey: 'empty');

      expect(inDeck(_emptyPack), findsOneWidget);
      expect(inDeck(_finished), findsNothing,
          reason: 'a pack with no words is not a finished deck');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the deck ends with what was known out of how many',
        (tester) async {
      final controller = await _dealt(tester, cardCount: 3);
      await _pumpDeck(tester, controller: controller);

      await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));
      await _tapAction(tester, find.widgetWithText(OutlinedButton, _dontKnowIt));
      await _tapAction(tester, find.widgetWithText(FilledButton, _knowIt));

      expect(inDeck(_finished), findsOneWidget);
      expect(inDeck('2 / 3'), findsOneWidget);
      // …and the deck is gone: the two answer buttons go with it, because there
      // is no card left to answer.
      expect(find.widgetWithText(FilledButton, _knowIt), findsNothing);
      expect(inDeck(_reveal), findsNothing);
      final stats =
          await readOutsideFakeAsync(tester, () => harness.repository.stats('en_ar'));
      expect(stats.totalAttempts, 3);
      expect(stats.totalCorrect, 2);
    });

    testWidgets('the dark theme reaches the dark tokens', (tester) async {
      await _pumpDeck(
        tester,
        brightness: Brightness.dark,
        controller: await _dealt(tester),
      );

      // The counter and the hint are the two secondary-ink runs on this screen,
      // and they are the ones the dark palette names differently.
      expect(
        tester.widget<Text>(inDeck('1/3')).style?.color,
        AppColors.textSecondaryDark,
      );
      expect(
        find.ancestor(of: inDeck(_term), matching: find.byType(AppSurface)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('reached from the bottom bar', () {
    testWidgets('البطاقات lands here and the pack key reaches the deck',
        (tester) async {
      // The artwork's bar draws exactly four items and `البطاقات` is the second.
      // `test/ui/home_shell_test.dart` pins the four labels and icons; this pins
      // the destination this task actually filled in, and it needs the bounded
      // wait for the reason `more_screen_test.dart` does: tapping the bar
      // mounts the screen, whose owner then runs two sequential reads.
      await pumpShell(tester, harness.repository);

      await tester.tap(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text('البطاقات')),
      );
      await tester.pumpAndSettle();
      await _settleDeck(tester);

      expect(find.byType(FlashcardsScreen), findsOneWidget);
      expect(inDeck(_title), findsOneWidget);
      expect(inDeck('1/10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home\'s flashcard tile lands here and leaves the bar where it was',
        (tester) async {
      // The grid tile is the app's *second* door into this screen, and the reason
      // `HomeShell` publishes `ShellTabScope` at all.
      await pumpShell(tester, harness.repository);

      await tester.tap(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.text('بطاقات التعلم'),
        ),
      );
      await tester.pumpAndSettle();
      await _settleDeck(tester);

      expect(find.byType(FlashcardsScreen), findsOneWidget);
      expect(
        _selectedTab(tester),
        1,
        reason: 'the tile selects the bar destination rather than pushing a copy',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// The bar's selected index, read off the `NavigationBar` rather than out of the
/// shell — the same object the bar itself draws from.
int _selectedTab(WidgetTester tester) => tester
    .widget<NavigationBar>(find.byType(NavigationBar))
    .selectedIndex;

class _DeckApp extends StatelessWidget {
  const _DeckApp({
    required this.repository,
    required this.packKey,
    required this.brightness,
    required this.settings,
    this.controller,
  });

  final VocabRepository repository;
  final String packKey;
  final Brightness brightness;
  final FlashcardController? controller;

  /// The theme/launcher seams `LexiLearnApp` would have installed.
  /// `FlashcardsScreen` carries the app's overflow menu in its `AppBar`, which
  /// reads both — see `appSeamProviders` in `test/helpers/test_env.dart`.
  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<VocabRepository>.value(value: repository),
        if (controller != null)
          ChangeNotifierProvider<FlashcardController>.value(value: controller!),
        ...appSeamProviders(settings: settings),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: FlashcardsScreen(packKey: packKey),
      ),
    );
  }
}