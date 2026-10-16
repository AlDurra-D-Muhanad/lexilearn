import 'package:flutter/foundation.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/stats_summary.dart';

/// Everything the Stats screen renders, and the two things it can do.
///
/// **The pack is fixed at construction and never re-read.** `StatsSummary` is
/// scoped to one pack, and so is every query behind it — `stats(packKey)` and
/// `resetProgress(packKey)` both filter on `pack_key`, which is the whole reason
/// two packs may hold the same word ids without sharing a word count. Holding
/// the key on the controller rather than passing it to each call is what makes
/// that scoping impossible to forget at a call site: there is no call to forget
/// an argument on. `test/ui/stats_controller_test.dart` → *pack scoping* gives
/// both packs the same entry ids so the filter is the only thing separating them.
///
/// **Every notification goes through [_notifyIfAlive],** for the same reason
/// `QuizController` and `SearchController` carry one: `load()` is fired from
/// `initState`, so the read is still in flight when a fast tap on Back tears the
/// route down, and `ChangeNotifier` asserts on `notifyListeners()` after
/// `dispose()` rather than doing nothing. The plan's version of this class
/// called `notifyListeners()` bare at both ends of `load()`.
class StatsController extends ChangeNotifier {
  /// Both fields are initializing formals, which `prefer_initializing_formals`
  /// asks for and which changes no call site: on a **named** parameter Dart
  /// exposes `this._x` publicly as `x`, so every `StatsController(repository: …,
  /// packKey: …)` in the app and the tests still names it the same way. Measured
  /// rather than assumed — a probe passing `_repository:` instead fails to
  /// compile with "No named parameter with the name '_repository'", and the same
  /// probe passing `repository:` compiles and runs.
  StatsController({
    required this._repository,
    required this._packKey,
  });

  final VocabRepository _repository;
  final String _packKey;

  StatsSummary _summary = StatsSummary.empty;
  bool _isLoading = true;
  Object? _error;

  /// Set in [dispose]. See [_notifyIfAlive].
  bool _disposed = false;

  /// The last thing that was read. `StatsSummary.empty` before the first read,
  /// after a read that failed, and after a reset.
  StatsSummary get summary => _summary;

  bool get isLoading => _isLoading;

  /// The last read or reset failure, or null.
  ///
  /// Kept apart from [summary] on purpose: an empty summary after a *failed*
  /// read and an empty summary after a *fresh install* are the same numbers, and
  /// only one of them is true. A screen that rendered "no answers yet" for both
  /// would tell a user with a broken database that they had never studied.
  Object? get error => _error;

  /// Re-reads this pack's summary.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      _summary = await _repository.stats(_packKey);
    } on Object catch (error) {
      _summary = StatsSummary.empty;
      _error = error;
    } finally {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  /// Clears this pack's word progress **and** its session history, then re-reads.
  ///
  /// Both halves are the repository's, in one transaction — a reset that zeroed
  /// the tiles and left "recent sessions" standing is exactly what the user
  /// would read as "Reset did nothing".
  ///
  /// A failure is recorded rather than thrown, and the summary is deliberately
  /// **not** blanked: the screen still shows the last thing that really was
  /// read, with the error beside it.
  Future<void> reset() async {
    _error = null;
    try {
      await _repository.resetProgress(_packKey);
    } on Object catch (error) {
      _error = error;
      _notifyIfAlive();
      return;
    }
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// `notifyListeners()` after [dispose] throws in debug, and the read this
  /// controller issues from `initState` can land after the route that owns it is
  /// gone. Same guard, and the same name, as `SearchController` and
  /// `QuizController` — and measured, not assumed: with the guard written but the
  /// `dispose()` override forgotten, `a load that lands after dispose does not
  /// throw` failed with "A StatsController was used after being disposed" out of
  /// `load`'s `finally`.
  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }
}