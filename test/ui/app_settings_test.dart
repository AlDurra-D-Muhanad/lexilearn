import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/app.dart';
import 'package:lexilearn/ui/settings/app_settings_controller.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home_shell.dart';
import 'package:lexilearn/ui/link/external_link.dart';
import 'package:lexilearn/ui/settings/app_info_screen.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';

import '../helpers/test_env.dart';

/// The copy the overflow menu and the about screen draw, as
/// `lib/ui/settings/` spells it.
const _appInfoLabel = 'معلومات التطبيق';
const _themeSystem = 'حسب النظام';
const _themeLight = 'فاتح';
const _themeDark = 'داكن';
const _telegramLabel = 'تواصل معي على تيلغرام';
const _developerName = 'Muhanad';

/// The pack the fixtures install.
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

/// The `Uri` every link test expects to be handed, spelled out here so the
/// assertion is about the *value* and not about the constant it came from.
///
/// `expect(fired, telegramContactUri)` would pass if the constant were edited to
/// anything at all, which is exactly the regression a user would notice: a
/// Telegram entry that opens somebody else's chat is still a green test. So the
/// literal is written here too, and the constant is asserted *against* it.
final Uri _expectedTelegram = Uri.parse('https://t.me/MUHANAD_D');

void main() {
  late TestHarness harness;

  /// True once a test has closed the harness itself to force a read to fail, so
  /// `tearDown` does not close it a second time.
  var closed = false;

  setUp(() async {
    closed = false;
    clearLaunchedLinks();
    harness = await TestHarness.create(packs: const <VocabPack>[_pack]);
  });

  tearDown(() async {
    // Guarded, because one test closes the harness itself to force a read to
    // fail; `tearDown` must not close it a second time.
    if (!closed) await harness.dispose();
  });

  /// Mounts the real app and opens the overflow menu.
  Future<void> openOverflowMenu(WidgetTester tester) async {
    await pumpShell(tester, harness.repository);
    await tester.tap(threeDotMenu);
    await tester.pumpAndSettle();
  }

  group('the overflow menu', () {
    testWidgets('every destination carries it', (tester) async {
      // Item 1, and the part of it that is a decision rather than a tap: the
      // control is on **all four** bottom-bar destinations, not only on Home
      // where the user noticed it missing. A menu on one screen and not three
      // reads as a bug on the other three. See `AppOverflowMenu`.
      await pumpShell(tester, harness.repository);
      expect(find.byType(AppOverflowMenu), findsOneWidget,
          reason: 'Home carries the menu');

      for (final icon in <IconData>[
        Icons.style_outlined,
        Icons.check_box_outlined,
        Icons.apps,
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pumpAndSettle();
        await settleDatabase(tester);
        expect(find.byType(AppOverflowMenu), findsOneWidget,
            reason: 'the destination reached by $icon carries the menu');
      }
    });

    testWidgets('the three-dot control is at the top of the screen',
        (tester) async {
      // "at the top" is measured, not asserted as a word. On the three screens
      // with an AppBar the menu has to be *inside* it; on Home, which has no
      // AppBar, it has to sit in the header row. Either way it is above the
      // body, and this is what a screenshot would show.
      await pumpShell(tester, harness.repository);

      final onHome = tester.getTopLeft(find.byType(AppOverflowMenu));
      expect(onHome.dy,
          lessThan(tester.getTopLeft(find.byType(TextField)).dy),
          reason: 'Home has no AppBar; the menu is in the header above the search');

      await tester.tap(find.byIcon(Icons.apps));
      await tester.pumpAndSettle();
      await settleDatabase(tester);
      final inAppBar = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(AppOverflowMenu),
      );
      expect(inAppBar, findsOneWidget,
          reason: 'a screen with an AppBar puts the menu in it');
    });

    testWidgets('معلومات التطبيق opens the about screen', (tester) async {
      // Item 1.
      await openOverflowMenu(tester);
      expect(find.text(_appInfoLabel), findsOneWidget);
      await tester.tap(find.text(_appInfoLabel));
      await tester.pumpAndSettle();

      expect(find.byType(AppInfoScreen), findsOneWidget);
      // The about screen is a *route*, like every other full screen here, so it
      // has the app's own back arrow rather than being a sheet.
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('the about screen', () {
    testWidgets('names the developer the user gave', (tester) async {
      // Item 4. Asserted as a rendered string, not as a constant: the constant
      // would be right whether or not the row were on screen.
      await openOverflowMenu(tester);
      await tester.tap(find.text(_appInfoLabel));
      await tester.pumpAndSettle();

      expect(find.text(_developerName), findsOneWidget,
          reason: 'the developer name is on the about screen, not just in a '
              'constant nobody can reach');
      expect(find.text('المطور'), findsOneWidget);
    });

    testWidgets('reaches the same Telegram chat', (tester) async {
      await openOverflowMenu(tester);
      await tester.tap(find.text(_appInfoLabel));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.telegram), findsOneWidget,
          reason: 'a Telegram icon, not a generic share glyph');
      await tester.tap(find.byIcon(Icons.telegram));
      await settleDatabase(tester);

      expect(launchedLinks, hasLength(1));
      expect(launchedLinks.single, _expectedTelegram);
    });
  });

  group('the Telegram entry', () {
    testWidgets('carries a Telegram icon and opens the chat',
        (tester) async {
      // Item 5.
      await openOverflowMenu(tester);

      // The icon is beside the label, which is what "the menu has a Telegram
      // entry with a Telegram icon" means in pixels.
      final row = find.ancestor(
        of: find.text(_telegramLabel),
        matching: find.byType(Row),
      );
      expect(find.descendant(of: row, matching: find.byIcon(Icons.telegram)),
          findsOneWidget,
          reason: 'the Telegram entry carries the Telegram mark');

      await tester.tap(find.text(_telegramLabel));
      await settleDatabase(tester);

      // **The intent that would be fired, shown without a device.** The seam
      // received the `Uri`, and the `Uri` *is* the whole payload of the Android
      // intent — `url_launcher_android`'s `UrlLauncher.java:87-90` does
      // `new Intent(ACTION_VIEW).setData(Uri.parse(url))` and nothing else. So
      // asserting the `Uri` is asserting the intent.
      expect(launchedLinks, hasLength(1));
      final fired = launchedLinks.single;
      expect(fired.scheme, 'https');
      expect(fired.host, 't.me');
      expect(fired.path, '/MUHANAD_D');
      expect(fired, _expectedTelegram);
      expect(fired.query, isEmpty, reason: 'a bare chat link, no tracking');
    });

    test('the constant and the user-visible intent are one string', () {
      // Guards the *other* failure: someone edits the constant and every test
      // above still passes, because they compare against the constant.
      expect(telegramContactUri, _expectedTelegram);
      expect(telegramContactUri.toString(), 'https://t.me/MUHANAD_D');
    });

    test('the shipped URL carries no permission', () {
      // Item 5's dependency check, and `docs/engineering-standards.md` §12's
      // "re-verify after any dependency change" as far as it can be discharged
      // without running a Gradle build. **What this proves:** the two manifests
      // that get merged contain no `<uses-permission>`. **What it does not
      // prove:** the final merged manifest inside a built APK — this round was
      // not permitted to run `flutter build`, so §12's end-to-end re-verification
      // is still outstanding and is recorded as such rather than claimed.
      const appManifest =
          'android/app/src/main/AndroidManifest.xml';

      // **The plugin's manifest is found through the resolved package config,
      // not through a path written into the test.**
      //
      // It used to name `D:\pub-cache\hosted\pub.dev\url_launcher_android-6.3.33\...`
      // -- an absolute path on one machine. **A test that names an absolute
      // path can only pass on the machine that wrote it**, and it did: it was
      // green locally through every round, and it went red only on the Linux
      // CI runner, where the file it was asserting about does not exist. The
      // assertion that was supposed to be the guard on section 12 was asserting
      // nothing on half the machines that ran it.
      //
      // The package config names the version that was actually resolved, so
      // this is a stronger check than the path was: it cannot drift from the
      // dependency without going red.
      final pluginManifest = _resolvedManifestOf('url_launcher_android');
      expect(pluginManifest, isNotNull,
          reason: 'url_launcher_android must be in the resolved package config; '
              'if it was dropped, the check below would be asserting nothing');

      for (final path in <String>[appManifest, pluginManifest!]) {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: '$path is the manifest the merger reads; if it moved, this '
                'check is silently asserting nothing');
        final xml = file.readAsStringSync();
        expect(xml.contains('<uses-permission'),
            isFalse,
            reason: '$path declares a permission, so the offline claim in §12 is '
                'no longer true and the launcher decision must be revisited');
      }
    });
  });

  group('the theme choice', () {
    testWidgets('is a menu of three, not a flip', (tester) async {
      // Item 2. A toggle cannot express "go back to following the system", and
      // the user is entitled to that — `ThemeMode.system` is a real option.
      await openOverflowMenu(tester);

      for (final label in <String>[_themeSystem, _themeLight, _themeDark]) {
        expect(find.text(label), findsOneWidget,
            reason: '«$label» is offered, not just a flip');
      }
    });

    testWidgets('recolours the app when one is chosen', (tester) async {
      await openOverflowMenu(tester);
      expect(_scaffoldBrightness(tester), Brightness.light);

      await tester.tap(find.text(_themeDark));
      await settleDatabase(tester);

      expect(_scaffoldBrightness(tester), Brightness.dark,
          reason: 'choosing «داكن» repaints the app, which is the whole point');
    });

    testWidgets('marks the current choice, and only the current one',
        (tester) async {
      await openOverflowMenu(tester);
      expect(_checkedThemeLabels(<String>[_themeSystem, _themeLight, _themeDark]),
          <String>[_themeSystem],
          reason: 'nothing stored means the app follows the system');

      await tester.tap(find.text(_themeDark));
      await settleDatabase(tester);
      await tester.tap(threeDotMenu);
      await tester.pumpAndSettle();

      expect(
          _checkedThemeLabels(<String>[_themeSystem, _themeLight, _themeDark]),
          <String>[_themeDark]);
    });

    testWidgets('the theme choice survives a restart', (tester) async {
      // **The one that matters, and it is a restart rather than a rebuild.**
      //
      // `:memory:` cannot express this: `TestHarness.create` opens with
      // `singleInstance: false`, so a second harness at the same `:memory:` path
      // is a *different, empty* database — a fresh install, not a restart. So
      // this runs against a file on disk, and a restart means: close the
      // database, build a brand-new `VocabRepository` over the same file, and
      // mount a brand-new `LexiLearnApp`.
      final dir = Directory.systemTemp.createTempSync('lexilearn-restart');
      final path = '${dir.path}/lexilearn.db';
      // **Swallowed, and deliberately.** `TestHarness.dispose` closes the
      // database, but the sqflite FFI side can still hold the file when
      // `tearDown` runs, so `deleteSync` intermittently throws
      // `PathAccessException` â€” a failure of the *cleanup*, not of the thing
      // under test, and one a mutation run of this file actually hit. The
      // directory lives under the OS temp root and costs nothing if it lives.
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Left behind on purpose rather than failing a green test.
        }
      });

      // `runAsync` for both harnesses: `TestHarness.create` opens a real
      // database and `dispose` closes it, and a `testWidgets` body runs in a
      // fake-async zone where neither completes — it hangs for the full ten
      // minutes with no message. `docs/engineering-standards.md` §5, and the same
      // reason the harness is built in `setUp` everywhere else.
      final before = (await tester.runAsync(
          () => TestHarness.create(packs: const <VocabPack>[_pack], path: path)))!;

      await tester.pumpWidget(
        LexiLearnApp(repository: before.repository),
      );
      await settleDatabase(tester);
      await tester.tap(threeDotMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_themeDark));
      await settleDatabase(tester);
      expect(_scaffoldBrightness(tester), Brightness.dark,
          reason: 'the choice took effect before anything was closed');

      // --- the restart ---
      // Tear the whole tree down and close the file. Nothing from the old
      // session survives: no controller, no repository, no open database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(before.dispose);

      final after = (await tester.runAsync(() => TestHarness.create(path: path)))!;
      addTearDown(() => tester.runAsync(after.dispose));

      await tester.pumpWidget(LexiLearnApp(repository: after.repository));
      await settleDatabase(tester);

      expect(_scaffoldBrightness(tester), Brightness.dark,
          reason: 'the choice was read back out of SQLite by a different '
              'repository over the same file — not remembered by a widget');
    });

    testWidgets('a fresh install follows the system', (tester) async {
      await pumpShell(tester, harness.repository);
      expect(_scaffoldBrightness(tester), Brightness.light);
      expect(find.text('مرحباً بك!'), findsOneWidget);
    });

    testWidgets('a failed read leaves the controller on the system theme',
        (tester) async {
      // **Scoped to the controller on purpose, and the scope is the finding.**
      //
      // The first version of this test mounted the whole app over a closed
      // database and expected no exception. It got one, and not from the
      // settings read: `HomeShell._loadActivePack` reads the pack list in
      // `initState` and does **not** catch. So the honest statement is the
      // narrow one — `AppSettingsController` never throws — rather than "the app
      // survives an unreadable database", which is false today for a reason that
      // has nothing to do with the theme. Guarding the shell's read is a
      // different task and this is not it.
      //
      // `runAsync` for the close: closing a real database inside a `testWidgets`
      // body hangs for the full ten minutes with no message
      // (`docs/engineering-standards.md` §5) — the same trap `TestHarness.create`
      // is built in `setUp` to avoid.
      final repository = harness.repository;
      final controller = AppSettingsController(repository: repository);
      addTearDown(controller.dispose);
      await tester.runAsync(harness.dispose);
      closed = true;

      await controller.load();

      expect(controller.mode, ThemeMode.system);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The three-dot control, however it is typed.
///
/// `AppOverflowMenu` builds `PopupMenuButton<_MenuValue>` with a **private**
/// value type, and Dart reifies generics — `find.byType(PopupMenuButton<Object>)`
/// would not match it, and naming `_MenuValue` is impossible from outside
/// `lib/ui/settings/`. So the finder is the glyph, which is the thing the user
/// actually taps and is unambiguous because the app has exactly one menu.
Finder get threeDotMenu => find.byIcon(Icons.more_vert);

/// The brightness the app is actually rendering in.
///
/// Read off the **shell's** theme rather than off `AppSettingsController`,
/// because the controller is the *intent* and this is the *result*: a test that
/// only read the controller would pass while the app stayed light. The shell is
/// above every destination, so this is the one widget whose theme is the whole
/// app's.
Brightness _scaffoldBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(HomeShell))).brightness;

/// Whether the theme row carrying [label] is drawn with a tick beside it.
///
/// Scoped to the row's **nearest** `Row` ancestor rather than to the menu, so a
/// tick on one row cannot be counted for another. The tick is what the user
/// actually sees, so it is what is asked about: a row that is built but not
/// marked is not "chosen".
bool _isChecked(String label) => find
    .descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.check_circle),
    )
    .evaluate()
    .isNotEmpty;

/// The theme rows currently ticked, in the order the menu draws them.
List<String> _checkedThemeLabels(List<String> labels) =>
    <String>[for (final label in labels) if (_isChecked(label)) label];

/// The `AndroidManifest.xml` of a resolved package, found through the package
/// config rather than through a path written into the test.
///
/// **A path written into a test is a test that can only pass on the machine
/// that wrote it.** The version of this check that named
/// `D:\pub-cache\...\url_launcher_android-6.3.33\...` was green on Windows for
/// every round of this project and red on the Linux CI runner, where the file
/// it was guarding simply did not exist -- so the guard was guarding nothing on
/// half the machines that ran it.
///
/// The package config names the version that was **actually resolved**, so this
/// is a stronger check than the hardcoded path was: it cannot drift away from
/// the dependency without going red. It is also portable, so the same
/// assertion runs on every platform the project builds on.
///
/// Returns null when the package is not in the config at all -- the caller
/// asserts on that, because a check that quietly resolves to nothing is the
/// failure this function exists to prevent.
String? _resolvedManifestOf(String packageName) {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final Object? decoded = jsonDecode(config.readAsStringSync());
  if (decoded is! Map) return null;
  final Object? packages = decoded['packages'];
  if (packages is! List) return null;

  for (final Object? entry in packages) {
    if (entry is! Map) continue;
    if (entry['name'] != packageName) continue;
    final Object? root = entry['rootUri'];
    if (root is! String) return null;

    // `rootUri` is normally an absolute `file:` URI; when it is relative it is
    // relative to the config file itself.
    var rootUri = Uri.parse(root);
    if (!rootUri.hasScheme) {
      rootUri = config.uri.resolveUri(rootUri);
    }
    final manifest = Directory.fromUri(rootUri)
        .uri
        .resolve('android/src/main/AndroidManifest.xml');
    return manifest.toFilePath();
  }
  return null;
}