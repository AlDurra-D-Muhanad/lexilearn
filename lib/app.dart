import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/vocab_repository.dart';
import 'ui/home_shell.dart';
import 'ui/link/external_link.dart';
import 'ui/settings/app_settings_controller.dart';
import 'ui/theme/app_theme.dart';

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
  });

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

  @override
  void initState() {
    super.initState();
    // Fired and not awaited, for the reason the class doc of the controller
    // gives: the first frame must not wait on the database, and the mode it
    // starts at is exactly the one this app used before the controller existed.
    _settings.load().ignore();
  }

  @override
  void dispose() {
    _settings.dispose();
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
          home: HomeShell(repository: widget.repository),
        ),
      ),
    );
  }
}