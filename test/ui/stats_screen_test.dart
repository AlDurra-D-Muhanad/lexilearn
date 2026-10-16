import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/stats/stats_controller.dart';
import 'package:lexilearn/ui/stats/stats_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../helpers/test_env.dart';

/// The chrome, in Arabic: the app is RTL end to end and the artwork's chrome is
/// Arabic. Every number on this screen is a Latin run and says so — see
/// `lib/ui/stats/stats_screen.dart`.
const _title = 'إحصائياتك';
const _loading = 'جارٍ التحميل…';
const _emptyHeadline = 'لا توجد إجابات بعد';
const _emptySupporting = 'أجب عن بعض الأسئلة وستظهر إحصائياتك هنا.';
const _loadFailed = 'تعذّر تحميل الإحصائيات.';
const _retry = 'إعادة المحاولة';
const _accuracyLabel = 'نسبة الدقة';
const _attemptsLabel = 'إجمالي الإجابات';
const _practisedLabel = 'كلمات تدربت عليها';
const _masteredLabel = 'كلمات أتقنتها';
const _recentHeading = 'آخر الجلسات';
const _noSessions = 'لا توجد جلسات بعد.';
const _reset = 'مسح التقدم';
const _resetTitle = 'مسح التقدم؟';
const _cancel = 'إلغاء';

/// Home's quick-launch tile, as `test/ui/home_screen_test.dart` spells it.
const _tileStats = 'إحصائياتك';

/// Two packs sharing the **same entry ids**, so only a `pack_key` filter can
/// tell their progress apart. See `stats_controller_test.dart` for why.
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

/// Everything inside the Stats screen and nothing outside it.
Finder inStats(String text) =>
    find.descendant(of: find.byType(StatsScreen), matching: find.text(text));

/// The card carrying [label] — one of the four stat tiles.
Finder statTile(String label) =>
    find.ancestor(of: inStats(label), matching: find.byType(AppSurface));

/// The value inside the tile carrying [label].
Finder statValue(String label, String value) =>
    find.descendant(of: statTile(label), matching: find.text(value));

/// The one card that holds the session history, heading and rows together.
Finder sessionsCard() => find.ancestor(
      of: inStats(_recentHeading),
      matching: find.byType(AppSurface),
    );

/// A ring drawn in [colour], found by its decoration rather than by its type.
///
/// The badge is a private widget, and a test that could name it would be coupled
/// to this screen's internal decomposition instead of to what it draws.
///
/// **The shape is load-bearing, and that is measured, not assumed.**
/// `AppSurface` is an `AnimatedContainer`, and `AnimatedContainer` is
/// implemented as an `AnimatedBuilder` whose child is a plain `Container` — so
/// *every card on the screen is itself a bordered `Container`* carrying the
/// surface fill and the brand hairline. Matching on colour alone therefore finds
/// each `AppSurface` as well as the badge, and `AppSurface` is what a card is
/// required to be (`every card is an AppSurface`). Verified at runtime by
/// printing the matched widgets' ancestors: a hairline match in a
/// three-session screen came back as `Container :: [AnimatedContainer,
/// AppSurface, _SessionsCard, …]` and `Container :: [_ScoreBadge, Row,
/// _SessionRow, …]`. The two are told apart by `BoxShape.circle`, which is the
/// one thing on this screen that is a ring rather than a card.
///
/// With the shape in the predicate the three expectations below are each
/// satisfied by a *session badge*, and the dark theme's hairline ring is the
/// accuracy track — the other circular bordered container, and the only one a
/// dark screen has when its one session is a perfect one.
Finder badgeRing(Color colour) => find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
          (widget.decoration! as BoxDecoration).border?.top.color == colour,
      description: 'a ring drawn in $colour',
    );

/// A tap, and then one real turn of the event loop.
///
/// Shared helpers, no private copy of the dance: a tap that reaches the database
/// needs the real event loop to land, and `settleDatabase` is exactly that turn.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settleDatabase(tester);
}

/// Confirms the reset dialog and waits for the re-read that follows it.
///
/// **A reset is two sequential database round trips**, not one:
/// `StatsController.reset()` awaits `resetProgress`'s transaction and *then*
/// calls `load()`, which issues its own query — and that second query is not
/// even issued until the first has answered. `settleDatabase` is one real turn
/// of the event loop, which covers one round trip and not reliably two when the
/// whole suite is running in parallel.
///
/// This was not theoretical. With a single settle, *confirming clears the tiles
/// and the session list together* failed on a full-suite run with
/// `Found 0 widgets with text "لا توجد إجابات بعد"` and passed every time the
/// file ran alone — the screen was still showing the pre-reset read, not a
/// failed reset.
///
/// Bounded, and it decides nothing: the assertions in the tests that call this
/// are what decide pass or fail. It only stops the test from reading the screen
/// before the screen's own read has landed.
Future<void> _confirmReset(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, _reset));
  for (var turn = 0; turn < 3; turn++) {
    await settleDatabase(tester);
  }
}

/// Writes to the database from inside a `testWidgets` body, **before** anything
/// is mounted.
///
/// `tester.runAsync` is what makes it complete at all: a `testWidgets` body runs
/// in a fake-async zone where a real sqflite future never answers. The write is
/// awaited inside `runAsync` rather than fired and delayed the way
/// `commitAndSettle` does, because there is no tree yet for those pumps to be
/// useful.
Future<void> _seed(
  WidgetTester tester,
  Future<void> Function() write,
) async {
  await tester.runAsync(write);
}

/// Sizes the surface like the phone the artwork is drawn on.
///
/// A thin alias for the shared `useAPhone`, kept only so this file's intent is
/// readable at the call site. The helper itself lives in
/// `test/helpers/test_env.dart` because `test/ui/home_screen_test.dart` needs
/// the identical thing — `إحصائياتك` is in the grid's second row, and on the
/// default 800×600 surface its centre resolves to `Offset(204.0, 865.4)`,
/// outside the root, where `tap` throws rather than scrolling.
void _useAPhone(WidgetTester tester) => useAPhone(tester);

/// The timestamp the screen renders for a session, built here rather than read
/// from the screen's own formatter — a test that reused the implementation would
/// agree with it whatever it formatted.
String _expectedWhen(DateTime startedAtUtc) {
  final local = startedAtUtc.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Mounts `StatsScreen` the way the app does: the brand theme, the app-wide RTL
/// direction, and the controller read from `provider`.
///
/// The controller is created and fired here rather than inside the screen, so a
/// test can also mount one that has *not* loaded yet. `HomeScreen` owns the real
/// one; see `the إحصائياتك tile opens Stats` for that path.
Future<void> _pumpStats(
  WidgetTester tester,
  VocabRepository repository, {
  String packKey = 'p',
  Brightness brightness = Brightness.light,
}) async {
  final controller =
      StatsController(repository: repository, packKey: packKey)..load();
  await tester.pumpWidget(
    _StatsApp(controller: controller, packKey: packKey, brightness: brightness),
  );
  await settleDatabase(tester);
}

class _StatsApp extends StatelessWidget {
  const _StatsApp({
    required this.controller,
    this.packKey = 'p',
    this.brightness = Brightness.light,
  });

  final StatsController controller;
  final String packKey;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StatsController>.value(
      value: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: StatsScreen(packKey: packKey),
      ),
    );
  }
}

void main() {
  late TestHarness harness;

  /// One test closes the harness itself to force a read to fail, and `tearDown`
  /// must not close it a second time.
  var closed = false;

  setUp(() async {
    closed = false;
    harness = await TestHarness.create(packs: <VocabPack>[_pack, _otherPack]);
  });

  tearDown(() async {
    if (!closed) await harness.dispose();
  });

  /// Records [attempts] right answers for [entryId] in [packKey].
  Future<void> answer(
    WidgetTester tester, {
    required String packKey,
    required String entryId,
    required int attempts,
  }) async {
    await _seed(tester, () async {
      for (var i = 0; i < attempts; i++) {
        await harness.repository.recordAnswer(
            packKey: packKey, entryId: entryId, wasCorrect: true);
      }
    });
  }

  /// Records one finished session.
  Future<void> session(
    WidgetTester tester, {
    required String packKey,
    required DateTime startedAt,
    required int totalQuestions,
    required int correctCount,
  }) async {
    await _seed(
      tester,
      () => harness.repository.finishSession(
        packKey: packKey,
        startedAt: startedAt,
        totalQuestions: totalQuestions,
        correctCount: correctCount,
      ),
    );
  }

  group('a fresh install', () {
    testWidgets('says so in words rather than showing a row of zeros',
        (tester) async {
      await _pumpStats(tester, harness.repository);

      expect(inStats(_title), findsOneWidget);
      expect(inStats(_emptyHeadline), findsOneWidget);
      expect(inStats(_emptySupporting), findsOneWidget);

      // Ruling 4: an install with zero sessions must not read as four zeros and
      // a 0%. Those numbers are indistinguishable from "you answered everything
      // wrong", which is not what happened.
      for (final label in <String>[
        _accuracyLabel,
        _attemptsLabel,
        _practisedLabel,
        _masteredLabel,
      ]) {
        expect(inStats(label), findsNothing, reason: '"$label" on an empty install');
      }
      expect(find.text('0'), findsNothing);
      expect(find.text('0%'), findsNothing);
      expect(inStats(_recentHeading), findsNothing);
    });

    testWidgets('offers no destructive action when there is nothing to reset',
        (tester) async {
      await _pumpStats(tester, harness.repository);

      // A reset button over an empty pack is an invitation to open a dialog that
      // has nothing to report.
      expect(find.text(_reset), findsNothing);
    });

    testWidgets('the loading state is a line, never a spinner', (tester) async {
      // An indeterminate `CircularProgressIndicator` schedules frames forever, so
      // `pumpAndSettle` never returns while one is on screen — which would hang
      // every test that pushes this screen. `quiz_screen.dart`'s
      // `_LoadingScreen` records the same decision for the same reason.
      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      await tester.pumpWidget(_StatsApp(controller: controller));
      await tester.pump();

      expect(find.text(_loading), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      // And it is replaced, not stacked under, once the read answers.
      await _seed(tester, controller.load);
      await tester.pumpAndSettle();
      expect(find.text(_loading), findsNothing);
    });
  });

  group('after answering', () {
    testWidgets('reports accuracy, answers, words practised and words mastered',
        (tester) async {
      // `a` reaches the mastery floor in `word_progress.dart` (5 attempts at
      // 80%+); `b` does not. 5 right, then 1 right and 1 wrong: 6 of 7.
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 5);
      await _seed(tester, () async {
        await harness.repository.recordAnswer(
            packKey: 'p', entryId: 'b', wasCorrect: true);
        await harness.repository.recordAnswer(
            packKey: 'p', entryId: 'b', wasCorrect: false);
      });

      await _pumpStats(tester, harness.repository);

      expect(statValue(_accuracyLabel, '86%'), findsOneWidget,
          reason: '6 of 7 is 85.7%, and it must round rather than truncate');
      expect(statValue(_attemptsLabel, '7'), findsOneWidget);
      expect(statValue(_practisedLabel, '2'), findsOneWidget);
      expect(statValue(_masteredLabel, '1'), findsOneWidget);
      expect(inStats(_emptyHeadline), findsNothing);
    });

    testWidgets('counts no other pack, even one holding the same word ids',
        (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 5);
      await answer(tester, packKey: 'other', entryId: 'a', attempts: 5);
      await answer(tester, packKey: 'other', entryId: 'b', attempts: 5);
      await answer(tester, packKey: 'other', entryId: 'c', attempts: 5);
      await session(
        tester,
        packKey: 'other',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 3,
        correctCount: 3,
      );

      await _pumpStats(tester, harness.repository, packKey: 'p');

      expect(statValue(_attemptsLabel, '5'), findsOneWidget,
          reason: 'the other pack has 15 attempts under the same word ids');
      expect(statValue(_practisedLabel, '1'), findsOneWidget);
      expect(find.text('3 / 3'), findsNothing,
          reason: 'another pack’s session under this pack’s tiles');
      // There are no sessions for `p` at all, so the section says so rather than
      // printing an empty list.
      expect(inStats(_noSessions), findsOneWidget);
    });

    testWidgets('lists the recent sessions newest first, with score and time',
        (tester) async {
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 13, 9),
        totalQuestions: 2,
        correctCount: 1,
      );
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 4,
        correctCount: 4,
      );

      await _pumpStats(tester, harness.repository);

      expect(inStats(_recentHeading), findsOneWidget);
      expect(inStats('4 / 4'), findsOneWidget);
      expect(inStats('1 / 2'), findsOneWidget);
      expect(
        inStats(_expectedWhen(DateTime.utc(2026, 10, 14, 12))),
        findsOneWidget,
      );

      // Newest first, asserted on geometry: both rows are on screen at once, so
      // the order is a layout fact rather than a list-index convention.
      expect(
        tester.getTopLeft(inStats('4 / 4')).dy,
        lessThan(tester.getTopLeft(inStats('1 / 2')).dy),
      );
      // Numerals are a Latin run, so they must not be reordered or refaced by the
      // app's direction.
      expect(tester.widget<Text>(find.text('4 / 4')).textDirection,
          TextDirection.ltr);
    });

    testWidgets('every card is an AppSurface and nothing is a bare Card',
        (tester) async {
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 4,
        correctCount: 4,
      );
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);

      await _pumpStats(tester, harness.repository);

      for (final label in <String>[
        _accuracyLabel,
        _attemptsLabel,
        _practisedLabel,
        _masteredLabel,
      ]) {
        expect(statTile(label), findsOneWidget, reason: '"$label" is not a card');
      }
      expect(
        find.ancestor(
            of: inStats(_recentHeading), matching: find.byType(AppSurface)),
        findsOneWidget,
      );
      // The other half of the same rule: a bare `Card` renders a hard black
      // keyline in this rasteriser, measured at 29,111 pixels once.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the accuracy number is in brand ink, never the accent',
        (tester) async {
      // `design_tokens.dart` permits the amber for icons and fills only.
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);

      await _pumpStats(tester, harness.repository);

      final style = tester.widget<Text>(inStats('100%')).style;
      expect(style?.color, AppColors.primaryLight);
      expect(style?.color, isNot(AppColors.accent));
      expect(style?.fontFamily, 'Inter',
          reason: 'a numeral run names the brand Latin explicitly');
    });

    testWidgets('a perfect session is ringed in success and a scoreless in error',
        (tester) async {
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 4,
        correctCount: 4,
      );
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 13, 12),
        totalQuestions: 4,
        correctCount: 0,
      );
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 12, 12),
        totalQuestions: 4,
        correctCount: 2,
      );

      await _pumpStats(tester, harness.repository);

      // Both are 2px rings rather than text: `#16A34A` on white measures 3.3:1,
      // which is over the 3:1 a border or an icon needs and under the 4.5:1 body
      // text needs. `quiz_screen.dart` measures and says the same about its own
      // answer rings.
      expect(badgeRing(AppColors.successLight), findsOneWidget);
      expect(badgeRing(AppColors.errorLight), findsOneWidget);
      // A half-right session is neither verdict, so it wears the brand hairline.
      // A "good enough" threshold invented here would be a rule with no evidence
      // behind it.
      expect(badgeRing(AppColors.borderLight), findsOneWidget);
    });

    testWidgets('the dark theme reaches the dark tokens', (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 4,
        correctCount: 4,
      );
      // A third session, half right. **The dark case used to be unverified:**
      // with only the perfect session above, the one `borderDark` ring in this
      // tree was the accuracy *track*, not a badge — so "neither verdict, so the
      // hairline" was asserted in light mode only. Measured: mutating
      // `_ScoreBadge`'s `neutral` from `borderDark` to `successDark` left all 17
      // tests green. This session is what makes the badge's dark colour
      // load-bearing, and the scoped assertion below is what catches it.
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 13, 12),
        totalQuestions: 4,
        correctCount: 2,
      );

      await _pumpStats(tester, harness.repository, brightness: Brightness.dark);

      expect(badgeRing(AppColors.successDark), findsOneWidget,
          reason: 'the one perfect session');
      // Unscoped: two hairline rings, the accuracy track and the half-right
      // badge. Before the third session this read 1, and that 1 was the track —
      // which is exactly why the mutation below left everything green.
      expect(badgeRing(AppColors.borderDark), findsNWidgets(2),
          reason: 'the accuracy track and the one session that is neither');
      // Scoped to the history card, so it can only be the badge.
      expect(
        find.descendant(
            of: sessionsCard(), matching: badgeRing(AppColors.borderDark)),
        findsOneWidget,
        reason: 'a session that is neither perfect nor scoreless wears the dark '
            'hairline too, and that is the case light mode already covered',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reset action is a full-width pill in the error colour',
        (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);

      await _pumpStats(tester, harness.repository);

      final button = find.widgetWithText(OutlinedButton, _reset);
      expect(button, findsOneWidget);
      final style = tester.widget<OutlinedButton>(button).style!;
      expect(style.shape?.resolve(<WidgetState>{}), isA<StadiumBorder>());
      expect(style.foregroundColor?.resolve(<WidgetState>{}), AppColors.errorLight);

      // Full width, measured on the button box: the artwork's actions run the
      // width of the content column.
      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
      expect(tester.getSize(button).width,
          closeTo(screenWidth - 2 * AppSpacing.m, 0.5));
      expect(tester.getSize(button).width, greaterThan(screenWidth * 0.9));
    });

    testWidgets('a dark screen uses the dark error colour for that pill',
        (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);

      await _pumpStats(tester, harness.repository, brightness: Brightness.dark);

      final style = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, _reset))
          .style!;
      expect(style.foregroundColor?.resolve(<WidgetState>{}), AppColors.errorDark);
    });
  });

  group('a failed read', () {
    testWidgets('says so, and does not claim the pack is empty', (tester) async {
      final controller =
          StatsController(repository: harness.repository, packKey: 'p');
      await tester.pumpWidget(_StatsApp(controller: controller));
      await tester.pump();

      // Close the database underneath the repository, so the read that follows
      // is the one that fails. `VocabRepository` is concrete and the data layer
      // underneath it is the thing being tested, so this is the honest fault.
      //
      // `readOutsideFakeAsync` on the close, not a bare `await`: a `testWidgets`
      // body runs in a fake-async zone where a real sqflite future never
      // answers, and this one is a real close. Awaited bare it does not fail —
      // it hangs to the ten-minute timeout, which is what it did before this
      // line was wrapped.
      closed = true;
      await readOutsideFakeAsync(tester, harness.dispose);
      await readOutsideFakeAsync(tester, () => controller.load());
      await tester.pumpAndSettle();

      expect(inStats(_loadFailed), findsOneWidget);
      expect(inStats(_emptyHeadline), findsNothing,
          reason: 'a broken read is not a fresh install');
      expect(find.text(_retry), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('resetting', () {
    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);
      await _pumpStats(tester, harness.repository);

      await _tap(tester, find.text(_reset));

      expect(inStats(_resetTitle), findsOneWidget);
      // **Two, not one, and the count is the assertion.** The same file
      // requires the screen's action to be an `OutlinedButton` labelled
      // `_reset` and the dialog's confirmation to be a `FilledButton` labelled
      // `_reset` (`confirming clears the tiles…` taps `widgetWithText(
      // FilledButton, _reset)`), so while the dialog is open that string is
      // necessarily on screen twice. Measured: the failure before this line was
      // "Found 2 widgets with text \"مسح التقدم\"".
      //
      // `findsNWidgets(2)` still says exactly what the original reason claimed —
      // one is the screen behind, one is the dialog's confirm — and it fails in
      // both directions. Had the dialog replaced the body the count would be 1;
      // had the dialog lost its confirm it would be 1 again.
      expect(find.text(_reset), findsNWidgets(2),
          reason: 'one behind the dialog, one on its confirmation');

      await _tap(tester, find.widgetWithText(TextButton, _cancel));

      expect(inStats(_resetTitle), findsNothing);
      expect(inStats(_emptyHeadline), findsNothing);
      expect(statValue(_attemptsLabel, '2'), findsOneWidget);
    });

    testWidgets(
        'the system back cancels the confirmation rather than leaving the '
        'screen', (tester) async {
      // This pins the behaviour `_ConfirmLayer`'s doc used to claim and the
      // code did not have. Measured before the `PopScope` was added, with the
      // confirmation open on a pushed `StatsScreen`:
      // `tester.binding.handlePopRoute()` returned `true`, the `StatsScreen`
      // count went to 0 and the host route came back. Back left the screen
      // mid-confirmation.
      //
      // It is mounted through `pumpShell` rather than `_StatsApp` on purpose:
      // `handlePopRoute` is about the *navigator*, and `_StatsApp` mounts
      // `StatsScreen` as `MaterialApp.home`, which has no route underneath to
      // come back to — the measurement above was taken on the pushed one.
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);
      _useAPhone(tester);
      await pumpShell(tester, harness.repository);

      await tester.tap(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.text(_tileStats),
      ));
      await tester.pumpAndSettle();
      await settleDatabase(tester);
      expect(find.byType(StatsScreen), findsOneWidget);

      // Open the confirmation, so the assertion below is about a pop *while a
      // destructive confirmation is up* and not about popping the screen.
      await _tap(tester, find.text(_reset));
      expect(inStats(_resetTitle), findsOneWidget);

      // Blocked, so the route stays and the screen is still there.
      //
      // **The return value does not say the route popped, and is not asserted
      // as if it did.** `NavigatorState.maybePop` returns `true` for
      // `RoutePopDisposition.doNotPop` as well as for a real pop — it means
      // "the pop was handled", and being blocked on purpose counts as handled.
      // Asserting `isFalse` here fails on correct code; the measurement that
      // actually distinguishes the two behaviours is whether `StatsScreen` is
      // still in the tree, which is the first assertion below. Verified: with
      // this `PopScope` in place `handlePopRoute()` returns `true` and the
      // screen survives; without it, it also returns `true` and the screen is
      // gone.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue,
          reason: 'the pop was handled — by being blocked, not by navigating');
      expect(find.byType(StatsScreen), findsOneWidget,
          reason: 'the route did not pop; back did not navigate away');
      // Cancelled, not ignored: a back button that does nothing at all is its
      // own defect, and this is the behaviour the `PopScope` callback exists
      // for.
      expect(inStats(_resetTitle), findsNothing,
          reason: 'back dismissed the confirmation rather than being swallowed');
      // And it reset nothing.
      expect(statValue(_attemptsLabel, '2'), findsOneWidget);
    });

    testWidgets('confirming clears the tiles and the session list together',
        (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);
      await session(
        tester,
        packKey: 'p',
        startedAt: DateTime.utc(2026, 10, 14, 12),
        totalQuestions: 2,
        correctCount: 2,
      );
      await _pumpStats(tester, harness.repository);
      expect(inStats('2 / 2'), findsOneWidget);

      await _tap(tester, find.text(_reset));
      await _confirmReset(tester);

      expect(inStats(_resetTitle), findsNothing);
      // Both halves, because a reset that zeroed the tiles and left the history
      // standing is exactly what the user would read as "Reset did nothing".
      expect(inStats(_emptyHeadline), findsOneWidget);
      expect(inStats('2 / 2'), findsNothing);
      expect(find.text(_reset), findsNothing,
          reason: 'nothing left to reset, so no destructive action is offered');

      final stats = await readOutsideFakeAsync(
          tester, () => harness.repository.stats('p'));
      expect(stats.totalAttempts, 0);
      expect(stats.recentSessions, isEmpty);
    });

    testWidgets('leaves another pack’s progress alone', (tester) async {
      await answer(tester, packKey: 'p', entryId: 'a', attempts: 2);
      await answer(tester, packKey: 'other', entryId: 'a', attempts: 3);
      await _pumpStats(tester, harness.repository, packKey: 'p');

      await _tap(tester, find.text(_reset));
      await _confirmReset(tester);

      final other = await readOutsideFakeAsync(
          tester, () => harness.repository.stats('other'));
      expect(other.totalAttempts, 3);
    });
  });

  group('reached from Home', () {
    testWidgets('the إحصائياتك tile opens Stats and leaves the bar where it was',
        (tester) async {
      // Ruling 1: statistics is a Home tile, not a bar destination. The artwork's
      // bar draws exactly four items — الرئيسية, البطاقات, الاختبارات, المزيد —
      // and statistics is not among them.
      //
      // The surface is sized first: on the default 800×600 the tile is in the
      // grid's second row and therefore off-screen, and `tap` throws rather than
      // scrolling to it. See [_useAPhone].
      _useAPhone(tester);
      await pumpShell(tester, harness.repository);

      await tester.tap(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.text(_tileStats),
      ));
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(find.byType(StatsScreen), findsOneWidget);
      expect(inStats(_emptyHeadline), findsOneWidget);
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
        reason: 'statistics is not a bottom-bar destination',
      );
      expect(find.byType(MoreScreen, skipOffstage: false), findsNothing,
          reason: 'المزيد is a different destination, not a stand-in for stats');
    });
  });
}