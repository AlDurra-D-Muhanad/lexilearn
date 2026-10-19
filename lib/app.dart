import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';


import 'data/vocab_repository.dart';
import 'ui/dictionary/dictionary_controller.dart';
import 'ui/home_shell.dart';
import 'ui/link/external_link.dart';
import 'ui/settings/app_settings_controller.dart';
import 'ui/theme/app_theme.dart';
import 'ui/wallpaper/wallpaper_catalog.dart';

/// The application root.
///
/// Takes an already-built [VocabRepository] rather than opening one itself, so
/// the widget tests can hand it an in-memory database and the composition root
/// in `main.dart` can hand it a real one. Beyond that chrome — the brand's two
/// themes, the app title, the app-wide text direction and the navigator
/// observers — this widget owns the two things every screen shares and nothing
/// else owns: **the user's theme choice** and **the seam that hands a link to
/// another app**.
///
/// **Why it is a `StatefulWidget` now, and what that costs.** It was a
/// `StatelessWidget` until the theme toggle needed somewhere to live, because a
/// controller that must be created once, read from `initState`, notified on
/// change and disposed with its owner is exactly what a `State` is for. The cost
/// is one `initState`/`dispose` pair and the fact that the widget is no longer
/// `const`-constructible from outside; nothing else in the file changed shape.
///
/// **[openUrl] is a seam, not a hook.** The app installs
/// [openWithUrlLauncher] — the real `url_launcher` — and a test hands in a
/// closure that records the `Uri`. That is the same arrangement as
/// `PickJsonFile` in `packs_controller.dart`, one level up: the awkward
/// environment sits behind one named type and nothing below this line knows
/// which implementation it got.
class LexiLearnApp extends StatefulWidget {
  const LexiLearnApp({
    super.key,
    required this.repository,
    this.openUrl,
    this.navigatorObservers,
    this.wallpaperSeed,
    this.dictionary,
  });

  /// The dictionary's own controller: the copy onto the device, its progress,
  /// and the engine once it is there.
  ///
  /// **Optional, and the app works without it.** The dictionary is 26 MB and
  /// the copy is off the UI path, so the app opens, navigates and shows the
  /// home screen while it happens — and a build with no dictionary at all
  /// still opens, still shows the starter pack and still works. A controller
  /// that was not handed in is an **idle** one, which never starts.
  final DictionaryController? dictionary;

  /// Seeds the rotating photograph. **A seam for `golden_test.dart` only** -
  /// null is the app's own behaviour, and the argument is threaded straight
  /// through to the two screens that draw one. See `HomeShell.wallpaperSeed`.
  final int? wallpaperSeed;

  final VocabRepository repository;

  /// How a link leaves the app. Null means [openWithUrlLauncher].
  final OpenExternalUrl? openUrl;

  /// Observers attached to the root navigator.
  ///
  /// **Added for one test's sake and kept because it is the only way to observe
  /// the root route at all.** "Back from Home must reach the system" is not a
  /// tree state — by then there is no tree, because on a device the process is
  /// gone — so the only evidence available in a widget test is a
  /// `NavigatorObserver` seeing `didPop` for the shell's route. Absent by default,
  /// which is why every screen test is unaffected by it existing.
  final List<NavigatorObserver>? navigatorObservers;

  @override
  State<LexiLearnApp> createState() => _LexiLearnAppState();
}

class _LexiLearnAppState extends State<LexiLearnApp> {
  late final AppSettingsController _settings =
      AppSettingsController(repository: widget.repository);

  /// The dictionary controller, or an idle one.
  ///
  /// **Built here and not handed in whole**, so a screen can reach it through
  /// the provider and a test that mounts the app without a dictionary still
  /// has one to read. The idle controller has no seams — no asset loader, no
  /// file system, no database factory — so its `start()` returns at once and
  /// nothing is installed.
  late final DictionaryController _dictionary = widget.dictionary ??
      DictionaryController.idle();

  /// Whether this state made the dictionary controller, and so owns it.
  ///
  /// **A controller that was handed in is not disposed here.** The app is
  /// given one by `main.dart`, which built it with the asset loader and the
  /// file system; disposing it at the end of the app's life would tear down
  /// something the caller still holds. The idle one this state creates is its
  /// own, and its own is disposed.
  bool get _ownsDictionary => widget.dictionary == null;

  @override
  void initState() {
    super.initState();
    // The image-cache ceiling, in the one place every run of this app passes
    // through. `Wallpapers` are the only bitmaps this app decodes, so the shared
    // ceiling can be set to exactly three of them — 6,998,400 bytes against the
    // 100 MB default. Idempotent, so a test may mount this twenty times. The
    // arithmetic is in `lib/ui/wallpaper/wallpaper_catalog.dart`; it is
    // asserted in `test/ui/wallpaper_catalog_test.dart`.
    configureWallpaperImageCache();
    // Fired and not awaited, for the reason the class doc of the controller
    // gives: the first frame must not wait on the database, and the mode it
    // starts at is exactly the one this app used before the controller existed.
    _settings.load().ignore();
    // **The dictionary's 26 MB copy, fired and not awaited.** This is the
    // whole of ruling E's first clause: the copy happens off the UI path, the
    // app opens and navigates while it runs, and the home screen says what is
    // happening rather than showing an empty search with no explanation.
    _dictionary.start().ignore();
  }

  @override
  void dispose() {
    _settings.dispose();
    if (_ownsDictionary) _dictionary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openUrl = widget.openUrl ?? openWithUrlLauncher;

    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<VocabRepository>.value(value: widget.repository),
        // Both seams are provided **above** `MaterialApp`, not inside it, so a
        // screen can reach them and so `LexiLearnApp` itself can be tested
        // without standing up a navigator first.
        Provider<OpenExternalUrl>.value(value: openUrl),
        // `ChangeNotifierProvider.value`, not `Provider.value`: provider
        // **asserts** against a `Listenable` in a plain `Provider` and names
        // `ChangeNotifierProvider` in the message — measured, not guessed, and it
        // took down the whole tree at `test/ui/home_shell_test.dart:128` when
        // this was a `Provider`. `.value` because the controller is created in
        // [initState] and disposed in [dispose]; the provider must not own it.
        ChangeNotifierProvider<AppSettingsController>.value(value: _settings),
        // **The dictionary, the same shape as the settings controller**: a
        // `ChangeNotifier` owned by this state, provided above the
        // `MaterialApp` so a screen can reach it. `ChangeNotifierProvider.value`
        // and not `Provider.value` for the reason the comment above gives —
        // provider asserts against a `Listenable` in a plain `Provider`.
        ChangeNotifierProvider<DictionaryController>.value(value: _dictionary),
      ],
      // `ListenableBuilder` rather than `Consumer` on purpose: the *only* thing
      // that depends on the controller is `themeMode` below, and rebuilding the
      // whole `MaterialApp` on a notification is what lets a mode change repaint
      // every screen at once — which is the point.
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, child) => MaterialApp(
          title: 'LexiLearn',
          // A development affordance. It would otherwise be baked into the
          // golden reference image and into store screenshots.
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          // **The one line the theme toggle exists for.** It was absent before,
          // which resolves to Material's own default of `ThemeMode.system` — so
          // this is value-preserving on a device with nothing stored, and it is
          // what makes the value `AppSettingsController` reads back out of SQLite
          // do anything at all.
          themeMode: _settings.mode,
          navigatorObservers:
              widget.navigatorObservers ?? const <NavigatorObserver>[],
          // Arabic-first RTL. Set once here rather than per screen, so a route
          // pushed later — the word detail view, a quiz, the about screen — inherits
          // it instead of having to remember. The bottom bar draws from the right
          // because of this line, which is where the brand artwork puts it.
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
          home: HomeShell(
            repository: widget.repository,
            wallpaperSeed: widget.wallpaperSeed,
          ),
        ),
      ),
    );
  }
}