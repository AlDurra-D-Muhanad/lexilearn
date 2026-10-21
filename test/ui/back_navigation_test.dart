import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/flashcards/flashcards_screen.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/home_shell.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_setup_screen.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';

import '../helpers/test_env.dart';

/// The bottom bar's other three destinations: the icon that reaches them and the
/// screen each must land on.
///
/// The same four the artwork draws, and deliberately not five — `test/ui/
/// home_shell_test.dart` owns that count. This file only cares about what back
/// does from each of the three non-Home tabs.
const _otherDestinations = <(IconData, Type)>[
  (Icons.style_outlined, FlashcardsScreen),
  (Icons.check_box_outlined, QuizSetupScreen),
  (Icons.apps, MoreScreen),
];

const _pack = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'serenity-1', term: 'serenity', translations: <String>['هدوء']),
  ],
);

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: const <VocabPack>[_pack]);
  });

  tearDown(() => harness.dispose());

  /// The bottom bar's selected index, read off the widget the bar draws from.
  int barIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  group('back from a bottom-bar destination', () {
    for (final (icon, screen) in _otherDestinations) {
      testWidgets('returns to Home instead of leaving the app, from $screen',
          (tester) async {
        // Item 3. The user reported the whole app closing from a pushed screen;
        // measured on the unmodified tree, the cause was here: `MaterialApp`'s
        // `home:` **is** the root route and the four bar destinations are not
        // routes at all, so back had nothing to pop and `maybePop` reached
        // `RoutePopDisposition.bubble` — which reports "not handled", and that is
        // what tells the engine to close the app. The pushed screens were always
        // fine, which is why the report named them.
        //
        // **Every assertion below is tree state.** `handlePopRoute`'s return
        // value is deliberately not captured: `NavigatorState.maybePop` returns
        // `true` for `RoutePopDisposition.doNotPop` — that is, for a pop this app
        // *deliberately blocked* — as well as for a real one, because what it
        // reports is "handled" and being blocked on purpose counts
        // (`docs/engineering-standards.md` §2, traced through `navigator.dart`
        // and `routes.dart` on this SDK). A return value cannot distinguish
        // "blocked and handled" from "navigated", so the tree does.
        await pumpShell(tester, harness.repository);
        expect(find.byType(HomeScreen), findsOneWidget, reason: 'opens on Home');

        await tester.tap(barDestinationIcon(icon));
        await tester.pumpAndSettle();
        await settleDatabase(tester);
        expect(find.byType(screen), findsOneWidget,
            reason: 'the tap reached the destination');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        // **The settle that was missing, and the whole flaky failure.** Back does
        // not navigate: it switches the bar's index, and `HomeShell` swaps the
        // destination inside one `AnimatedSwitcher` keyed by that index
        // (`home_shell.dart:218-228`). So going Home *remounts* `HomeScreen`, and
        // its `initState` calls `_loadPack`, which is a fresh `entries` read
        // (`home_screen.dart:146,220`). `pumpAndSettle` cannot finish that read -
        // `databaseFactoryFfi` answers over a `SendPort` to another isolate, so
        // the reply is a real event, not a microtask - and a body that returned
        // here left sqflite's ten-second lock-warning timer pending, which
        // `flutter_test` fails over as "A Timer is still pending even after the
        // widget tree was disposed". Measured at 6/8 runs of this file on its
        // own, before this settle existed.
        await settleDatabase(tester);

        // What the user asked for: back returns to the main page.
        expect(find.byType(HomeScreen), findsOneWidget,
            reason: 'back returns to الرئيسية');
        expect(find.byType(screen), findsNothing,
            reason: 'and it leaves the destination it came from');
        expect(barIndex(tester), 0, reason: 'the bar follows');

        // And what it must NOT have done: closed the app. On a device a
        // "not handled" answer is `SystemNavigator.pop()`. In a widget test the
        // root route staying in the tree is the closest honest observable of
        // "the app did not go away" that exists without a device.
        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
      });
    }
  });

  group('back from Home', () {
    testWidgets('nothing vetoes the pop, so the app is allowed to close',
        (tester) async {
      // The other half of the user's sentence: «وان كان المستخدم في الصفحة
      // الرئيسية عندها يخرج من التطبيق».
      //
      // **This cannot be asserted from the tree**, and the reason is worth
      // recording: with a blocking `PopScope`, `maybePop` takes the `doNotPop`
      // branch and the route stays; with no `PopScope`, it takes the `bubble`
      // branch and the route *also* stays, because the first route has nothing
      // below it to bubble to. Both outcomes are "the tree is unchanged", so
      // tree state cannot tell them apart — only the return value can, and §2
      // forbids reading that.
      //
      // What *is* observable, and is asserted here, is the mechanism: **no
      // `PopScope` on the root route has `canPop == false`** while Home is
      // showing. A veto is what would swallow the press and keep the user
      // stranded, and its absence is what lets `maybePop` bubble.
      await pumpShell(tester, harness.repository);
      expect(find.byType(HomeScreen), findsOneWidget);

      final vetoes = <PopScope<void>>[
        for (final scope in tester.widgetList<PopScope<void>>(
          find.byType(PopScope<void>),
        ))
          if (!scope.canPop) scope,
      ];
      expect(vetoes, isEmpty,
          reason: 'nothing may veto the pop while Home is showing, or back '
              'would do nothing at all');

      // Sanity: the three non-Home tabs *do* veto, or the test above would pass
      // on an app that has no back handling whatsoever. This is the guard on the
      // guard — without it, deleting every `ShellBackToHome` in the app would
      // leave this test green.
      for (final (icon, screen) in _otherDestinations) {
        await tester.tap(barDestinationIcon(icon));
        await tester.pumpAndSettle();
        await settleDatabase(tester);
        expect(find.byType(screen), findsOneWidget);

        expect(
          tester
              .widgetList<PopScope<void>>(find.byType(PopScope<void>))
              .any((scope) => !scope.canPop),
          isTrue,
          reason: '$screen vetoes the pop so it can answer it itself',
        );
      }
      // The loop above ends on a destination, and this body is over: the settle
      // belongs after the last thing that touched the database, not just between
      // the iterations. See the note on the same line in the first group.
      await settleDatabase(tester);
    });
  });

  group('back from a pushed route', () {
    testWidgets('pops the route and leaves the bar where it was',
        (tester) async {
      // The behaviour that was **already** correct, pinned so the fix above
      // cannot have broken it. `HomeShell._openWordDetail` pushes a real route,
      // so there is something to pop and `maybePop` takes the `pop` branch.
      useAPhone(tester);
      await pumpShell(tester, harness.repository);

      await tester.enterText(find.byType(TextField), 'serenity');
      await tester.pump(AppDurations.standard);
      await realTurnThenSettle(tester);
      await tester.tap(find.descendant(
        of: find.byType(ListView),
        matching: find.text('serenity'),
      ));
      await tester.pumpAndSettle();
      await settleDatabase(tester);
      expect(find.byType(WordDetailScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Popping the route puts `HomeScreen` back, and the shell had swapped it
      // out, so it mounts afresh and reads the pack again. Same reason as the
      // settle in the first group.
      await settleDatabase(tester);

      expect(find.byType(WordDetailScreen), findsNothing,
          reason: 'the pushed route popped');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(barIndex(tester), 0, reason: 'the bar never moved');
    });
  });

  group('the back button and a confirmation', () {
    testWidgets('cancels the dialog and stays on the tab', (tester) async {
      // **The bug the first attempt at this fix shipped.** The shell's `PopScope`
      // and the confirmation's own both veto the same route, and a blocked pop
      // fires *every* `PopEntry` on that route — so one press closed the dialog
      // *and* jumped the bar to Home. Measured, not assumed.
      //
      // Exactly one `PopScope` per destination is what prevents it, and that is
      // asserted here by the outcome: the dialog closes and `المزيد` is still
      // the bar's selection.
      await pumpShell(tester, harness.repository);
      await tester.tap(find.byIcon(Icons.apps));
      await tester.pumpAndSettle();
      await settleDatabase(tester);
      expect(find.byType(MoreScreen), findsOneWidget);

      final reset = find.widgetWithText(OutlinedButton, 'مسح التقدم');
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await settleDatabase(tester);
      expect(find.text('مسح التقدم؟'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('مسح التقدم؟'), findsNothing, reason: 'the dialog closed');
      expect(find.byType(MoreScreen), findsOneWidget,
          reason: 'and the tab did NOT jump to Home');
      expect(barIndex(tester), 3);

      // And back still works afterwards, now that the dialog is gone.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // The last press is a bar switch back to Home, which remounts `HomeScreen`
      // and its pack read. This is the last database-triggering action in the
      // body, so this is the settle that keeps the read out of the teardown.
      await settleDatabase(tester);

      expect(find.byType(HomeScreen), findsOneWidget,
          reason: 'the next back press goes Home, as it should');
    });
  });

  group('the home index', () {
    testWidgets('الرئيسية is the first destination in the bar', (tester) async {
      // `_homeIndex` in `lib/ui/home_shell.dart` is private, and widening a
      // constant's visibility so a test could compare it would be the wrong
      // reason to make it public. What matters is the agreement between that
      // constant and the bar, and **the bar is observable**: index 0 is the one
      // back returns to, and it is `الرئيسية`.
      //
      // A bar reordered without updating `_homeIndex` would send back to the
      // wrong tab, and the behavioural tests above would report it only as "back
      // landed on the wrong screen". This names the cause.
      await pumpShell(tester, harness.repository);

      final destinations = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .cast<NavigationDestination>();
      expect(destinations, hasLength(4));
      expect(destinations.first.label, 'الرئيسية',
          reason: 'the destination back returns to is index 0');
      expect(barIndex(tester), 0,
          reason: 'and the shell starts on it');
    });
  });
}