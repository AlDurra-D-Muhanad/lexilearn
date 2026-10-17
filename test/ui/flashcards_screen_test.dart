import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/flashcards/flashcard_controller.dart';
import 'package:lexilearn/ui/flashcards/flashcards_screen.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
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

    testWidgets('the illustrated nature panel the artwork draws is present',
        (tester) async {
      await _pumpDeck(tester, controller: await _dealt(tester));

      // §4ج: «الصورة التوضيحية: صورة طبيعة مروسة». There is no image asset in
      // this repository and photographs are out of scope by user decision, so
      // the panel is drawn rather than loaded — see the screen's own note. What
      // is pinned here is that the slot exists, at the artwork's proportion, and
      // that it is a glyph rather than a broken image.
      expect(find.byIcon(Icons.landscape_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      await _pumpDeck(tester, controller: await _dealt(tester));

      // The artwork shows أعرف, لا أعرف **and** the عرض المعنى link together, in
      // that order, on one card. Gating the two answer buttons behind `revealed`
      // would be a tidier interaction and a different screen.
      expect(find.widgetWithText(FilledButton, _knowIt), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, _dontKnowIt), findsOneWidget);
      expect(find.widgetWithText(TextButton, _reveal), findsOneWidget);
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
    this.controller,
  });

  final VocabRepository repository;
  final String packKey;
  final Brightness brightness;
  final FlashcardController? controller;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<VocabRepository>.value(value: repository),
        if (controller != null)
          ChangeNotifierProvider<FlashcardController>.value(value: controller!),
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