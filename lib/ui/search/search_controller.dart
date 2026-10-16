import 'package:flutter/foundation.dart';

import '../../data/vocab_repository.dart';
import '../../domain/vocab_entry.dart';

/// The state behind the Home screen's search field.
///
/// Holds no widget and no timer: the field's debounce belongs to the screen,
/// because that is what decides how long a human is likely to take between
/// keystrokes. What lives here is the part that is worth testing on its own —
/// what the user has typed, what came back, whether a read is running, and
/// whether it failed.
class SearchController extends ChangeNotifier {
  SearchController({required this.repository});

  /// Public and final rather than a private field set from a named parameter:
  /// the interface later tasks were given names that parameter `repository`, and
  /// a private named parameter is not legal Dart, so the field has to carry the
  /// same name for `this.repository` to be an initialising formal.
  final VocabRepository repository;

  String _query = '';

  /// The pack the last search ran against.
  ///
  /// Remembered rather than passed every time: after the user switches packs the
  /// screen re-runs the query it already has, and `search` therefore takes
  /// `packKey` as optional and falls back to this.
  String _packKey = '';

  List<VocabEntry> _results = const <VocabEntry>[];
  bool _isSearching = false;
  Object? _error;

  /// `ChangeNotifier` has no public `isDisposed`, and its `notifyListeners`
  /// throws once disposed. The Home screen disposes this controller while a
  /// debounced read may still be in flight, so the flag is tracked here and
  /// every notification goes through [_notifyIfAlive].
  bool _disposed = false;

  /// What the user typed, verbatim — not normalised. The field echoes this back,
  /// so normalising it would rewrite the user's typing under their cursor.
  String get query => _query;

  List<VocabEntry> get results => _results;
  bool get isSearching => _isSearching;
  Object? get error => _error;

  /// Runs [rawQuery] against [packKey], or against the last pack used.
  ///
  /// Never throws: a missing pack or an unreadable database lands in [error]
  /// with an empty [results], because this is called straight from a timer in a
  /// widget and an escaping exception would take the screen down with it.
  Future<void> search(String rawQuery, {String? packKey}) async {
    _query = rawQuery;
    _packKey = packKey ?? _packKey;
    _isSearching = true;
    _error = null;
    _notifyIfAlive();
    try {
      _results = await repository.search(packKey: _packKey, query: _query);
    } on Object catch (error) {
      _results = const <VocabEntry>[];
      _error = error;
    } finally {
      _isSearching = false;
      _notifyIfAlive();
    }
  }

  /// Empties the query and the results. Does not re-run the search: clearing the
  /// field is the screen's cue to go back to its own empty state, not to query
  /// the database for everything again.
  void clear() {
    _query = '';
    _results = const <VocabEntry>[];
    _error = null;
    _notifyIfAlive();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }
}
