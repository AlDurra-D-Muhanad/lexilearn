import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';

/// The key the theme choice is stored under.
///
/// One constant, so the string that reaches SQLite is written once. A test that
/// read the row out of the database by hand would otherwise be quoting a second
/// copy of it.
const String themeModeSettingKey = 'theme_mode';

/// The stored spelling of [ThemeMode.system], [ThemeMode.light] and
/// [ThemeMode.dark].
///
/// **The `name` of the enum, not an index and not a hand-written word.** An index
/// would silently repoint at a different mode if a future Flutter inserted one;
/// a hand-written word would have to be kept in step with [themeModeFromSetting]
/// by hand. `ThemeMode.name` is the enum's own answer and Dart guarantees it is
/// unique, so [themeModeFromSetting] is total over what [themeModeSetting] can
/// write.
String themeModeSetting(ThemeMode mode) => mode.name;

/// Reads back what [themeModeSetting] wrote, or null when nothing was stored
/// **or when what was stored is not a mode this build knows**.
///
/// Null rather than a fallback to [ThemeMode.system] for the unknown case on
/// purpose: "never chosen" and "chosen, but the string is from a build that had
/// a fourth mode" are the same thing to the caller — follow the system until
/// told otherwise — and collapsing them here means one branch instead of two
/// that cannot disagree.
ThemeMode? themeModeFromSetting(String? stored) {
  for (final mode in ThemeMode.values) {
    if (mode.name == stored) return mode;
  }
  return null;
}

/// The user's theme choice, and the one thing that has to survive a restart.
///
/// **A setting, not a one-shot flip.** The user reported having to change the
/// *system* theme to get a dark app; flipping the app's own `themeMode` for the
/// current session would answer that complaint for exactly as long as the
/// process lives and then lose it. So the choice goes to the same store
/// everything else in this app persists to — SQLite, through `VocabRepository`
/// — rather than to a second mechanism. See `lib/data/settings_dao.dart` for why
/// not `shared_preferences`.
///
/// **[ThemeMode.system] stays a first-class option.** It is the default, it is
/// the only mode that survives a user who never touches the menu, and it is the
/// value a fresh install reports — so "the app follows my phone" keeps working
/// for everyone who never asked for anything else.
///
/// **The read is fired from `initState` and starts at [ThemeMode.system], and
/// that is deliberate rather than optimistic.** `LexiLearnApp` owns this
/// controller, so a user who chose `داكن` gets one frame of system theme before
/// the row is read. That is the same trade every controller in this app makes —
/// `PacksController`, `StatsController`, `SearchController` and `QuizController`
/// all publish a placeholder until their read lands — and it means a first frame
/// is never blocked on the database. Crucially it is also *no worse than today*:
/// before this controller existed `themeMode` was never set at all, which is
/// `ThemeMode.system`, so an unread row is exactly the previous behaviour.
///
/// **Every failure is swallowed and leaves the mode at [ThemeMode.system].** A
/// theme is not worth a crash and not worth an error screen, and a database that
/// cannot be read at start-up is a reason to follow the system rather than a
/// reason to fail the launch. Pinned by *a failed read leaves the controller on
/// the system theme* in `test/ui/app_settings_test.dart`.
///
/// **The claim is about this class, not about the app surviving an unreadable
/// database**, and the difference is measured rather than assumed. That test was
/// first written against the whole app over a closed database and threw — not
/// from this read, but from `HomeShell._loadActivePack`, which issues its own
/// unguarded query from `initState`. So "the app starts anyway" is false today
/// for a reason that has nothing to do with the theme, and widening this comment
/// to claim it would be a comment asserting a falsehood. Guarding the shell's own
/// read is a separate task and is not this file's.
class AppSettingsController extends ChangeNotifier {
  /// [_repository] is an initializing formal, which `prefer_initializing_formals`
  /// asks for and which changes no call site: on a **named** parameter Dart
  /// exposes `this._x` publicly as `x`, so every
  /// `AppSettingsController(repository: …)` still names it the same way. The
  /// same choice, and the same reason, as `PacksController`.
  AppSettingsController({required this._repository});

  final VocabRepository _repository;

  ThemeMode _mode = ThemeMode.system;

  /// Set in [dispose]. See [_notifyIfAlive].
  bool _disposed = false;

  /// The mode the app is rendering in right now.
  ThemeMode get mode => _mode;

  /// Reads the stored choice.
  ///
  /// Never awaited by the widget that fires it — see the class doc for why the
  /// first frame does not wait on it.
  Future<void> load() async {
    try {
      final stored = await _repository.setting(themeModeSettingKey);
      // Absent, unreadable and unrecognised all land here as null, and all three
      // mean the same thing to a user: they never picked.
      final storedMode = themeModeFromSetting(stored);
      if (storedMode == null || storedMode == _mode) return;
      _mode = storedMode;
      _notifyIfAlive();
    } on Object {
      // Deliberately silent. See the class doc: the mode is already the value
      // this app used before the controller existed.
    }
  }

  /// Switches to [mode], in this session and on every one after it.
  ///
  /// **The in-memory change happens first and the write second, deliberately.**
  /// Tapping `داكن` must repaint the app immediately; making the user wait on a
  /// SQLite round trip to see the screen change would be the same complaint the
  /// toggle was added to answer. A write that then fails leaves the session
  /// themed as asked and the next start back on the system — a lost preference,
  /// which is a far smaller failure than a frozen UI, and the reason this is
  /// stated rather than left to be discovered.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _notifyIfAlive();
    try {
      await _repository.setSetting(themeModeSettingKey, themeModeSetting(mode));
    } on Object {
      // Same trade as above: a preference that did not persist is not worth an
      // error screen.
    }
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}