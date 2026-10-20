import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/packs/packs_controller.dart';
import 'package:lexilearn/ui/settings/app_settings_controller.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../helpers/test_env.dart';

/// The chrome, as `lib/ui/more/more_screen.dart` spells it.
const _title = 'المزيد';
const _statsHeading = 'إحصائياتك';
const _packsHeading = 'الحزم';
const _backupHeading = 'النسخ الاحتياطي';
const _bundledChip = 'مدمجة';
const _importPack = 'استيراد حزمة';
const _exportBackup = 'تصدير نسخة احتياطية';
const _restoreBackup = 'استعادة نسخة احتياطية';
const _delete = 'حذف';
const _deleteTitle = 'حذف الحزمة؟';
const _cancel = 'إلغاء';
const _reset = 'مسح التقدم';
const _resetTitle = 'مسح التقدم؟';
const _busy = 'جارٍ التنفيذ…';
const _noPacks = 'لا توجد حزم بعد.';
const _noAnswers = 'لا توجد إجابات بعد.';
const _loadFailed = 'تعذّر تحميل الإحصائيات.';
const _accuracyLabel = 'نسبة الدقة';
const _attemptsLabel = 'إجمالي الإجابات';
const _practisedLabel = 'كلمات تدربت عليها';
const _masteredLabel = 'كلمات أتقنتها';

/// The pack the shell fixture installs.
const _bundled = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'fever-1', term: 'fever', translations: <String>['حمى']),
  ],
);

/// A second pack, imported by a test, with an Arabic name.
///
/// Arabic on purpose: the row picks its text direction from the string's own
/// codepoints, so only a pack named in Arabic proves that half of the rule.
const _imported = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar_2',
  title: 'حزمة مستوردة',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(id: 'lantern-1', term: 'lantern', translations: <String>['فانوس']),
  ],
);

/// Everything inside the More screen and nothing outside it.
Finder inMore(String text) =>
    find.descendant(of: find.byType(MoreScreen), matching: find.text(text));

/// The card carrying [label] — one of the three stat tiles.
Finder statTile(String label) =>
    find.ancestor(of: inMore(label), matching: find.byType(AppSurface));

/// The value inside the tile carrying [label].
Finder statValue(String label, String value) =>
    find.descendant(of: statTile(label), matching: find.text(value));

/// A tap, then enough real turns of the event loop for what it triggered.
///
/// Shared helpers, no private copy of the dance: a tap that reaches the database
/// needs the real event loop to land, and `settleDatabase` is exactly that turn.
///
/// **`ensureVisible` first, because this page is long.** The reset control is
/// below the fold on the default 800×600 surface — its centre resolves to
/// `Offset(400.0, 800.0)` — and `tap` on an off-screen widget does not scroll to
/// it, it warns and misses. Same one-line family of trouble as
/// `useAPhone`, for the other reason a phone-sized surface does not solve: the
/// page's length depends on how many packs and figures are on it.
///
/// **Three turns, not one, and that is a fix rather than slack.** `settleDatabase`
/// is one turn of the real event loop, which covers one database round trip and
/// not reliably two when the machine is loaded — and **most actions on this page
/// are two round trips**, because every one of them writes and then re-reads:
/// `importFromPicker` writes through `importPack` and then calls `load()`;
/// `exportBackup` walks every pack and every pack's progress rows and only then
/// reaches the platform; `restoreBackup` runs a whole transaction and then
/// `load()`s. The second query is not even *issued* until the first has answered.
///
/// Measured, not assumed. With one turn, four of this file's tests went red
/// **only under load** — 4 of 6 concurrent runs of this file, and **0 of 8**
/// isolated `--plain-name` runs and 0 of 6 sequential full-file runs. Every one of
/// the four failed with the same signature, `Found 0 widgets with text "<what the
/// write should have produced>"`:
///
/// * `a valid file is imported and listed`
/// * `exporting on a device with no file provider says so and recovers`
/// * `a backup file is restored through the restore action`
/// * `importing a backup through the pack action names the other one`
///
/// That is a **flaky test** by `docs/engineering-standards.md` §9's own three
/// kinds — breaks under load, passes alone — and the fault is this test's
/// design, not the toolchain and not a weak assertion. `stats_screen_test.dart`
/// hit the identical trap, on the identical two-round-trip reset, measured it the
/// same way, and fixed it with a bounded loop; this is that fix, one level up.
///
/// Bounded at three, and it decides nothing: every assertion after it is the
/// thing that decides pass or fail. It only stops a test from reading the screen
/// before the screen's own read has landed.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  for (var turn = 0; turn < 3; turn++) {
    await settleDatabase(tester);
  }
}

/// Confirms whatever destructive dialog is open, and waits the same way.
///
/// A confirmation is a database round trip plus the re-read behind it, so it gets
/// the same bounded loop [_tap] gives — which is why this is [_tap] rather than a
/// second copy of the loop.
Future<void> _confirm(WidgetTester tester) => _tap(
      tester,
      find.widgetWithText(FilledButton, _delete).evaluate().isEmpty
          ? find.widgetWithText(FilledButton, _reset)
          : find.widgetWithText(FilledButton, _delete),
    );

/// Writes to the database from inside a `testWidgets` body, **before** anything
/// is mounted, and hands the value back.
///
/// Generic because one caller needs the result: the restore test has to read a
/// backup out of the database and then feed those bytes to an injected picker,
/// and a `Future<void>` signature would have made that two reads.
///
/// `tester.runAsync` is what makes it complete at all: a `testWidgets` body runs
/// in a fake-async zone where a real sqflite future never answers. The write is
/// awaited inside `runAsync` rather than fired and delayed the way
/// `commitAndSettle` does, because there is no tree yet for those pumps to be
/// useful.
Future<T?> _seed<T>(WidgetTester tester, Future<T> Function() read) =>
    tester.runAsync(read);

/// Mounts `MoreScreen` the way the app does — the brand theme, the app-wide RTL
/// direction — with an injected `PacksController` so no file dialog is ever
/// involved.
///
/// The controller is created and fired here rather than inside the screen, so a
/// test can also mount one that has *not* loaded yet. `MoreScreen` owns the real
/// one on the app's path; see `lib/ui/more/more_screen.dart` → `_resolvePacks`.
Future<void> _pumpMore(
  WidgetTester tester,
  VocabRepository repository, {
  String packKey = 'en_ar',
  String packTitle = 'English to Arabic',
  PickJsonFile? pickJsonFile,
  Brightness brightness = Brightness.light,
  PacksController? controller,
}) async {
  final packs = controller ??
      PacksController(
        repository: repository,
        pickJsonFile: pickJsonFile ?? () async => null,
      );
  await tester.pumpWidget(
    _MoreApp(
      repository: repository,
      packs: packs,
      packKey: packKey,
      packTitle: packTitle,
      brightness: brightness,
      settings: createAppSettings(repository),
    ),
  );
  await settleDatabase(tester);
}

class _MoreApp extends StatelessWidget {
  const _MoreApp({
    required this.repository,
    required this.packs,
    required this.packKey,
    required this.packTitle,
    required this.brightness,
    required this.settings,
  });

  final VocabRepository repository;
  final PacksController packs;
  final String packKey;

  /// The pack's **name**, as the shell hands it down.
  ///
  /// **The name and not the key**, for the same reason the app does it: a
  /// pack key is an identifier and the pill is in front of the user.
  final String packTitle;
  final Brightness brightness;

  /// The theme/launcher seams `LexiLearnApp` would have installed. `MoreScreen`
  /// carries the app's overflow menu, which reads both, so this stand-in has to
  /// supply them itself — see `appSeamProviders` in `test/helpers/test_env.dart`.
  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<VocabRepository>.value(value: repository),
        ChangeNotifierProvider<PacksController>.value(value: packs),
        ...appSeamProviders(settings: settings),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: MoreScreen(
          packKey: packKey,
          packTitle: packTitle,
          onPackSelected: (_) {},
        ),
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
    // Seeded, not imported: `TestHarness.create` installs its packs through
    // `importPack`, which marks them `isBundled: false`, and a non-bundled pack
    // is deletable. The bundled one is what `main.dart` puts on a real device,
    // and the difference between the two is exactly what this file asserts.
    harness = await TestHarness.create();
    await harness.repository.seedBundledPack(PackCodec.encodePack(_bundled));
  });

  tearDown(() async {
    if (!closed) await harness.dispose();
  });

  /// Records [attempts] right answers for [entryId].
  Future<void> answer(
    WidgetTester tester, {
    required String packKey,
    required String entryId,
    required int attempts,
  }) =>
      _seed(tester, () async {
        for (var i = 0; i < attempts; i++) {
          await harness.repository.recordAnswer(
              packKey: packKey, entryId: entryId, wasCorrect: true);
        }
      });

  Future<void> installImportedPack(WidgetTester tester) => _seed(
        tester,
        () => harness.repository
            .importPack(PackCodec.encodePack(_imported)),
      );

  group('the page itself', () {
    testWidgets('leads with statistics and ends with the reset, in that order',
        (tester) async {
      // Asserted on geometry, not on a list index: "statistics, then packs,
      // then backup, then reset" is a claim about where things sit.
      await _pumpMore(tester, harness.repository);

      expect(inMore(_title), findsOneWidget);
      final stats = tester.getTopLeft(inMore(_statsHeading)).dy;
      final packs = tester.getTopLeft(inMore(_packsHeading)).dy;
      final backup = tester.getTopLeft(inMore(_backupHeading)).dy;
      final reset = tester.getTopLeft(find.text(_reset)).dy;

      expect(stats, lessThan(packs));
      expect(packs, lessThan(backup));
      expect(backup, lessThan(reset));
    });

    testWidgets('names the active pack and nothing else on an empty pack',
        (tester) async {
      await _pumpMore(tester, harness.repository);

      // **The name, not the key.** The key was in the pill in front of the user.
      // The pill above the list and the pack's own row both name it.
      expect(inMore('English to Arabic'), findsNWidgets(2),
          reason: 'the pill above the list and the pack\'s own row');
      expect(inMore('en_ar'), findsNothing,
          reason: 'a pack key is an identifier and must not reach the user');
      expect(inMore(_bundledChip), findsOneWidget);
      expect(inMore(_noAnswers), findsOneWidget);
    });

    testWidgets('reports a failed statistics read rather than claiming an empty pack',
        (tester) async {
      // Close the database underneath the repository, so the read that follows
      // is the one that fails. `VocabRepository` is concrete and the data layer
      // underneath it is the thing being tested, so this is the honest fault.
      //
      // `readOutsideFakeAsync` on the close, not a bare `await`: a `testWidgets`
      // body runs in a fake-async zone where a real sqflite future never
      // answers, and awaited bare this one hangs to the ten-minute timeout.
      await _pumpMore(tester, harness.repository);
      closed = true;
      await readOutsideFakeAsync(tester, harness.dispose);

      // **Unmount before remounting.** `pumpWidget` reuses a `State` whose
      // runtimeType and key are unchanged, so pumping the same app twice does
      // *not* run `initState` again and the statistics controller — created there
      // — would still be holding the read that already succeeded. Measured: with
      // only the second `_pumpMore`, this test found zero failure messages.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await _pumpMore(tester, harness.repository);

      expect(inMore(_loadFailed), findsOneWidget);
      expect(inMore(_noAnswers), findsNothing,
          reason: 'a broken read is not a fresh install');
      expect(tester.takeException(), isNull);
    });

    testWidgets('every surface is an AppSurface and nothing is a bare Card',
        (tester) async {
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 2);
      await _pumpMore(tester, harness.repository);

      for (final label in <String>[
        _accuracyLabel,
        _attemptsLabel,
        _practisedLabel,
        _masteredLabel,
      ]) {
        expect(statTile(label), findsOneWidget, reason: '"$label" is not a card');
      }
      // The pack row, the accuracy card and the three tiles.
      expect(
        find.descendant(
            of: find.byType(MoreScreen), matching: find.byType(AppSurface)),
        findsNWidgets(5),
      );
      // The other half of the same rule: a bare `Card` renders a hard black
      // keyline in this rasteriser, measured at 29,111 pixels once.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows no spinner while it reads, because a spinner never settles',
        (tester) async {
      // An indeterminate `CircularProgressIndicator` schedules frames forever,
      // so `pumpAndSettle` would never return while one was on screen — which
      // would hang every test on this file. The same decision, for the same
      // reason, as `stats_screen.dart`'s loading line.
      await tester.pumpWidget(
        _MoreApp(
          repository: harness.repository,
          packs: PacksController(
            repository: harness.repository,
            pickJsonFile: () async => null,
          ),
          packKey: 'en_ar',
          packTitle: 'English to Arabic',
          brightness: Brightness.light,
          settings: createAppSettings(harness.repository),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      // And it is replaced, not stacked under, once the reads answer — with the
      // settle *after* the assertions, because the read this screen fired from
      // `initState` is still in flight and the binding reports an outstanding
      // timer if the body ends without it. Measured: ending here failed with
      // `Pending timers: … SqfliteDatabaseMixin.txnSynchronized`.
      await settleDatabase(tester);
      expect(inMore(_title), findsOneWidget);
    });

    testWidgets('no button or chip on this page paints an elevation shadow',
        (tester) async {
      // **The resolved style, not the source text.** `elevation: 0` written at
      // the call site is invisible to a reader of this assertion, and the
      // failure mode it exists for is not "someone forgot to type it here" —
      // it is "a Material default is 1 and this rasteriser strokes that as an
      // opaque black keyline". Measured out of this SDK's
      // `packages/flutter/lib/src/material/`: `ElevatedButton` rests at **1.0**
      // (`elevated_button.dart:570-585`), `Chip` resolves through a `?? 0`
      // fallback and is already safe (`chip.dart:1350`), and `FilledButton` —
      // which rests at 0.0 — **jumps to 1.0 on hover**
      // (`filled_button.dart:588-603`).
      //
      // **`hovered` is asserted for that last reason.** A resting-only check
      // would pass on a completely unmodified theme for the filled buttons, and
      // a golden would never see the difference, because a screenshot is taken
      // with no pointer over anything.
      //
      // **Two layers supply this, and each one is caught by a different test.**
      // Measured, deleting each in turn:
      //
      // | mutation | this test | `app_theme_test.dart` |
      // |---|---|---|
      // | the three theme entries removed | **green** | **red** |
      // | the six per-widget opt-outs removed | **red** | unaffected |
      // | both layers removed | **red** | **red** |
      //
      // So neither layer's regression is silent, which is the property worth
      // having — but the first row also means this test must **not** claim to
      // guard the theme. It guards the screen: the local `elevation: 0` at each
      // of the four call sites and the `Chip`, with the theme as a second line of
      // defence for every *other* screen that never remembered to opt out. That
      // second line is what `app_theme_test.dart` pins, and only it can.
      await _pumpMore(tester, harness.repository);

      const resting = <WidgetState>{};
      const hovering = <WidgetState>{WidgetState.hovered};
      const pressed = <WidgetState>{WidgetState.pressed};

      Future<void> expectNoElevation(
        Finder finder,
        String what,
      ) async {
        // **Two layers are checked, because two layers supply the value**, and
        // neither check alone catches both regressions.
        //
        // * The widget's **declared** `style` — catches someone deleting the
        //   local `elevation: 0` at the call site.
        // * The **`Material` the button actually builds**, whose `elevation` is
        //   the resolved value (`button_style_button.dart:600` passes
        //   `elevation: resolvedElevation!` into it). This is the "does it
        //   *paint* a keyline" half, and it is what would catch a widget that
        //   relied on the theme alone.
        final button = tester.widget<ButtonStyleButton>(finder);
        final material = tester.widget<Material>(
          find.descendant(of: finder, matching: find.byType(Material)).first,
        );
        for (final entry in <String, Set<WidgetState>>{
          'resting': resting,
          'hovered': hovering,
          'pressed': pressed,
        }.entries) {
          expect(
            button.style?.elevation?.resolve(entry.value),
            0.0,
            reason: '$what declares an elevation in its ${entry.key} state',
          );
        }
        expect(material.elevation, 0.0,
            reason: '$what paints a Material at elevation '
                '${material.elevation}, which is a keyline');
      }

      await expectNoElevation(
        find.widgetWithText(FilledButton, _importPack),
        'the import button',
      );
      await expectNoElevation(
        find.widgetWithText(OutlinedButton, _exportBackup),
        'the export button',
      );
      await expectNoElevation(
        find.widgetWithText(OutlinedButton, _restoreBackup),
        'the restore button',
      );
      await expectNoElevation(
        find.widgetWithText(OutlinedButton, _reset),
        'the reset pill',
      );

      // `ChipThemeData.elevation` and `Chip.elevation` are plain `double?`s, not
      // `WidgetStateProperty`s — `chip.dart:1350` reads the widget's value
      // straight into a `?? 0` chain — so there is no state to resolve, and
      // calling `resolve` on it would be inventing an API. `Chip` has no hover
      // state and no `pressElevation` getter of its own (`RawChip` has it, and
      // `Chip` does not), so the resting value is the whole of what this widget
      // can be asked. The press value is pinned on the theme in
      // `test/design/app_theme_test.dart`, where `ChipThemeData` does expose it.
      final chip = tester.widget<Chip>(
        find.ancestor(of: inMore(_bundledChip), matching: find.byType(Chip)).first,
      );
      expect(chip.elevation, 0.0, reason: 'the bundled chip rests raised');

      expect(tester.takeException(), isNull);
    });

    testWidgets('the dark theme reaches the dark tokens', (tester) async {
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 2);
      await _pumpMore(tester, harness.repository, brightness: Brightness.dark);

      final style = tester.widget<Text>(inMore('100%')).style;
      expect(style?.color, AppColors.primaryDark);

      final resetStyle =
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, _reset)).style!;
      expect(resetStyle.foregroundColor?.resolve(<WidgetState>{}), AppColors.errorDark);
      expect(tester.takeException(), isNull);
    });
  });

  group('the statistics figures', () {
    testWidgets('report accuracy, answers, words practised and words mastered',
        (tester) async {
      // `fever-1` reaches the mastery floor in `word_progress.dart` (5 attempts at
      // 80%+). 5 right, then 1 more right and 1 wrong: 6 of 7.
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 5);
      await _seed(tester, () async {
        await harness.repository.recordAnswer(
            packKey: 'en_ar', entryId: 'fever-1', wasCorrect: true);
        await harness.repository.recordAnswer(
            packKey: 'en_ar', entryId: 'fever-1', wasCorrect: false);
      });

      await _pumpMore(tester, harness.repository);

      expect(statValue(_accuracyLabel, '86%'), findsOneWidget,
          reason: '6 of 7 is 85.7%, and it must round rather than truncate');
      expect(statValue(_attemptsLabel, '7'), findsOneWidget);
      expect(statValue(_practisedLabel, '1'), findsOneWidget);
      expect(statValue(_masteredLabel, '1'), findsOneWidget);
      expect(inMore(_noAnswers), findsNothing);
    });

    testWidgets('the accuracy number is in brand ink, never the accent',
        (tester) async {
      // `design_tokens.dart` permits the amber for icons and fills only.
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 2);
      await _pumpMore(tester, harness.repository);

      final style = tester.widget<Text>(inMore('100%')).style;
      expect(style?.color, AppColors.primaryLight);
      expect(style?.color, isNot(AppColors.accent));
      expect(style?.fontFamily, 'Inter',
          reason: 'a numeral run names the brand Latin explicitly');
    });
  });

  group('the packs list', () {
    testWidgets('marks the bundled pack undeletable and says so', (tester) async {
      await _pumpMore(tester, harness.repository);

      expect(inMore(_bundledChip), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing,
          reason: 'a bundled pack is re-seeded on the next launch');
    });

    testWidgets('shows an imported pack in its own script and offers a delete',
        (tester) async {
      await installImportedPack(tester);
      await _pumpMore(tester, harness.repository);

      expect(inMore('حزمة مستوردة'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      // The active pack is named **once** in the pill above the rows and once
      // in its own row, and the key is not named at all: `en_ar` is an
      // identifier, not a name. `test/ui/home_shell_test.dart` asserts each
      // destination shows the pack, and this is the shape that satisfies that
      // whether one pack is installed or five.
      expect(inMore('English to Arabic'), findsNWidgets(2),
          reason: 'the pill above the list and the pack\'s own row');
      expect(inMore('en_ar'), findsNothing,
          reason: 'a pack key is an identifier and must not reach the user');
      expect(inMore('en_ar_2'), findsNothing);
      // Arabic keeps the ambient family and the app's direction; a Latin title
      // names Inter and asks for LTR. Both directions are asserted, because a
      // screen that always picked one would still draw every string legibly.
      expect(tester.widget<Text>(inMore('حزمة مستوردة')).textDirection, isNull);
      // **Two Latin names on this page** — the pill above the list and the
      // pack's own row — and both of them ask for LTR.
      final latin = inMore('English to Arabic');
      expect(
        tester.widget<Text>(latin.first).textDirection,
        TextDirection.ltr,
        reason: 'the pill',
      );
      expect(
        tester.widget<Text>(latin.last).textDirection,
        TextDirection.ltr,
        reason: 'the pack row',
      );
    });

    testWidgets('says so in words when there is no pack at all', (tester) async {
      // The device with nothing installed, reached by deleting rather than by
      // opening a second harness: `TestHarness.create` awaits real sqflite
      // futures and a `testWidgets` body runs in a fake-async zone where those
      // never answer. Measured: building one here hung to the ten-minute
      // timeout with no message naming the cause.
      await _seed(tester, () => harness.repository.deletePack('en_ar'));

      await _pumpMore(tester, harness.repository);

      expect(inMore(_noPacks), findsOneWidget);
      expect(inMore(_bundledChip), findsNothing);
    });

    testWidgets('tapping a row reports it, and never the row already active',
        (tester) async {
      await installImportedPack(tester);
      String? chosen;
      await tester.pumpWidget(
        ChangeNotifierProvider<PacksController>.value(
          value: PacksController(
            repository: harness.repository,
            pickJsonFile: () async => null,
          ),
          child: MultiProvider(
            providers: appSeamProviders(
              settings: createAppSettings(harness.repository),
            ),
            child: Provider<VocabRepository>.value(
              value: harness.repository,
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) =>
                    Directionality(textDirection: TextDirection.rtl, child: child!),
                home: MoreScreen(
                  packKey: 'en_ar',
                  onPackSelected: (key) => chosen = key,
                ),
              ),
            ),
          ),
        ),
      );
      await settleDatabase(tester);

      await _tap(tester, inMore('حزمة مستوردة'));
      expect(chosen, 'en_ar_2');

      // The active pack's row is the other one, and re-picking what is already
      // active is a no-op rather than a second write.
      await _tap(tester, inMore('English to Arabic'));
      expect(chosen, 'en_ar_2', reason: 'the active pack did not change');
    });
  });

  group('importing and restoring', () {
    testWidgets('a malformed file says so in words and imports nothing',
        (tester) async {
      await _pumpMore(
        tester,
        harness.repository,
        pickJsonFile: () async => '{ this is not json',
      );

      await _tap(tester, find.widgetWithText(FilledButton, _importPack));

      // The codec's own sentence, matched on its opening words: the full text
      // ends in a `FormatException` message whose wording is the SDK's, not
      // this app's, so pinning the whole string would make this a test of Dart.
      expect(inMoreContaining('This file is not valid JSON'), findsOneWidget);
      expect(inMore('English to Arabic'), findsNWidgets(2),
          reason: 'the pill above the list and the pack\'s own row');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a valid file is imported and listed', (tester) async {
      await _pumpMore(
        tester,
        harness.repository,
        pickJsonFile: () async => PackCodec.encodePack(_imported),
      );

      await _tap(tester, find.widgetWithText(FilledButton, _importPack));

      expect(inMore('حزمة مستوردة'), findsOneWidget);
      expect(inMoreContaining('تم استيراد'), findsOneWidget);
    });

    testWidgets('backing out of the dialog says nothing was chosen',
        (tester) async {
      await _pumpMore(tester, harness.repository, pickJsonFile: () async => null);

      await _tap(tester, find.widgetWithText(FilledButton, _importPack));

      expect(inMore('لم تختر ملفاً.'), findsOneWidget);
    });

    testWidgets('importing a backup through the pack action names the other one',
        (tester) async {
      // Both file kinds are `.json`, so a user has no way to tell them apart
      // before handing one over. Each action must refuse the other's shape with
      // a sentence that says what to do instead.
      await _pumpMore(
        tester,
        harness.repository,
        pickJsonFile: () async => await harness.repository.exportBackupJson(),
      );

      await _tap(tester, find.widgetWithText(FilledButton, _importPack));

      expect(inMoreContaining('Restore backup'), findsOneWidget);
      expect(inMore('حزمة مستوردة'), findsNothing,
          reason: 'a backup is not a pack, so importing it imported nothing');
    });

    testWidgets('a backup file is restored through the restore action',
        (tester) async {
      await installImportedPack(tester);
      // Inside `runAsync` for the same reason every write here is: a real
      // sqflite future never answers inside a `testWidgets` body. Measured: read
      // bare, this hung to the ten-minute timeout with nothing naming the cause.
      final backup =
          await _seed(tester, () => harness.repository.exportBackupJson());
      // Drop the imported pack so the restore has something to put back.
      await _seed(tester, () => harness.repository.deletePack('en_ar_2'));

      await _pumpMore(
        tester,
        harness.repository,
        pickJsonFile: () async => backup,
      );

      await _tap(tester, find.widgetWithText(OutlinedButton, _restoreBackup));

      expect(inMore('حزمة مستوردة'), findsOneWidget);
      expect(inMoreContaining('تمت الاستعادة'), findsOneWidget);
    });

    testWidgets('restoring a pack through the restore action names the other one',
        (tester) async {
      await _pumpMore(
        tester,
        harness.repository,
        pickJsonFile: () async => PackCodec.encodePack(_imported),
      );

      await _tap(tester, find.widgetWithText(OutlinedButton, _restoreBackup));

      expect(inMoreContaining('vocabulary pack'), findsOneWidget);
      expect(inMore('حزمة مستوردة'), findsNothing,
          reason: 'the file was refused, so nothing was imported');
    });

    testWidgets('exporting on a device with no file provider says so and recovers',
        (tester) async {
      // `path_provider` has no implementation under `flutter_test`, so the
      // documents directory cannot be reached here. What this pins is the
      // behaviour that *is* reachable: the controller stays alive, `isBusy`
      // returns to false, and the user reads a sentence rather than a stack
      // trace. The JSON that would have been written is pinned directly against
      // `VocabRepository.exportBackupJson` in `test/data/vocab_repository_test.dart`.
      final controller = PacksController(repository: harness.repository);
      addTearDown(controller.dispose);
      await _pumpMore(tester, harness.repository, controller: controller);

      await _tap(tester, find.widgetWithText(OutlinedButton, _exportBackup));

      expect(inMore('تعذّر إنشاء النسخة الاحتياطية على هذا الجهاز.'),
          findsOneWidget);
      expect(controller.isBusy, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every file action is disabled while one is in flight',
        (tester) async {
      // A second tap during a pick would open two dialogs; the busy flag is what
      // stops it, and this asserts the buttons actually honour it.
      final gate = Completer<String?>();
      final controller = PacksController(
        repository: harness.repository,
        pickJsonFile: () => gate.future,
      );
      addTearDown(controller.dispose);
      await _pumpMore(tester, harness.repository, controller: controller);

      final import = find.widgetWithText(FilledButton, _importPack);
      await tester.tap(import);
      await tester.pump();
      expect(inMore(_busy), findsWidgets);
      expect(
        tester.widget<FilledButton>(import).onPressed,
        isNull,
        reason: 'import stayed live while a pick was open',
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, _exportBackup))
            .onPressed,
        isNull,
      );

      gate.complete(null);
      await settleDatabase(tester);
      expect(
        tester.widget<FilledButton>(import).onPressed,
        isNotNull,
        reason: 'the button stayed dead after the pick finished',
      );
    });
  });

  group('deleting a pack', () {
    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      await installImportedPack(tester);
      await _pumpMore(tester, harness.repository);

      await _tap(tester, find.byIcon(Icons.delete_outline));
      expect(inMore(_deleteTitle), findsOneWidget);

      await _tap(tester, find.widgetWithText(TextButton, _cancel));
      expect(inMore(_deleteTitle), findsNothing);
      expect(inMore('حزمة مستوردة'), findsOneWidget);
    });

    testWidgets('confirming removes the pack and says which one',
        (tester) async {
      await installImportedPack(tester);
      await _pumpMore(tester, harness.repository);

      await _tap(tester, find.byIcon(Icons.delete_outline));
      await _confirm(tester);

      expect(inMore(_deleteTitle), findsNothing);
      expect(inMore('حزمة مستوردة'), findsNothing);
      // Two lines, matched separately and not by their shared opening words:
      // the controller's generic confirmation and this screen's, which names the
      // pack. `inMoreContaining('تم حذف')` matched **both** before they were
      // pinned apart.
      expect(inMore('تم حذف الحزمة.'), findsOneWidget);
      expect(inMore('تم حذف «حزمة مستوردة».'), findsOneWidget);

      final packs = await readOutsideFakeAsync(
          tester, () => harness.repository.packs());
      expect(packs.map((p) => p.packKey), <String>['en_ar']);
    });
  });

  group('resetting', () {
    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 2);
      await _pumpMore(tester, harness.repository);

      await _tap(tester, find.widgetWithText(OutlinedButton, _reset));

      expect(inMore(_resetTitle), findsOneWidget);
      // Two, not one, and the count is the assertion: the screen's action and
      // the confirmation's own button carry the same words, so while the
      // confirmation is open that string is on screen twice.
      expect(find.text(_reset), findsNWidgets(2));

      await _tap(tester, find.widgetWithText(TextButton, _cancel));

      expect(inMore(_resetTitle), findsNothing);
      expect(statValue(_attemptsLabel, '2'), findsOneWidget);
    });

    testWidgets('confirming clears the figures behind it', (tester) async {
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 2);
      await _pumpMore(tester, harness.repository);
      expect(statValue(_attemptsLabel, '2'), findsOneWidget);

      await _tap(tester, find.widgetWithText(OutlinedButton, _reset));
      await _confirm(tester);

      expect(inMore(_resetTitle), findsNothing);
      expect(inMore(_noAnswers), findsOneWidget);
      expect(statValue(_attemptsLabel, '2'), findsNothing);

      final stats = await readOutsideFakeAsync(
          tester, () => harness.repository.stats('en_ar'));
      expect(stats.totalAttempts, 0);
    });

    testWidgets('the system back cancels the confirmation rather than leaving the screen',
        (tester) async {
      // Same measurement as `stats_screen_test.dart`, for the same wrapper: with
      // the confirmation open, `tester.binding.handlePopRoute()` returned `true`,
      // the screen's count went to 0 and the host route came back. Back left the
      // screen mid-confirmation.
      //
      // Mounted through `pumpShell` rather than the stand-in app on purpose:
      // `handlePopRoute` is about the *navigator*, and the stand-in mounts
      // `MoreScreen` as `MaterialApp.home`, which has no route underneath to
      // come back to.
      await answer(tester, packKey: 'en_ar', entryId: 'fever-1', attempts: 2);
      await pumpShell(tester, harness.repository);
      await tester.tap(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text(_title)),
      );
      await tester.pumpAndSettle();
      await settleDatabase(tester);
      expect(find.byType(MoreScreen), findsOneWidget);

      await _tap(tester, find.widgetWithText(OutlinedButton, _reset));
      expect(inMore(_resetTitle), findsOneWidget);

      // **The return value of `handlePopRoute` is not asserted here, and the
      // comment this test used to carry said why and then asserted it anyway.**
      //
      // `NavigatorState.maybePop` returns `true` for `RoutePopDisposition.doNotPop`
      // — that is, for a pop this code *deliberately blocked* — as well as for a
      // real one, because "handled" is what it reports and being blocked on
      // purpose counts (`docs/engineering-standards.md` §2, traced through
      // `navigator.dart` and `routes.dart` on this SDK). So `expect(handled,
      // isTrue)` cannot tell the two behaviours apart.
      //
      // What distinguishes them is the tree, and that is what this asserts.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(MoreScreen), findsOneWidget,
          reason: 'the route did not pop; back did not navigate away');
      expect(inMore(_resetTitle), findsNothing,
          reason: 'back dismissed the confirmation rather than being swallowed');
      // And it reset nothing.
      expect(statValue(_attemptsLabel, '2'), findsOneWidget);
    });
  });

  group('reached from the bottom bar', () {
    testWidgets('المزيد lands here and the pack key is handed to the screen',
        (tester) async {
      // The artwork's bar draws exactly four items and `المزيد` is the fourth.
      // `test/ui/home_shell_test.dart` pins the four labels and icons; this pins
      // the destination this task actually filled in.
      await pumpShell(tester, harness.repository);

      await tester.tap(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text(_title)),
      );
      await tester.pumpAndSettle();
      await settleDatabase(tester);

      expect(find.byType(MoreScreen), findsOneWidget);
      // **The name, not the key.** The key was in the pill in front of the
      // user, and a pack key is an identifier.
      expect(inMore('English to Arabic'), findsNWidgets(2),
          reason: 'the pill above the list and the pack\'s own row');
      expect(inMore('en_ar'), findsNothing,
          reason: 'a pack key is an identifier and must not reach the user');
      expect(inMore(_packsHeading), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Anything on the More screen carrying [fragment].
Finder inMoreContaining(String fragment) => find.descendant(
      of: find.byType(MoreScreen),
      matching: find.textContaining(fragment),
    );