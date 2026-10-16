import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/quiz_question.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_controller.dart';
import 'package:lexilearn/ui/quiz/quiz_result_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_setup_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../helpers/test_env.dart';

/// Four words, so every question has exactly four options.
const VocabPack _pack = VocabPack(
  schemaVersion: 1,
  packId: 'p',
  title: 'P',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'a', term: 'alpha', translations: <String>['ألف']),
    VocabEntry(id: 'b', term: 'beta', translations: <String>['بيتا']),
    VocabEntry(id: 'c', term: 'gamma', translations: <String>['جاما']),
    VocabEntry(id: 'd', term: 'delta', translations: <String>['دلتا']),
  ],
);

/// A second installed pack, so the picker has something to switch *to*.
///
/// Three words, so the two labels the picker draws differ in their entry count as
/// well as their title — a test that only looked for the title could pass while
/// the field was still showing the other pack's row.
const VocabPack _secondPack = VocabPack(
  schemaVersion: 1,
  packId: 'q',
  title: 'Second',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'x', term: 'xray', translations: <String>['إكس']),
    VocabEntry(id: 'y', term: 'yoga', translations: <String>['يوغا']),
    VocabEntry(id: 'z', term: 'zinc', translations: <String>['زنك']),
  ],
);

/// The picker labels, spelled out rather than interpolated into the assertions.
const String _packTitle = 'P';
const int _packEntries = 4;
const String _secondTitle = 'Second';
const int _secondEntries = 3;

/// The chrome these tests assert on.
///
/// Copied here rather than imported, because the screens keep their strings
/// private and a test that reached into a screen's private constants could not
/// fail for the reason it exists. Arabic, because the artwork's chrome is Arabic
/// and the app is RTL end to end.
const String _next = 'التالي';
const String _finish = 'إنهاء';
const String _correctBanner = 'إجابة صحيحة';
const String _wrongBanner = 'إجابة خاطئة';
const String _advanceToSetup = 'العودة إلى الإعداد';
const String _startQuiz = 'ابدأ الاختبار';
const String _lengthError = 'أدخل رقمًا صحيحًا، مثل 10';
const String _lengthCap = 'الحد الأقصى 200 سؤال في الجلسة';

void main() {
  late TestHarness harness;
  late QuizController controller;

  /// A controller over a pack that is not installed, so its first read answers
  /// with nothing and the session is over before it starts.
  late QuizController empty;

  /// A second install, used only by the picker test, which needs a pack to switch
  /// *to*. Opened once in `setUpAll` rather than per test: opening a database is
  /// a real async round trip, and a `testWidgets` body runs in a fake-async zone
  /// where that never completes — a test that opened its own hung until the
  /// ten-minute timeout. It is deliberately **not** the per-test harness: two
  /// installed packs make `HomeShell` resolve whichever `listPacks` orders first,
  /// and the setup-flow tests assert on sessions recorded under `p`.
  late TestHarness twoPacks;

  setUpAll(() async {
    twoPacks = await TestHarness.create(packs: <VocabPack>[_pack, _secondPack]);
  });

  tearDownAll(() => twoPacks.dispose());

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[_pack]);
    controller = QuizController(
      repository: harness.repository,
      packKey: 'p',
      questionCount: 2,
      random: Random(4),
    );
    empty = QuizController(
      repository: harness.repository,
      packKey: 'no-such-pack',
      questionCount: 3,
      random: Random(1),
    );
    // Both controllers are **started here**, not in the test bodies. A
    // `testWidgets` body runs inside a fake-async zone in which a real `Future`
    // never completes on its own, so `start()`'s pack read would never answer
    // and every test would sit there until the ten-minute timeout — which is
    // what happened before this moved. `setUp` runs outside that zone, and
    // `pumpShell` documents the same trap from the shell's side.
    await controller.start();
    await empty.start();
  });

  tearDown(() => harness.dispose());

  Future<void> pumpQuiz(WidgetTester tester) async {
    await tester.pumpWidget(_QuizApp(controller: controller));
    await _settle(tester);
  }

  Finder optionText(QuizQuestion question, int index) =>
      find.text(question.options[index].text);

  /// The controller behind the screen under test.
  ///
  /// Read from the tree rather than captured, because the setup screen builds
  /// and owns its own: a test that answered through the outer controller would
  /// be grading a screen nobody is looking at.
  QuizController controllerOf(WidgetTester tester) => Provider.of<QuizController>(
        tester.element(find.byType(QuizScreen)),
        listen: false,
      );

  testWidgets('shows the asked term and four options', (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;

    expect(find.text(question.answer.term), findsOneWidget);
    expect(question.options, hasLength(4));
    for (var i = 0; i < question.options.length; i++) {
      expect(optionText(question, i), findsOneWidget);
    }
  });

  testWidgets('the options are four full-width stacked rows, not lettered chips',
      (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;

    // The artwork draws a full-width option button per answer. A row of lettered
    // chips would put all four at the same height, and would put a letter on the
    // screen; both are pinned here because the lettering is exactly the reading
    // this task had to rule out.
    final centres = <double>[
      for (var i = 0; i < question.options.length; i++)
        tester.getCenter(optionText(question, i)).dy,
    ];
    expect(centres, orderedEquals(<double>[...centres]..sort()));
    expect(centres.toSet(), hasLength(4));
    for (final letter in <String>['A', 'B', 'C', 'D']) {
      expect(find.text(letter), findsNothing, reason: 'a "$letter" chip is back');
    }

    // …and *full-width* is the other half of the claim, so it is measured rather
    // than assumed. The screen's own `EdgeInsets.symmetric(horizontal: AppSpacing.m)`
    // is the only inset between a row and the edge, so every option is exactly as
    // wide as the question card above it — and that card is nearly the whole
    // screen, which is what stops the equality passing for a narrow column.
    //
    // Measuring the `InkWell` rather than the text matters: the text is as wide
    // as the word, which a chip layout would satisfy too.
    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    final expectedWidth = screenWidth - 2 * AppSpacing.m;
    for (var i = 0; i < question.options.length; i++) {
      // The *button*, not the `InkWell` inside it: measured, the InkWell comes
      // out 2px narrower than the box it is in, and the box is what the artwork
      // draws and what the user aims at. Measured on the button box, each option
      // is the screen less the screen's own `AppSpacing.m` inset on both sides.
      final button = find.ancestor(
        of: optionText(question, i),
        matching: find.byType(AnimatedContainer),
      );
      expect(button, findsOneWidget, reason: 'option $i is not a button');
      expect(tester.getSize(button).width, closeTo(expectedWidth, 0.5),
          reason: 'option $i is not full-width');
      // …and the floor, so the equality above cannot be satisfied by a column
      // that is narrow on both screens.
      expect(tester.getSize(button).width, greaterThan(screenWidth * 0.9),
          reason: 'option $i is not full-width');
    }
  });

  testWidgets('the advance button is disabled until an option is tapped', (tester) async {
    await pumpQuiz(tester);

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, _next));
    expect(button.onPressed, isNull);
  });

  testWidgets('a correct answer is confirmed and advances', (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;

    await _tap(tester, optionText(question, question.correctIndex));

    expect(find.text(_correctBanner), findsOneWidget);
    expect(find.textContaining(_wrongBanner), findsNothing);
    expect(controller.correctCount, 1);
    expect(controller.answeredCount, 1);

    await _tap(tester, find.widgetWithText(FilledButton, _next));
    expect(controller.answeredCount, 1);
    expect(controller.isFinished, isFalse);
    expect(controller.question, isNotNull);
  });

  testWidgets('the correct option is marked in the brand success colour', (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;

    expect(find.byIcon(Icons.check_circle), findsNothing);
    await _tap(tester, optionText(question, question.correctIndex));

    // `AppColors.successLight`, not `colorScheme.primary`: the answer to "was
    // that right" must not change colour between light and dark. Asserted, not
    // assumed — the plan's own draft used the theme's primary.
    final check = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(check.color, AppColors.successLight);
    expect(find.byIcon(Icons.cancel), findsNothing);
  });

  testWidgets('a wrong answer reveals the correct translation', (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;

    await _tap(tester, optionText(question, _firstWrongIndex(question)));

    expect(find.text(_correctBanner), findsNothing);
    expect(find.textContaining(_wrongBanner), findsOneWidget);
    expect(find.textContaining(question.answer.displayText), findsWidgets);
    // The right option is marked too: the user has to see what they were being
    // offered, not only what they picked.
    final cancel = tester.widget<Icon>(find.byIcon(Icons.cancel));
    expect(cancel.color, AppColors.errorLight);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(controller.correctCount, 0);
  });

  testWidgets('a second tap cannot change the recorded answer', (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;

    // Tapped through the widget tree, so this pins `_OptionTile`'s guard: it
    // nulls its `onTap` once answered, and that is the layer a finger reaches.
    await _tap(tester, optionText(question, question.correctIndex));
    await _tap(tester, optionText(question, 0));

    expect(controller.answeredCount, 1);
    expect(controller.correctCount, 1);

    // Read through `runAsync` rather than awaited directly: this is a real
    // SQLite round trip, and a `testWidgets` body runs in a fake-async zone
    // where a real `Future` never completes on its own — awaited bare, the test
    // would sit until the ten-minute timeout instead of failing. The same trap
    // `pumpShell` documents, met with the same one call.
    final stats = (await tester.runAsync(() => harness.repository.stats('p')))!;
    expect(stats.totalAttempts, 1);
  });

  testWidgets('answering twice through the controller is one answer and one row',
      (tester) async {
    await pumpQuiz(tester);
    final question = controller.question!;
    final wrong = _firstWrongIndex(question);
    final pushed = controllerOf(tester);

    // **The controller's own guard, not the tile's.** Driven through the object
    // the screen is watching, so `_OptionTile`'s nulled `onTap` is bypassed:
    // delete `if (_selectedIndex != null) return` from `QuizController.answer`
    // and the test above still passes, while this one goes red. The Python
    // original re-read its file on every keystroke, so one question scored twice
    // — once from the widget, once from here.
    //
    // Fired and not awaited, because that is what `_OptionTile`'s `onTap` does
    // and because `answer` awaits a database write: awaiting it in a
    // fake-async zone never completes. The writes are given a real turn below,
    // before the row count is read.
    unawaited(pushed.answer(question.correctIndex));
    await tester.pumpAndSettle();
    unawaited(pushed.answer(wrong));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
    await tester.pumpAndSettle();

    expect(pushed.answeredCount, 1);
    expect(pushed.correctCount, 1);
    // The first answer is still the one held: the second call did not move it.
    expect(pushed.isSelectedOption(question.correctIndex), isTrue);
    expect(pushed.isSelectedOption(wrong), isFalse);

    final stats = (await tester.runAsync(() => harness.repository.stats('p')))!;
    expect(stats.totalAttempts, 1);
    expect(stats.totalCorrect, 1);
  });

  testWidgets('the final advance shows the result screen', (tester) async {
    await pumpQuiz(tester);

    for (var i = 0; i < 2; i++) {
      final question = controller.question!;
      await _tap(tester, optionText(question, question.correctIndex));
      await _tap(tester, find.widgetWithText(FilledButton, i == 1 ? _finish : _next));
    }

    expect(controller.isFinished, isTrue);
    expect(find.byType(QuizResultScreen), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.textContaining('100%'), findsOneWidget);
  });

  testWidgets('the result screen counts right answers over answered ones', (tester) async {
    await pumpQuiz(tester);

    var question = controller.question!;
    await _tap(tester, optionText(question, question.correctIndex));
    await _tap(tester, find.widgetWithText(FilledButton, _next));

    question = controller.question!;
    await _tap(tester, optionText(question, _firstWrongIndex(question)));
    await _tap(tester, find.widgetWithText(FilledButton, _finish));

    // Half the answers were right. The session was 100% *complete*, which is the
    // number the plan's result screen printed as a percentage correct.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
  });

  testWidgets('the quiz screen draws no bare Card', (tester) async {
    await pumpQuiz(tester);

    // A `Card` under this rasteriser strokes out as an opaque black keyline —
    // 29,111 pixels of it the last time it was measured. Every surface here is
    // an `AppSurface` or the brand decoration composed locally.
    expect(find.byType(Card), findsNothing);
    expect(find.byType(AppSurface), findsWidgets);
  });

  testWidgets('the quiz screen survives a dark theme', (tester) async {
    await tester.pumpWidget(_QuizApp(controller: controller, brightness: Brightness.dark));
    await _settle(tester);
    final question = controller.question!;

    await _tap(tester, optionText(question, _firstWrongIndex(question)));

    expect(tester.takeException(), isNull);
    // Both verdicts still read, in the brand's own tokens.
    expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).color, AppColors.successLight);
    expect(tester.widget<Icon>(find.byIcon(Icons.cancel)).color, AppColors.errorLight);
    expect(find.textContaining(_wrongBanner), findsOneWidget);
  });

  testWidgets('an empty pack lands on the result screen rather than throwing',
      (tester) async {
    await tester.pumpWidget(_QuizApp(controller: empty));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(QuizResultScreen), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget);
  });

  testWidgets('the setup screen rejects a zero length and explains why', (tester) async {
    await _openSetup(tester, harness.repository);

    await tester.enterText(find.byType(TextField), '0');
    await _tap(tester, find.widgetWithText(FilledButton, _startQuiz));

    expect(find.textContaining(_lengthError), findsOneWidget);
    expect(find.byType(QuizScreen), findsNothing);
  });

  testWidgets('the setup screen rejects a length over the cap', (tester) async {
    await _openSetup(tester, harness.repository);

    await tester.enterText(find.byType(TextField), '500');
    await _tap(tester, find.widgetWithText(FilledButton, _startQuiz));

    expect(find.textContaining(_lengthCap), findsOneWidget);
    expect(find.byType(QuizScreen), findsNothing);
  });

  testWidgets('the setup screen rejects an empty length', (tester) async {
    await _openSetup(tester, harness.repository);

    // The third bad answer the original could be given. `Search.py` re-prompted
    // by recursing — `return loop()` after an `isdigit()` failure — so the third
    // mistake blew the stack. Here there is no recursion to blow: `_start` is a
    // `void` with an early return per failure, so the *same* message the `0`
    // case shows is what an empty field shows, and the tap is simply refused.
    await tester.enterText(find.byType(TextField), '');
    await _tap(tester, find.widgetWithText(FilledButton, _startQuiz));

    expect(find.textContaining(_lengthError), findsOneWidget);
    expect(find.byType(QuizScreen), findsNothing);
  });

  testWidgets('the setup screen offers one-tap lengths', (tester) async {
    await _openSetup(tester, harness.repository);

    await _tap(tester, find.widgetWithText(ActionChip, '20'));

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '20');
    expect(find.textContaining(_lengthError), findsNothing);
  });

  testWidgets('the setup screen starts a quiz of the requested length', (tester) async {
    await _openSetup(tester, harness.repository);

    await tester.enterText(find.byType(TextField), '2');
    await _tap(tester, find.widgetWithText(FilledButton, _startQuiz));

    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, _next), findsOneWidget);
  });

  testWidgets('the result screen returns to setup', (tester) async {
    await _openSetup(tester, harness.repository);
    await tester.enterText(find.byType(TextField), '1');
    await _tap(tester, find.widgetWithText(FilledButton, _startQuiz));

    // Driven through the screen's own controller, which the setup screen built.
    final pushed = controllerOf(tester);
    final question = pushed.question!;
    await _tap(tester, optionText(question, question.correctIndex));
    await _tap(tester, find.widgetWithText(FilledButton, _finish));
    expect(find.byType(QuizResultScreen), findsOneWidget);

    await _tap(tester, find.widgetWithText(FilledButton, _advanceToSetup));

    expect(find.byType(QuizSetupScreen), findsOneWidget);
    expect(find.byType(QuizResultScreen), findsNothing);

    // And the session the pushed screen ran is on disk, not in the widget tree.
    // Through `runAsync`, for the same fake-async reason as the read above.
    final stats = (await tester.runAsync(() => harness.repository.stats('p')))!;
    expect(stats.recentSessions, hasLength(1));
  });

  testWidgets('the picker reports the pack the user chooses', (tester) async {
    // The one part of this destination with no coverage at all: nothing in the
    // suite opened the dropdown, so `onChanged`, its `value != packKey` guard and
    // the `ValueKey` that re-keys the field on a pack switch were all unexercised.
    // Mounted against a host that owns the active key exactly as `HomeShell`
    // does, because a host that only records the call would prove the callback
    // fires and nothing about what the screen does next.
    final two = twoPacks;
    final selected = <String>[];

    await tester.pumpWidget(_SetupApp(
      repository: two.repository,
      selected: selected,
    ));
    await _settle(tester);

    // The field opens on the pack it was handed, named.
    expect(find.text('$_packTitle ($_packEntries)'), findsOneWidget);
    expect(find.text('p'), findsOneWidget);

    await _tap(tester, find.byType(DropdownButton<String>));
    await _tap(tester, find.text('$_secondTitle ($_secondEntries)').last);

    // 1. `onChanged` fired, carrying the key the screen was handed…
    expect(selected, <String>['q']);
    // 2. …the host rebuilt, so the field shows the pack that was chosen…
    expect(find.text('$_secondTitle ($_secondEntries)'), findsOneWidget);
    // …and so does the pill, which is drawn from the same key the quiz would
    // draw from. Without the `ValueKey`, `initialValue` is read once and this
    // would still read 'P (4)'.
    expect(find.text('q'), findsOneWidget);
    expect(find.text('p'), findsNothing);

    // 3. Re-choosing the pack that is already active must not report it again:
    //    the guard is what stops a no-op tap from resetting the whole app's
    //    pack behind the user's back.
    await _tap(tester, find.byType(DropdownButton<String>));
    await _tap(tester, find.text('$_secondTitle ($_secondEntries)').last);

    expect(selected, <String>['q'],
        reason: 're-picking the active pack reported a pack switch');
  });

  testWidgets('the Home tab does not build the quiz screen', (tester) async {
    // The committed golden renders the Home tab alone, and the shell builds one
    // destination at a time. This is what keeps that PNG valid across this task.
    await pumpShell(tester, harness.repository);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(QuizSetupScreen), findsNothing);
  });
}

/// Mounts `QuizSetupScreen` the way the shell does — the brand theme, the
/// app-wide RTL direction, the repository from `provider` — over a host that owns
/// the active pack key exactly as `HomeShell` does.
///
/// The host is the point. `QuizSetupScreen` cannot change the pack itself; it
/// reports the choice and the shell rebuilds it. A host that only recorded the
/// callback would prove the `onChanged` wiring and nothing about the re-keying,
/// which is half of what had no coverage.
class _SetupApp extends StatelessWidget {
  const _SetupApp({required this.repository, required this.selected});

  final VocabRepository repository;

  /// Every pack key the screen reported, in order.
  final List<String> selected;

  @override
  Widget build(BuildContext context) {
    return Provider<VocabRepository>.value(
      value: repository,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: _SetupHost(selected: selected),
      ),
    );
  }
}

class _SetupHost extends StatefulWidget {
  const _SetupHost({required this.selected});

  final List<String> selected;

  @override
  State<_SetupHost> createState() => _SetupHostState();
}

class _SetupHostState extends State<_SetupHost> {
  /// `HomeShell` starts from the first installed pack; the harness installs `p`
  /// first, so this is the same starting state the real app reaches.
  String _packKey = 'p';

  @override
  Widget build(BuildContext context) {
    return QuizSetupScreen(
      packKey: _packKey,
      onPackSelected: (packKey) {
        widget.selected.add(packKey);
        setState(() => _packKey = packKey);
      },
    );
  }
}

/// A tap, and then one real turn of the event loop.
///
/// A tap runs the controller's synchronous half inside the test's fake-async
/// zone, so the pixels the user sees are already right by the time
/// `pumpAndSettle` returns — but the repository write that follows it can only
/// complete on the real loop. Without this turn those writes are still in flight
/// when the harness closes its database in `tearDown`. This is the one-line
/// reason `pumpShell` exists, for the screens this file mounts itself.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// One real turn of the event loop, for a read that was issued rather than
/// awaited — a `FutureBuilder`, or a controller `start()` already in flight.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(shellDatabaseSettle));
  await tester.pumpAndSettle();
}

/// Opens the quiz destination through the shell.
///
/// `pumpShell` is the shared helper and it is not copied here: what this adds is
/// the read the destination issues once *it* is on screen, which the shell's own
/// two turns cannot cover. `pumpShell` documents that a destination needing a
/// third sequential read should grow a `pump()`-then-`runAsync` pair there
/// rather than in a test, and `test/helpers/test_env.dart` is outside this
/// task's file list — so the pair lives here and is flagged rather than
/// duplicated silently.
Future<void> _openSetup(WidgetTester tester, VocabRepository repository) async {
  await pumpShell(tester, repository);
  await _tap(tester, find.byIcon(Icons.check_box_outlined));
  await _settle(tester);
  expect(find.byType(QuizSetupScreen), findsOneWidget);
}

/// Mounts the quiz screen the way the app does: the brand theme, the app-wide
/// RTL direction, and the controller read from `provider`.
class _QuizApp extends StatelessWidget {
  const _QuizApp({required this.controller, this.brightness = Brightness.light});

  final QuizController controller;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<QuizController>.value(
      value: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const QuizScreen(),
      ),
    );
  }
}

/// The index of an option that is not the answer.
///
/// By identity, from [QuizQuestion.isCorrect]. Never by comparing text: that is
/// the bug this port exists to remove, and a helper that guessed with it would
/// quietly make these tests agree with the bug.
int _firstWrongIndex(QuizQuestion question) {
  for (var i = 0; i < question.options.length; i++) {
    if (!question.isCorrect(i)) return i;
  }
  throw StateError('the generated question had no wrong option');
}
