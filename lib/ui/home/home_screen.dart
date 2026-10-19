import 'dart:async';
import 'dart:math';

// `SearchController` is also a Material widget (`search_anchor.dart`), so the
// app's own one is this file's `SearchController` and Material's is hidden.
// Renaming either would break the interface later tasks were told to depend on.
import 'package:flutter/material.dart' hide SearchController;
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/word_of_the_day.dart';
import 'package:lexilearn/ui/dictionary/dictionary_controller.dart';
import 'package:lexilearn/ui/dictionary/dictionary_search_controller.dart';
import 'package:lexilearn/ui/dictionary/dictionary_word_screen.dart';
import 'package:lexilearn/ui/favorites/favorites_screen.dart';
import 'package:lexilearn/ui/home_shell.dart';
import 'package:lexilearn/ui/search/search_controller.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';
import 'package:lexilearn/ui/stats/stats_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/wallpaper/nature_photo.dart';
import 'package:lexilearn/ui/wallpaper/nature_rotation.dart';
import 'package:lexilearn/ui/wallpaper/wallpaper_scrim.dart';
import 'package:provider/provider.dart';

/// The chrome strings, taken from `docs/design/brand-reference.png`.
const String _greeting = 'مرحباً بك!';
const String _subheading = 'كل كلمة جديدة تقرّبك من هدفك';
const String _searchHint = 'ابحث عن كلمة...';
const String _wordOfTheDayLabel = 'Word of the Day';
const String _meaningButton = 'معرفة المعنى';
const String _clearTooltip = 'مسح';
const String _noResults = 'لا توجد نتائج. جرّب جزءاً من الكلمة.';
const String _searchFailed = 'تعذّر البحث.';
const String _searching = 'جارٍ البحث…';
const String _preparingDictionary = 'جارٍ تجهيز المعجم…';

/// The brand's first destination: the greeting, the word of the day, the search
/// field, and the 2×2 quick-launch grid.
///
/// **Search is a field on this screen, not a destination.** The artwork's Home
/// phone draws the field directly under the heading and the grid under the word
/// of the day, with no separate search screen anywhere in the bar, so there is
/// nothing to navigate to when the user types.
///
/// Typed into the field, the same body becomes the result list. Swapping rather
/// than stacking is deliberate: the dashboard is a dashboard, and pushing a list
/// over it would leave a search field half-hidden behind the results it
/// produced.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.packKey,
    required this.onPackSelected,
    required this.onOpenWord,
    this.onOpenDictionaryWord,
    this.wallpaperSeed,
  });

  /// Seeds the rotation that chooses which photograph the word-of-the-day card
  /// opens on. **Null means the app's own behaviour** — a fresh [Random], so two
  /// launches begin on different photographs.
  ///
  /// The same seam `FlashcardController.random` and `QuizController.random`
  /// already are, and for the same reason: `golden_test.dart` photographs this
  /// screen, and a reference image that shows a different photograph on every
  /// regeneration is a reference nobody can compare against.
  ///
  /// **An integer, not a `Random`, and the difference is not cosmetic.** A shared
  /// generator is consumed in *construction order*, so whichever rotation was
  /// built first takes draw one and the other takes draw two — and which is
  /// which depends on the navigation. Measured, not argued: with one `Random(3)`
  /// handed to both surfaces, `nextInt(8)` returns 7 and then 7 again, so a
  /// **light** reference image passed by coincidence, while `nextInt(6)` returns
  /// 5 on the second draw and the **dark** one failed loudly. An integer gives
  /// every rotation its own generator, so each is reproducible on its own.
  final int? wallpaperSeed;

  /// The pack every part of this screen is scoped to. Empty until `HomeShell`
  /// resolves it, and empty for good when nothing is installed.
  final String packKey;

  /// Switches the active pack.
  ///
  /// Handed to this screen by the shell alongside every other destination, and
  /// deliberately not called from here yet: the pack picker is Task 13's, and
  /// inventing a second one on Home would put the same list in two places. What
  /// Home *does* do with [packKey] is show it — the pill in the header — so the
  /// screen is visibly scoped to something rather than reading as a dead end.
  final ValueChanged<String> onPackSelected;

  /// Opens one word. Task 14 points this at `WordDetailScreen`; until then
  /// `HomeShell` holds a no-op.
  final ValueChanged<VocabEntry> onOpenWord;

  /// Opens one dictionary word.
  ///
  /// **Optional, and it is a separate door rather than a wider one.** A
  /// dictionary entry and a pack entry are different things — the first has
  /// senses, glosses and examples, the second has a translation and a note —
  /// and a screen that has to guess which it is holding is a screen that will
  /// guess wrong. Null means "there is no dictionary here", which is the
  /// truth for a build without one.
  final ValueChanged<DictionaryEntry>? onOpenDictionaryWord;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SearchController _search;
  final TextEditingController _field = TextEditingController();

  Timer? _debounce;

  /// The dictionary's controller, so the screen can say how far its copy has
  /// got and know when its engine is there.
  late final DictionaryController _dictionary;

  /// The dictionary's own search, or null while there is no dictionary.
  ///
  /// **Created when the engine arrives and disposed when it does not.** The
  /// dictionary is 26 MB and its copy is off the UI path, so for the first
  /// few seconds of a first launch there is no engine and therefore no
  /// dictionary search — and the screen says so rather than showing an empty
  /// result list with no explanation.
  DictionarySearchController? _dictionarySearch;

  /// **Home's rotating photograph.**
  ///
  /// Owned here and not inside the card, for two reasons that are the same
  /// reason: a rotation built in `_WordOfTheDayCard` would be constructed again
  /// on every rebuild of the card and would therefore **re-roll its starting
  /// index every time** — which is exactly the flicker the user would see on
  /// each hot rebuild. One instance per screen, created once, disposed in
  /// [dispose], is the whole of ruling E's "pick the index once per session and
  /// advance from it".
  ///
  /// **Timed, at `AppDurations.wallpaper`** — ten seconds, the user's own
  /// figure. It is the same class the flashcard deck drives by hand with
  /// `interval: null`; see `NatureRotation` for why they are two instances of
  /// one class rather than one of two.
  ///
  /// A private generator per rotation, from [HomeScreen.wallpaperSeed]. Null
  /// means `NatureRotation` builds its own, which is the app's real behaviour.
  Random? get _seededGenerator =>
      widget.wallpaperSeed == null ? null : Random(widget.wallpaperSeed!);

  /// **Null until the first `didChangeDependencies`, and built with the real
  /// brightness rather than corrected afterwards.** `initState` cannot read
  /// `Theme.of` — that is an inherited dependency, and taking one from
  /// `initState` is an assertion — so the first version constructed with a
  /// placeholder and let [didChangeDependencies] fix it. That drew the starting
  /// index **twice**, once per set, which is invisible on a device and fatal to
  /// reproducibility: with a seed, `Random(3).nextInt(8)` followed by
  /// `Random(3).nextInt(6)` is not `Random(3).nextInt(6)`, and the golden
  /// capture's assertion of which photograph it photographed failed on exactly
  /// the dark shots. Building it once, correctly, is both simpler and
  /// reproducible.
  NatureRotation? _rotation;

  /// The whole active pack, read once per pack switch.
  ///
  /// Held separately from the search results because the word of the day must be
  /// picked from the *pack*, not from whatever happens to be on screen: a
  /// filtered list would give the card a different word depending on the last
  /// thing typed.
  List<VocabEntry> _entries = const <VocabEntry>[];

  @override
  void initState() {
    super.initState();
    _search = SearchController(repository: context.read<VocabRepository>())
      ..addListener(_onSearchChanged);
    // `context.read` is safe in `initState` — it does not subscribe — which is
    // the same reason the repository is read there.
    _dictionary = context.read<DictionaryController>();
    _dictionary.addListener(_onDictionaryChanged);
    _syncDictionarySearch();
    _loadPack(widget.packKey);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // The rotation's timer and its lifecycle observer, in the same place as
    // everything else this state owns. `NatureRotation.dispose` cancels the
    // timer and marks the controller disposed, so a tick that was already in
    // flight when the route popped is a no-op rather than a notification into a
    // dead `State`.
    _rotation?.dispose();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    _dictionarySearch
      ?..removeListener(_onSearchChanged)
      ..dispose();
    _dictionary.removeListener(_onDictionaryChanged);
    _field.dispose();
    super.dispose();
  }

  /// Creates or disposes the dictionary's search, as the engine comes and
  /// goes.
  void _syncDictionarySearch() {
    final engine = _dictionary.engine;
    if (engine == null) {
      final existing = _dictionarySearch;
      if (existing == null) return;
      _dictionarySearch = null;
      existing
        ..removeListener(_onSearchChanged)
        ..dispose();
      return;
    }
    if (_dictionarySearch != null) return;
    _dictionarySearch = DictionarySearchController(engine: engine)
      ..addListener(_onSearchChanged);
  }

  /// The dictionary became ready, or its copy moved on.
  void _onDictionaryChanged() {
    if (!mounted) return;
    _syncDictionarySearch();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The rotation's set follows the theme, and this is the only place a
    // `State` may read an inherited widget it did not already depend on. It
    // runs before the first `build`, so a dark phone never renders one frame of
    // the light set, and **the very first call builds it with the brightness it
    // is being created for** rather than correcting one built on a guess.
    // `NatureRotation.brightness` is idempotent, so the repeated calls this
    // method gets from ordinary rebuilds do nothing.
    final brightness = Theme.of(context).brightness;
    final existing = _rotation;
    if (existing == null) {
      _rotation = NatureRotation(
        brightness: brightness,
        interval: AppDurations.wallpaper,
        random: _seededGenerator,
      );
      return;
    }
    existing.brightness = brightness;
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packKey == widget.packKey) return;
    _loadPack(widget.packKey);
    // Re-run whatever is in the field against the new pack rather than dropping
    // the user's query on the floor. `SearchController` remembers the key, so
    // this does not have to carry one.
    if (_field.text.isNotEmpty) {
      _debounce?.cancel();
      _run(_field.text);
    }
  }

  Future<void> _loadPack(String packKey) async {
    final repository = context.read<VocabRepository>();
    // An empty key is the shell's start-up window, not a missing pack: it must
    // not be asked for, because the read would answer "no such pack" and the
    // screen would flash an error before it has ever shown anything.
    //
    // The `try` is `favorites_screen.dart:133-148`'s, for `home_screen`'s reason:
    // this read is genuinely in flight while the first frame is built, so a back
    // that beats it -- or a teardown that closes the database under it -- leaves
    // sqflite throwing `Bad state: This database has already been closed` with
    // nobody to catch it. That arrived as an unhandled async error *after* the
    // test body had finished, which `flutter_test` counts as a failure. The
    // screen has no error state to invent one into, so an unmounted read is
    // simply dropped -- the same call `favorites_screen.dart:179-184` makes.
    List<VocabEntry> entries;
    try {
      entries = packKey.isEmpty
          ? const <VocabEntry>[]
          : await repository.entries(packKey);
    } catch (_) {
      return;
    }
    // Two pack switches in quick succession race here; only the last one wins.
    if (!mounted || widget.packKey != packKey) return;
    setState(() => _entries = entries);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    // Rebuilt immediately so the clear button appears with the first keystroke.
    // It reads `_field.text`, not `_search.query`: `SearchController` only
    // assigns the query inside `search()`, which is 250 ms away, so a button
    // driven by the controller appeared a quarter-second after the character it
    // was meant to erase. Measured: 0 clear buttons before typing, 0 at +100 ms,
    // 1 after the debounce.
    setState(() {});
    // 250 ms — `AppDurations.standard`, the brand's own "immediate" duration.
    // Long enough to coalesce a fast typist into one read, short enough that
    // the list still feels like it is following along. Without it every
    // keystroke is a round trip to SQLite.
    _debounce?.cancel();
    _debounce = Timer(AppDurations.standard, () => _run(value));
  }

  /// Runs the query against whichever search the active pack calls for.
  ///
  /// **Two searches, and the choice is the pack's.** The dictionary is the
  /// default pack, so the field searches the dictionary when the dictionary
  /// is the active pack and the pack's own words otherwise. Both are behind
  /// the same 250 ms debounce, so the field behaves the same either way.
  void _run(String value) {
    final dictionary = _dictionarySearch;
    if (widget.packKey == dictionaryPackKey && dictionary != null) {
      dictionary.search(value);
      return;
    }
    _search.search(value, packKey: widget.packKey);
  }

  /// Empties the field and goes straight back to the dashboard.
  ///
  /// Deliberately does not query for "everything": clearing a search is a cue to
  /// leave the results, and re-reading the pack to then throw the answer away is
  /// a read for nobody.
  void _clear() {
    _debounce?.cancel();
    _field.clear();
    _search.clear();
    _dictionarySearch?.clear();
  }

  /// Whether the body is showing results rather than the dashboard.
  ///
  /// Decided on the *trimmed* query, because a field holding nothing but spaces
  /// should stay on the dashboard instead of dumping the whole pack.
  bool get _hasQuery {
    final dictionary = _dictionarySearch;
    if (widget.packKey == dictionaryPackKey && dictionary != null) {
      return dictionary.query.trim().isNotEmpty;
    }
    return _search.query.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(packKey: widget.packKey),
            const SizedBox(height: AppSpacing.m),
            _SearchField(
              controller: _field,
              onChanged: _onChanged,
              onClear: _clear,
              // The field's own text, not `_hasQuery`: the clear button must
              // exist from the first keystroke, and `_search.query` only catches
              // up after the 250 ms debounce. `_hasQuery` still decides the
              // body swap below, where waiting is right — the results really are
              // the debounced read's, not the field's.
              hasQuery: _field.text.trim().isNotEmpty,
            ),
            const SizedBox(height: AppSpacing.m),
            Expanded(
              child: _hasQuery ? _results() : _dashboard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() {
    // `pick` throws on an empty list, by design. With no pack installed the
    // answer is "no card", not "an empty card" — and the grid still stands,
    // because the destinations do not depend on a pack being present.
    final wordOfTheDay =
        _entries.isEmpty ? null : WordOfTheDay.pick(_entries, DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.m,
      ),
      children: <Widget>[
        // **The dictionary's copy, said out loud.**
        //
        // The brief is explicit: the app must "never leave the app showing an
        // empty search with no explanation". So while the 26 MB copy runs,
        // the home screen says what is happening and how far it has got —
        // and the dashboard itself is still there underneath it.
        if (_dictionary.isInstalling) ...<Widget>[
          _DictionaryProgressBanner(controller: _dictionary),
          const SizedBox(height: AppSpacing.m),
        ],
        if (wordOfTheDay != null) ...<Widget>[
          _WordOfTheDayCard(
            entry: wordOfTheDay,
            onOpenWord: widget.onOpenWord,
            rotation: _rotation!,
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        _QuickLaunchGrid(
          packKey: widget.packKey,
          onOpenWord: widget.onOpenWord,
        ),
      ],
    );
  }

  Widget _results() {
    final dictionary = _dictionarySearch;
    if (widget.packKey == dictionaryPackKey && dictionary != null) {
      return _dictionaryResults(dictionary);
    }
    if (_search.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_search.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Text(
            _searchFailed,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_search.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Text(
            _noResults,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _search.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _EntryRow(
        entry: _search.results[index],
        onTap: widget.onOpenWord,
      ),
    );
  }

  /// The dictionary's results.
  ///
  /// **A list, and the list is long.** An Arabic key is shared by many
  /// senses — the most-shared key in this dictionary resolves to more
  /// headwords than a screen of twenty could hold — so the list is a scroll
  /// view with as many rows as the search found, and each row carries the
  /// headword **and** the Arabic that matched.
  ///
  /// **A suggestion is a card, never a row.** The card shows what was typed
  /// beside the word being offered, so the app never shows a different word
  /// as if the user had typed it.
  Widget _dictionaryResults(DictionarySearchController controller) {
    if (controller.isSearching) {
      // **A line of words, not a spinner.** An indeterminate
      // `CircularProgressIndicator` schedules frames for ever, so
      // `pumpAndSettle` never returns while one is on screen — and this
      // screen is the one the golden photographs. The same decision
      // `more_screen.dart` and `stats_screen.dart` make, and for the same
      // reason.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Text(
            _searching,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Text(
            _searchFailed,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    final items = controller.items;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Text(
            _noResults,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DictionarySuggestionItem) {
          return DictionarySuggestionCard(
            typed: item.typed,
            entry: item.entry,
            reason: item.reason,
            onOpen: () => _openDictionaryEntry(item.entry),
          );
        }
        final word = item as DictionaryWordItem;
        return _DictionaryRow(
          entry: word.entry,
          arabic: word.arabic,
          onTap: () => _openDictionaryEntry(word.entry),
        );
      },
    );
  }

  void _openDictionaryEntry(DictionaryEntry entry) {
    final open = widget.onOpenDictionaryWord;
    if (open == null) return;
    open(entry);
  }
}

/// The greeting, the active pack, and the brand's book mark.
///
/// Laid out directionally, so it reads right-to-left like the rest of the app.
/// The artwork draws its own header the other way round — the greeting pushed to
/// the left, the mark on the right — which is what a mock drawn left-to-right
/// looks like once it is inside an Arabic screen. Material's own convention is
/// followed here, as it is in the golden this file's screen is measured against.
class _Header extends StatelessWidget {
  const _Header({required this.packKey});

  final String packKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.m,
        AppSpacing.m,
        0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _subheading,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          _PackPill(packKey: packKey),
          const SizedBox(width: AppSpacing.s),
          const _BookMark(),
          const SizedBox(width: AppSpacing.s),
          // **The app's overflow menu, and the reason Home is not the only
          // destination that has one.** The user reported its absence here;
          // `AppOverflowMenu` records why all four destinations carry it
          // instead. It goes at the end of this row because this screen has no
          // `AppBar` and its header already ends with a control-shaped element,
          // so nothing above or below the fold moves. Pinned by
          // `test/ui/home_shell_test.dart` → *every destination carries the
          // overflow menu*.
          const AppOverflowMenu(),
        ],
      ),
    );
  }
}

/// The pack this screen is scoped to, named.
///
/// Not decoration: `HomeShell` resolves the active pack once and hands the same
/// key to all four destinations, so this is what proves the screen is reading
/// that state rather than standing still.
class _PackPill extends StatelessWidget {
  const _PackPill({required this.packKey});

  final String packKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Text(
        // A pack key is a Latin run, so it asks for Inter explicitly instead of
        // inheriting Tajawal's own Latin.
        packKey.isEmpty ? '—' : packKey,
        textDirection: TextDirection.ltr,
        style: AppText.latin.copyWith(fontSize: 12, color: secondary),
      ),
    );
  }
}

/// The amber book mark, on the circle the artwork draws it in.
class _BookMark extends StatelessWidget {
  const _BookMark();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // The artwork's amber circle at its own tint: the accent is too light to
        // fill a large disc without shouting, which is why it is a wash here and
        // the full-strength amber only on the glyph.
        color: AppColors.accent.withValues(alpha: isDark ? 0.24 : 0.16),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.menu_book_rounded, color: AppColors.accent, size: 22),
    );
  }
}

/// The search field: a full pill, per the theme's `inputDecorationTheme`.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasQuery,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Drives the clear button. The *controller's* text would do the same, but this
  /// is the state the screen already rebuilt for.
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        // No `AppText.latin` here, and deliberately. Every *static* Latin run in
        // the app names Inter, but this field holds whatever the user types, and
        // an Arabic query typed into an Inter-bound field renders as tofu — the
        // bilingual search the Python original had would be unreadable.
        //
        // The pill outline is not restated here either. `AppTheme`'s
        // `inputDecorationTheme` carries `enabledBorder` / `focusedBorder` /
        // `disabledBorder`, because Material 3 synthesises a filled field's
        // outline from those three and ignores `border` when they are null.
        // Pinned by `test/design/input_outline_test.dart`.
        decoration: InputDecoration(
          hintText: _searchHint,
          hintTextDirection: TextDirection.rtl,
          // Material puts the icon at the *start*, which is the right-hand end in
          // RTL. The artwork draws its magnifier at the other end, as a
          // left-to-right mock would; see `docs/design/style-direction.md`
          // → Amendments.
          prefixIcon: Icon(Icons.search_rounded, color: secondary),
          suffixIcon: !hasQuery
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: _clearTooltip,
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

/// The word-of-the-day card.
///
/// **The brand fills it with the primary colour and the artwork fills it with a
/// photograph, and the photograph is now the user's own file.** So the card
/// keeps `AppSurface`'s `fill` as the colour *underneath* the picture — the
/// frame before the first decode, and the fill if a photograph ever fails to
/// load — and the label, the term and the phonetic sit on top of it.
///
/// **Every surface on this screen is still an `AppSurface`, and this one
/// included.** The photograph is a child, not a replacement: it goes in a
/// `Stack` behind the column, so the card keeps the brand's radius, hairline
/// rule and light-mode shadow exactly as they were. Reaching for a bare `Card`
/// or a private `Container` here would trade the brand's shadow for Material's
/// elevation shadow, that this rasteriser strokes as an opaque black keyline;
/// `test/ui/home_screen_test.dart` asserts every surface here is an `AppSurface`.
///
/// **The photograph fills the card rather than sitting in a panel of its own,
/// and that is a measurement.** The card is a content-sized column: it measured
/// **328 x 201 logical on the golden phone, 1080x2340 at 3x, which is 1.6318:1**,
/// so it has no fixed proportion for a panel to match and a panel would have to
/// invent one and change the card's height. `NaturePhoto` draws `BoxFit.cover`,
/// which crops and never distorts.
///
/// **The text on the photograph is why `WallpaperScrim` exists.** Its strength
/// was solved from the pixels of all fourteen photographs rather than chosen by
/// eye, and `test/ui/wallpaper_legibility_test.dart` re-measures it every run.
class _WordOfTheDayCard extends StatelessWidget {
  const _WordOfTheDayCard({
    required this.entry,
    required this.onOpenWord,
    required this.rotation,
  });

  final VocabEntry entry;
  final ValueChanged<VocabEntry> onOpenWord;

  /// The rotation this card draws. Owned by `_HomeScreenState`, not created
  /// here.
  final NatureRotation rotation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onFill = isDark ? AppColors.textDark : AppColors.surfaceLight;
    final fill = isDark ? AppColors.surfaceDark : AppColors.primaryLight;

    return AppSurface(
      fill: fill,
      // The card's own padding moves onto the column, because the photograph
      // and the scrim have to reach the card's edges for either of them to be
      // worth having.
      padding: EdgeInsets.zero,
      child: ClipRRect(
        // `AppSurface`'s own radius. Named twice, deliberately: `AppSurface`
        // rounds its *decoration* and does not clip its child, so without this
        // the photograph's square corners would sit on top of its rounded ones.
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ListenableBuilder(
                listenable: rotation,
                builder: (context, _) => NaturePhoto(
                  assetPath: rotation.assetPath,
                  nextAssetPath: rotation.nextAssetPath,
                ),
              ),
            ),
            // Above the photograph, below the text. A gradient rather than a
            // flat wash: it holds its strength exactly where the label, the
            // term and the phonetic sit, and lets go above the button, so the
            // bottom third of the card is the photograph at full strength.
            // See `lib/ui/wallpaper/wallpaper_scrim.dart` for how the strength
            // was arrived at.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: WallpaperScrim.gradient),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
          Text(
            _wordOfTheDayLabel,
            style: AppText.latin.copyWith(fontSize: 13, color: onFill),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  entry.term,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.latinDisplay
                      .copyWith(fontSize: AppText.wordOfTheDay, color: onFill),
                ),
              ),
              // Static, never played: text-to-speech is out of scope by user
              // decision, so the artwork's speaker is a glyph and not a control.
              const SizedBox(width: AppSpacing.s),
              const Icon(Icons.volume_up_rounded, color: AppColors.accent),
            ],
          ),
          if (entry.phonetic.isNotEmpty)
            Text(
              entry.phonetic,
              textDirection: TextDirection.ltr,
              style: AppText.latin.copyWith(fontSize: 14, color: onFill),
            ),
          const SizedBox(height: AppSpacing.m),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton(
              onPressed: () => onOpenWord(entry),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textLight,
                shape: const StadiumBorder(),
                // `ElevatedButton` is the one Material 3 family that rests at
                // elevation **1.0** (`elevated_button.dart:570-585`), and that
                // is the same `canvas.drawShadow` defect the cards used to have:
                // the test rasteriser strokes it as an opaque black keyline around
                // the pill, 2,363 pixels of them the last time it was measured.
                // The amber fill carries the button on its own.
                //
                // **`app_theme.dart` now zeroes `elevatedButtonTheme` too**, so
                // this local line is redundant for *this* build and the comment
                // above used to be stale about why. It is kept because it is the
                // call site that pays for the amber pill specifically, and because
                // standards §3 of `docs/engineering-standards.md` — "a rule without
                // an incident gets simplified away" — says a local opt-out with
                // the incident written next to it is what stops the next person
                // deleting it as dead code. Pinned by
                // `test/design/app_theme_test.dart`.
                elevation: 0,
              ),
              child: const Text(_meaningButton),
            ),
          ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 2×2 quick-launch grid the artwork draws under the card.
///
/// Children are in *reading* order, top-right first, because the grid lays out
/// directionally. The artwork's mock transposes both rows, which is what a
/// left-to-right mock of an Arabic grid looks like; the reading order is the one
/// the brand reference names the tiles in. Recorded in
/// `docs/design/style-direction.md` → Amendments.
///
/// **Two of the four tiles switch the bottom bar; `المفضلة` and `إحصائياتك`
/// push.** Pushing a route for a destination the bar can already show leaves the
/// bar highlighting `الرئيسية` under a screen the user did not choose, and makes
/// Back return to Home instead of to the bar. `المفضلة` and `إحصائياتك` are
/// genuinely not tabs — the artwork reaches both from the grid and neither from
/// anywhere else, and its bar has only the four items above — so they have
/// nothing to switch to and are pushed. The bar's index and its handler come
/// from `ShellTabScope`, which `HomeShell` publishes because this screen's
/// constructor cannot take a callback.
class _QuickLaunchGrid extends StatelessWidget {
  const _QuickLaunchGrid({
    required this.packKey,
    required this.onOpenWord,
  });

  final String packKey;

  /// Passed **into** the pushed `FavoritesScreen`, so tapping a saved word opens
  /// it. `HomeScreen` owns this callback and the shell owns the handler behind
  /// it; the grid only forwards, because its constructor is private and a third
  /// indirection would hide where a tap ends up.
  final ValueChanged<VocabEntry> onOpenWord;

  /// Switches the bar to [index] when a scope is present.
  ///
  /// Mounted outside the shell — `HomeScreen` is pumpable on its own in a test —
  /// there is nothing to switch, so the tap does nothing rather than throwing.
  void _goToTab(BuildContext context, int index) =>
      ShellTabScope.of(context)?.selectTab(index);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.m,
      crossAxisSpacing: AppSpacing.m,
      // Square-ish, as the artwork draws them, and short enough that four of
      // them plus the card fit a phone without the whole body scrolling.
      childAspectRatio: 1.15,
      children: <Widget>[
        _QuickLaunchTile(
          icon: Icons.auto_stories_rounded,
          iconColor: AppColors.accent,
          title: 'بطاقات التعلم',
          subtitle: 'ابدأ الآن',
          onTap: () => _goToTab(context, 1),

        ),
        _QuickLaunchTile(
          icon: Icons.check_box_rounded,
          // Ink, not amber: this is the colour the artwork draws this tile's
          // mark in, and the amber is reserved for the two it also draws amber.
          iconColor: Theme.of(context).colorScheme.onSurface,
          title: 'الاختبارات',
          subtitle: 'اختبر نفسك',
          onTap: () => _goToTab(context, 2),
        ),
        _QuickLaunchTile(
          icon: Icons.favorite_rounded,
          iconColor: AppColors.accent,
          title: 'المفضلة',
          subtitle: 'كلماتك المفضلة',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => FavoritesScreen(
              packKey: packKey,
              // The shell's handler, not a no-op. Task 14's fix round: this line
              // was `onOpenWord: (_) {}`, so tapping a saved word did **nothing** -
              // and this tile is the only place in the app that builds a
              // `FavoritesScreen`. Pinned by
              // `test/ui/favorites_screen_test.dart` -> *tapping a row from Home
              // opens the word detail*.
              onOpenWord: onOpenWord,
            ),
          )),
        ),
        _QuickLaunchTile(
          icon: Icons.insights_rounded,
          iconColor: Theme.of(context).colorScheme.onSurface,
          title: 'إحصائياتك',
          subtitle: 'تقدمك وإنجازك',
          // Pushed, not a bar selection — and this is a decision, not a gap.
          // The artwork's bar draws exactly four destinations (الرئيسية,
          // البطاقات, الاختبارات, المزيد) in the light phone and again in the
          // dark one, with no statistics item in either, so index 3 is المزيد
          // and routing statistics through it would be reaching Stats by way of
          // a screen the user never asked for. The artwork *does* draw a fourth
          // Home tile carrying the bar-chart glyph, which is this one, so the
          // screen is a route pushed from the grid. See
          // `docs/design/style-direction.md` → Navigation, and
          // `lib/ui/stats/stats_screen.dart`.
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StatsScreen(packKey: packKey),
              )),
        ),
      ],
    );
  }
}

class _QuickLaunchTile extends StatelessWidget {
  const _QuickLaunchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final radius = BorderRadius.circular(AppRadii.md);

    return Semantics(
      // A tile is a button, and a screen reader has to be told so: `InkWell`
      // alone exposes a tap but not the role, and the whole card is one target.
      container: true,
      button: true,
      label: title,
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: iconColor),
              const SizedBox(height: AppSpacing.s),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dictionary result: the headword, and the Arabic that matched.
///
/// **Both, and the Arabic is not decoration.** An Arabic query is a lookup
/// *key* and 30,567 of the dictionary's Arabic senses are stored as
/// comma-separated synonym lists, so a row that showed only the headword
/// would not tell the user which of the senses they had found.
class _DictionaryRow extends StatelessWidget {
  const _DictionaryRow({
    required this.entry,
    required this.arabic,
    required this.onTap,
  });

  final DictionaryEntry entry;
  final String? arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return ListTile(
      onTap: onTap,
      title: Text(
        entry.word,
        textDirection: TextDirection.ltr,
        style: AppText.latin,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (arabic != null && arabic!.isNotEmpty)
            Text(arabic!, textDirection: TextDirection.rtl),
          if (entry.ipa != null && entry.ipa!.isNotEmpty)
            Text(
              entry.ipa!,
              textDirection: TextDirection.ltr,
              style: AppText.latin.copyWith(fontSize: AppText.caption, color: secondary),
            ),
        ],
      ),
      isThreeLine: (arabic != null && arabic!.isNotEmpty) &&
          (entry.ipa != null && entry.ipa!.isNotEmpty),
    );
  }
}

/// The dictionary's copy, and how far it has got.
///
/// **A determinate bar and a sentence.** The bar is determinate because the
/// copy really does have a fraction, and an indeterminate one schedules
/// frames for ever — which is also why `pumpAndSettle` would never return
/// while it was on screen.
class _DictionaryProgressBanner extends StatelessWidget {
  const _DictionaryProgressBanner({required this.controller});

  final DictionaryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final percent = (controller.progress * 100).round();

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _preparingDictionary,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$percent٪',
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodySmall
                ?.merge(AppText.latin)
                .copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: controller.progress,
              minHeight: 6,
              backgroundColor:
                  isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            ),
          ),
        ],
      ),
    );
  }
}

/// One search result.
class _EntryRow extends StatelessWidget {  const _EntryRow({required this.entry, required this.onTap});

  final VocabEntry entry;
  final ValueChanged<VocabEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: () => onTap(entry),
      // An English term in an Arabic app must not be reordered by the app's
      // direction; its translations must be.
      title: Text(
        entry.term,
        textDirection: TextDirection.ltr,
        style: AppText.latin,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final translation in entry.translations)
            Text(translation, textDirection: TextDirection.rtl),
          if (entry.note.isNotEmpty)
            // A note in the dataset is English prose, like the term above it, so
            // it asks for Inter and LTR explicitly rather than being reordered by
            // the app's direction or set in Tajawal's own Latin.
            Text(
              entry.note,
              textDirection: TextDirection.ltr,
              style: AppText.latin.merge(theme.textTheme.bodySmall),
            ),
        ],
      ),
      isThreeLine: entry.translations.length > 1,
    );
  }
}
