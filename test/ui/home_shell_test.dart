import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/flashcards/flashcards_screen.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_setup_screen.dart';

import '../helpers/test_env.dart';

/// One bottom-bar destination: the screen the bar must land on, the Arabic
/// label it draws, and the icon the bar declares for it.
///
/// The icon is part of the contract, not decoration. Tapping by icon means a
/// renamed or reordered destination fails the lookup loudly instead of silently
/// testing nothing.
class _Destination {
  const _Destination({
    required this.screen,
    required this.label,
    required this.icon,
  });

  final Type screen;
  final String label;
  final IconData icon;
}

/// The brand's four destinations, in bar order — exactly the four the artwork
/// draws, with no `المفضلة`.
///
/// Favourites is a shipped feature, not a tab: it is pushed from the `المفضلة`
/// tile in Home's 2×2 grid and from the heart on the word detail screen, which
/// is the artwork's own way in. `test/helpers/test_env.dart` and
/// `docs/design/style-direction.md` → Navigation record the same.
///
/// Count pinned by `hasLength(4)` below, not by this list's own length, so
/// dropping a destination cannot quietly make the length assertions pass.
const _destinations = <_Destination>[
  _Destination(screen: HomeScreen, label: 'الرئيسية', icon: Icons.home_outlined),
  _Destination(screen: FlashcardsScreen, label: 'البطاقات', icon: Icons.style_outlined),
  _Destination(screen: QuizSetupScreen, label: 'الاختبارات', icon: Icons.check_box_outlined),
  _Destination(screen: MoreScreen, label: 'المزيد', icon: Icons.apps),
];

/// Mounts the app and lets the shell's start-up database read actually answer.
///
/// The pumping itself is shared — see `pumpShell` in
/// `test/helpers/test_env.dart`, and the one-line reason `runAsync` is required
/// there. This wrapper exists only to hand it the harness under test.
Future<void> _pumpShell(WidgetTester tester, TestHarness harness) =>
    pumpShell(tester, harness.repository);

/// A tap on a bottom-bar destination, and enough waiting for what it reads.
///
/// `settleDatabase` is not decoration here and it is **required** for `المزيد`,
/// because that screen reads SQLite from `initState` — the pack list and the
/// active pack's figures. `pumpAndSettle` alone cannot deliver them: a
/// `testWidgets` body runs in a fake-async zone where a real sqflite future never
/// answers, and before this the body ended with the read still in flight, which
/// the binding reports as `Pending timers: … PackDao.listPacks` and counts as a
/// failure.
///
/// This is the pattern `test/helpers/test_env.dart` names for exactly this
/// situation — "a destination or widget that mounts its own read needs only
/// this" — added in Task 13, when `MoreScreen` became the first destination to
/// mount a read of its own after `pumpShell` had already returned.
Future<void> _openDestination(WidgetTester tester, Finder icon) async {
  await tester.tap(icon);
  await tester.pumpAndSettle();
  await settleDatabase(tester);
}

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[
      VocabPack(
        schemaVersion: 1,
        packId: 'en_ar',
        title: 'English to Arabic',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: const [],
      ),
    ]);
  });

  tearDown(() => harness.dispose());

  testWidgets('opens on Home and can reach every destination', (tester) async {
    await _pumpShell(tester, harness);

    // The shell resolves the active pack once at start-up and hands the key to
    // every destination. Asserting that key on every screen is what proves the
    // shell threads state around rather than merely swapping four widgets.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.text('en_ar'), findsOneWidget);

    for (final destination in _destinations.skip(1)) {
      await _openDestination(tester, find.byIcon(destination.icon));

      expect(
        find.byType(destination.screen),
        findsOneWidget,
        reason: 'tapping ${destination.icon} did not reach ${destination.screen}',
      );
      expect(find.text(destination.label), findsWidgets);
      expect(
        find.text('en_ar'),
        findsOneWidget,
        reason: '${destination.screen} was handed no active pack',
      );
    }
  });

  testWidgets('has one screen per bottom destination', (tester) async {
    await _pumpShell(tester, harness);

    // The bottom bar indexes straight into the screen list. If these lengths
    // ever diverge, tapping the last destination throws a range error at
    // runtime and nothing catches it until someone holds the phone. Four, per
    // the artwork — never five.
    expect(_destinations, hasLength(4));

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    // `NavigationBar.destinations` is typed `List<Widget>`; the cast is what
    // makes the label and icon assertions below compile, and it fails loudly
    // if something other than a `NavigationDestination` ever lands in the bar.
    final destinations = bar.destinations.cast<NavigationDestination>();
    expect(destinations, hasLength(4));
    expect(
      destinations.map((destination) => destination.label).toList(),
      _destinations.map((destination) => destination.label).toList(),
      reason: 'bar order drifted from the screen order',
    );
    for (var index = 0; index < _destinations.length; index++) {
      expect(
        (destinations[index].icon as Icon).icon,
        _destinations[index].icon,
        reason: 'destination ${index + 1} ("${_destinations[index].label}") '
            'draws the wrong icon',
      );
      expect(destinations[index].selectedIcon, isNotNull);
    }

    for (final destination in _destinations) {
      // Scoped to the bar on purpose: each screen draws its own Arabic title,
      // which is the same string as its nav label, so an unscoped `find.text`
      // would match two widgets and `tap` would throw instead of navigating.
      final label = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(destination.label),
      );
      expect(label, findsOneWidget);
      await _openDestination(tester, label);

      expect(
        tester.takeException(),
        isNull,
        reason: 'tapping "${destination.label}" threw',
      );
      expect(
        find.byType(destination.screen),
        findsOneWidget,
        reason: 'the bar index for "${destination.label}" does not match screens',
      );
    }
  });
}
