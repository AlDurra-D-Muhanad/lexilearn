import 'package:flutter/foundation.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';

/// One thing in the dictionary's result list.
///
/// **Two kinds, and the difference is the point.** A [DictionaryWordItem] is
/// a word the query reached: the user typed it, or typed something that
/// *contains* it as a synonym, and the app is showing them the word. A
/// [DictionarySuggestionItem] is a word the query might have meant: the app
/// is **offering** it, and the card shows what was typed beside it, so the
/// user decides.
///
/// A memorisation app that silently shows `child` for `childern` teaches the
/// user that the app knows what they meant, which is exactly the belief that
/// makes a typo permanent.
sealed class DictionarySearchItem {
  const DictionarySearchItem();
}

/// A word the query reached.
final class DictionaryWordItem extends DictionarySearchItem {
  const DictionaryWordItem({required this.entry, this.arabic});

  final DictionaryEntry entry;

  /// The Arabic that matched, when the query was Arabic.
  final String? arabic;

  @override
  String toString() => 'DictionaryWordItem(${entry.word})';
}

/// A word the query might have meant.
final class DictionarySuggestionItem extends DictionarySearchItem {
  const DictionarySuggestionItem({
    required this.typed,
    required this.entry,
    required this.reason,
  });

  /// What the user typed, verbatim.
  final String typed;

  /// The word being offered.
  final DictionaryEntry entry;

  /// Why it is being offered: `stem` or `spelling`.
  final String reason;

  @override
  String toString() =>
      'DictionarySuggestionItem($typed -> ${entry.word}, $reason)';
}

/// The state behind the dictionary search.
///
/// **The engine is the only thing it holds**, and the engine is a data-layer
/// object that knows about headwords and senses. Everything the screen draws
/// is here: the items, whether a read is in flight, and the failure.
class DictionarySearchController extends ChangeNotifier {
  DictionarySearchController({required this.engine});

  final DictionaryEngine engine;

  String _query = '';
  List<DictionarySearchItem> _items = const <DictionarySearchItem>[];
  bool _isSearching = false;
  Object? _error;
  bool _disposed = false;

  /// What the user typed, verbatim.
  String get query => _query;

  /// The results, in rank order.
  List<DictionarySearchItem> get items => _items;

  /// Whether a read is in flight.
  bool get isSearching => _isSearching;

  /// The last failure.
  Object? get error => _error;

  /// Runs [rawQuery] against the dictionary.
  ///
  /// **Never throws.** This is called straight from a debounce timer in a
  /// widget, and an escaping exception would take the screen down with it.
  Future<void> search(String rawQuery) async {
    _query = rawQuery;
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      _items = const <DictionarySearchItem>[];
      _error = null;
      _notifyIfAlive();
      return;
    }
    _isSearching = true;
    _error = null;
    _notifyIfAlive();
    try {
      _items = _writesArabic(trimmed)
          ? await _searchArabic(trimmed)
          : await _searchEnglish(trimmed);
    } on Object catch (error) {
      _items = const <DictionarySearchItem>[];
      _error = error;
    } finally {
      _isSearching = false;
      _notifyIfAlive();
    }
  }

  /// Empties the query and the results. Does not re-run the search: clearing
  /// the field is the screen's cue to go back to its own empty state.
  void clear() {
    _query = '';
    _items = const <DictionarySearchItem>[];
    _error = null;
    _notifyIfAlive();
  }

  /// The Arabic path: a **ranked list**, because one Arabic key is shared by
  /// many senses.
  ///
  /// **Every hit carries the Arabic that matched**, not only the headword. A
  /// list of headwords with no Arabic beside them tells the user nothing
  /// about which of the senses matched, and the dictionary's Arabic is
  /// stored as comma-separated synonym lists.
  Future<List<DictionarySearchItem>> _searchArabic(String query) async {
    final hits = await engine.searchArabic(query);
    return <DictionarySearchItem>[
      for (final hit in hits)
        DictionaryWordItem(entry: hit.entry, arabic: hit.arabic),
    ];
  }

  /// The English path: an exact word, a suggestion, or nothing at all.
  ///
  /// **A stem is never shown as if the user had typed it.** The lookup hands
  /// back a sealed hierarchy, and the stem case becomes a *suggestion card*
  /// that shows what was typed beside the word being offered. The spelling
  /// case is the same shape: the user typed something that is not a word, and
  /// the app offers the nearest thing that is.
  Future<List<DictionarySearchItem>> _searchEnglish(String query) async {
    final lookup = await engine.lookupEnglish(query);
    if (lookup is ExactWord) {
      return <DictionarySearchItem>[
        DictionaryWordItem(
          entry: lookup.entry,
          arabic: _firstArabic(lookup.entry),
        ),
      ];
    }
    if (lookup is StemSuggestion) {
      return <DictionarySearchItem>[
        DictionarySuggestionItem(
          typed: lookup.typed,
          entry: lookup.entry,
          reason: 'stem',
        ),
      ];
    }
    // Nothing matched. The near-misses come first, and the type-ahead
    // follows them.
    final near = await engine.spellingSuggestions(query);
    final prefix = await engine.autocomplete.search(query);
    return <DictionarySearchItem>[
      for (final suggestion in near.suggestions)
        DictionarySuggestionItem(
          typed: query,
          entry: suggestion.entry,
          reason: 'spelling',
        ),
      for (final entry in prefix)
        DictionaryWordItem(entry: entry, arabic: _firstArabic(entry)),
    ];
  }

  /// The first Arabic a headword carries, or null.
  static String? _firstArabic(DictionaryEntry entry) {
    for (final sense in entry.senses) {
      final arabic = sense.arabic;
      if (arabic != null && arabic.trim().isNotEmpty) return arabic;
    }
    return null;
  }

  /// Whether [value] carries an Arabic letter.
  ///
  /// **The same block the app's other screens use** - U+0600 to U+06FF, plus
  /// the Arabic Supplement and Extended-A blocks - so "is this Arabic?" is
  /// answered the same way everywhere it is asked.
  static bool _writesArabic(String value) => value.runes.any(
        (rune) => (rune >= 0x0600 && rune <= 0x06FF) ||
            (rune >= 0x0750 && rune <= 0x077F) ||
            (rune >= 0x08A0 && rune <= 0x08FF),
      );

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
