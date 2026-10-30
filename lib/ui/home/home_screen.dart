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
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/word_of_the_day.dart';
import 'package:lexilearn/ui/custom_dictionary/custom_dictionary_screen.dart';
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
import 'package:lexilearn/ui/wallpaper/wallpaper_gradient.dart';
import 'package:provider/provider.dart';

/// The chrome strings, taken from `docs/design/brand-reference.png`.
const String _subheading = 'كل كلمة جديدة تقرّبك من هدفك';
const String _searchHint = 'ابحث عن كلمة...';
const String _wordOfTheDayLabel = 'Word of the Day';
const String _meaningButton = 'معرفة المعنى';
const String _clearTooltip = 'مسح';
const String _noResults = 'لا توجد نتائج. جرّب جزءاً من الكلمة.';
const String _searchFailed = 'تعذّر البحث.';
const String _searching = 'جارٍ البحث…';
const String _preparingDictionary = 'جارٍ تجهيز المعجم…';

/// **The greeting, in the four runs the reference draws it in.**
///
/// **The four runs concatenate to «مرحباً بك!»** — the greeting as one string
/// is in the test file, which asserts on the whole phrase.
///
/// **The tanween is a character of its own, and it has to be a run of its own.**
/// In «مرحباً» the fathatan is `U+064B`, written *after* the alef in the
/// logical string and drawn *above* it on screen. So a colour on the whole word
/// colours the word, and the reference's own treatment — white «مرحبا» with the
/// tanween in the brand gold — cannot be expressed without splitting the run.
///
/// **Splitting it there does not break the Arabic.** Measured, not assumed: the
/// split puts the alef at the end of the white run, so the `ب` before it still
/// joins to it, and the tanween — a combining mark with no advance of its own —
/// is drawn above the alef in the gold run. The golden image shows the mark in
/// gold, in the right place, above a white alef.
const String _greetingWord = 'مرحبا';
const String _greetingTanween = '\u064B';
const String _greetingTail = ' بك';
const String _greetingBang = '!';

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
    this.packTitle = '',
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

  /// The pack's **name**, for the chip in the header.
  ///
  /// **The name, never the key.** The key is `dictionary_en_ar` — an
  /// identifier, and this chip is the one place the user read it. The shell
  /// resolves it with the pack list it reads at start-up and hands it down, so
  /// this screen has it without a read of its own.
  final String packTitle;

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

  /// The repository, held so the dictionary's arrival can be noticed.
  ///
  /// **Read once, in `initState`, for the reason `context.read` is safe there.**
  late final VocabRepository _repository;

  /// Whether the pack has been read since the dictionary became readable.
  ///
  /// **The flag that makes the re-read happen exactly once.**
  bool _readTheReadyPack = false;

  @override
  void initState() {
    super.initState();
    _search = SearchController(repository: context.read<VocabRepository>())
      ..addListener(_onSearchChanged);
    // `context.read` is safe in `initState` — it does not subscribe — which is
    // the same reason the repository is read there.
    _repository = context.read<VocabRepository>();
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
    _reloadIfThePackBecameReadable();
    setState(() {});
  }

  /// Re-reads the pack when the dictionary's engine has arrived.
  ///
  /// **The defect this closes, and the shape of it.**
  ///
  /// The dictionary is copied onto the device **off the UI path**: 26 MB, on
  /// first launch, while the app is already on screen. Until that copy lands,
  /// the dictionary pack has **no readable words at all** — `VocabRepository
  /// .entries` answers the dictionary's key with an empty list while the
  /// repository holds no engine — so the word of the day has nothing to pick
  /// and the card is simply not drawn.
  ///
  /// **The read that filled `_entries` happened in `initState`, before the copy
  /// finished, and nothing read the pack again.** The user reported exactly
  /// that: «بطاقة كلمة اليوم لا تظهر الا بعد الانتقال الى واجهة اخرى ثم
  /// العودة الى الرئيسية» — the card appeared only after leaving the screen and
  /// coming back, because *coming back* is what built a new `State` and ran a
  /// new `initState`, and by then the copy was done.
  ///
  /// **Why the shell's own listener could not carry it.** `HomeShell` listens
  /// to the same controller and switches the active pack to the dictionary when
  /// it becomes ready — but only when the active key is *not already* the
  /// dictionary's. On a device where the dictionary's row is already in the
  /// pack table (which is what `ensureDictionaryPack` puts there), the shell
  /// changes nothing, `HomeScreen.didUpdateWidget` never fires, and no read
  /// is issued. The signal has to be the dictionary's own arrival, and the
  /// screen has to hear it.
  ///
  /// **The gate is the repository, not the controller.** The screen asks
  /// "can the pack be read now?", and the answer is the repository's: the
  /// engine is attached to it *before* the controller notifies
  /// (`DictionaryController.start` attaches, then notifies), so the two agree in
  /// the app — and the repository is the thing the read actually depends on.
  /// **Once, and only once.** The controller notifies on every progress tick
  /// of the copy, so the flag is what stops a 26 MB download from becoming a
  /// hundred database reads.
  void _reloadIfThePackBecameReadable() {
    if (_readTheReadyPack) return;
    if (_repository.dictionary == null) return;
    _readTheReadyPack = true;
    _loadPack(widget.packKey);
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
          // **The curated pool, not the pack's whole contents.** The card is
          // the only reader here, and the user's ruling is that the dictionary's
          // card must draw from the curated set rather than from all 31,600
          // entries; the repository answers the dictionary's pool in SQL and
          // every other pack's with its own entries. See
          // `VocabRepository.wordOfTheDayPool`.
          : await repository.wordOfTheDayPool(packKey);
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
            _Header(title: widget.packTitle),
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
  const _Header({required this.title});

  /// The active pack's display name.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    // **The gold where the mode can carry it**, and the body ink where it
    // cannot. One token, one rule — see `AppColors.accentInk`.
    final accent = AppColors.accentInk(isDark);

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
                // **The greeting, in the reference's four runs.**
                //
                // «مرحباً بك!» is white **except the tanween and the exclamation
                // mark, which are gold** — the reference's own treatment, and the
                // user's: «التنوين على كلمة مرحبا ليس ذهبيا واجعل علامة التعجب
                // ايضا ذهبية».
                //
                // **The gold is the accent, so it is `accentInk`** — the gold in
                // dark mode, where the reference draws it, and the body ink in
                // light mode, where the gold measures 1.95 : 1 against the page
                // and could not carry a character. The token is the rule, and it
                // lives in one place.
                Text.rich(
                  TextSpan(
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    children: <InlineSpan>[
                      const TextSpan(text: _greetingWord),
                      TextSpan(
                        text: _greetingTanween,
                        style: TextStyle(color: accent),
                      ),
                      const TextSpan(text: _greetingTail),
                      TextSpan(
                        text: _greetingBang,
                        style: TextStyle(color: accent),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          // **The pill is the one thing in this row that may shrink.** The
          // greeting is the brand's headline, the mark and the overflow menu
          // are the artwork's, and the pack's *name* is metadata: a pack the
          // user imported can have a name of any length, and a name that does
          // not fit has to be shortened rather than push the row off the
          // screen. Measured on the artwork's phone: the row is 328 px wide,
          // the mark and the menu and the gaps take 112 of them, and the
          // greeting needs the rest.
          Flexible(child: _PackPill(title: title)),
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
          //
          // **`edgeInset: 0`, and the reason is this row's own padding.** The
          // header row already carries the page's 16 px margin, so the button
          // is 16 px from the screen's edge already — the same place the three
          // `AppBar` destinations put it once they are given the margin the
          // bar's `actions` slot does not have. The user's own words: «زر
          // الثلاث نقاط قريب جدا من حافة الشاشة اجعله كما في الشاشة
          // الرئيسية» — the three-dot button is far too close to the edge of
          // the screen; make it as it is on the home screen.
          const AppOverflowMenu(edgeInset: 0),
        ],
      ),
    );
  }
}

/// Whether [value] carries an Arabic letter.
///
/// **The same block the app's other screens use** — U+0600 to U+06FF, plus the
/// Arabic Supplement and Extended-A blocks — so "is this Arabic?" is answered
/// the same way everywhere it is asked.
bool _writesArabic(String value) => value.runes.any(
      (rune) => (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF),
    );

/// The pack this screen is scoped to, named.
///
/// Not decoration: `HomeShell` resolves the active pack once and hands the same
/// key to all four destinations, so this is what proves the screen is reading
/// that state rather than standing still.
///
/// **The pack's name, never its key.** The key is `dictionary_en_ar` — a
/// technical identifier, and this chip is the one place the user read it. The
/// name is «القاموس الكامل» for the dictionary and the starter set's own
/// title for the 297-word pack.
class _PackPill extends StatelessWidget {
  const _PackPill({required this.title});

  /// The pack's display name, or the empty string while it is still resolving.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    // The name may be Arabic and it may be Latin, and the chip is a run of
    // text in the app's own direction — so the direction is the paragraph's,
    // not a decision this widget makes.
    final isArabic = _writesArabic(title);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        // **The structure blue, and the rule the identity document states:**
        // the blue is structure rather than accent — the pack chip's outline is
        // one of the three places it is used, beside the card borders and the
        // search field's outline. In light mode the same role is the pale
        // grey, which is the same system inverted.
        border: Border.all(
          color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
        ),
      ),
      child: Text(
        // The em dash is the shell's start-up window rather than a missing
        // pack: the key has not been resolved yet, so the name is not known.
        title.isEmpty ? '—' : title,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        // **One line, shortened rather than wrapped.** The name is metadata
        // and the row has no room for two lines of it.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isArabic
            ? theme.textTheme.bodySmall?.copyWith(color: secondary)
            : AppText.latin.copyWith(fontSize: 12, color: secondary),
      ),
    );
  }
}

/// The book mark, on the circle the artwork draws it in.
///
/// **The reference's mark: a gold ring around a dark disc, with the gold book
/// inside it.** The ring is measured off the reference's own header, where the
/// circle's outline is the brand's gold and its interior is the app's darkest
/// disc.
class _BookMark extends StatelessWidget {
  const _BookMark();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The gold is an *ink* here, and light mode cannot carry it as one: the
    // mark sits on the page background, and the gold measures 1.95 : 1 on the
    // light background. `AppColors.accentInk` is the rule.
    final ink = AppColors.accentInk(isDark);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // The disc the reference draws the mark on: the icon badge's own
        // colour, a step below the surface in both modes.
        color: isDark ? AppColors.iconBadgeDark : AppColors.backgroundLight,
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: 1.5),
      ),
      child: Icon(Icons.menu_book_rounded, color: ink, size: 22),
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
/// **The brand fills it with a photograph, and the photograph is the user's own
/// file.** So the card keeps `AppSurface`'s `fill` as the colour *underneath*
/// the picture — the frame before the first decode, and the fill if a
/// photograph ever fails to load — and the label, the term and the phonetic
/// sit on top of it.
///
/// **The card keeps its shape, and that is the user's ruling.** The reference
/// image shows a split card — photograph on one side, text on the other — and
/// the user refused it: «بطاقة اليوم ليست نصفان ابقها كما هي ابق التدرج و الظل»
/// — the card is not two halves; leave it as it is, keep the ramp and the
/// shadow. So the photograph stays **full-bleed**, the ramp stays, and the
/// text stays **on** the photograph. `docs/new-identity.md` rule 4 says so,
/// and `lib/ui/wallpaper/wallpaper_gradient.dart` and `AppShadows.onPhoto`
/// are therefore **not** dead code.
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
/// **The text on the photograph is why `WallpaperGradient` exists.** Its shape
/// was recomputed from the artwork's own card and its strength was solved from
/// the pixels of all thirteen photographs rather than chosen by eye, and
/// `test/ui/wallpaper_legibility_test.dart` re-measures it every run.
///
/// **What the ramp does to the photograph's own contrast, measured rather than
/// claimed.** Sampled in the card's left half, where the right-aligned text
/// never reaches, against the same photograph before and after:
///
/// | the card's band | the photograph's own spread | under the scrim | under the ramp |
/// |---|---|---|---|
/// | the label | 0.040 | 16% | **253%** |
/// | the word | 0.277 | 15% | 15% |
/// | the phonetic | 0.213 | 15% | 15% |
/// | the button | 0.448 | 53% | **16%** |
///
/// **What the new identity changes here is the colour and nothing else.** The
/// speaker is the gold, and the button is the gold — a solid gold pill with
/// the app's darkest ink on it, which measures **9.90 : 1** whatever is behind
/// it, where the old translucent pill had to be solved against the user's
/// brightest photographs. The ramp and the shadow are untouched, and the ink
/// on the photograph is still white in both modes.
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
    // **White in both modes**, and the artwork is the reason: its light card
    // draws "serenity" in white and its dark card draws "ambition" in white.
    // The text still sits on the photograph, and the photograph does not change
    // with the phone's theme. See `AppColors.onPhoto`.
    final onFill = AppColors.onPhoto;
    // **The frame under the photograph.** The second navy surface in dark mode
    // — the reference's own card interior — and the page background in light
    // mode, which is the same system inverted: a step below the surface.
    final fill =
        isDark ? AppColors.surfaceDarkAlt : AppColors.backgroundLight;

    return AppSurface(
      fill: fill,
      // The card's own padding moves onto the column, because the photograph
      // and the ramp have to reach the card's edges for either of them to be
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
            // Above the photograph, below the text. **A gradient, not a scrim**,
            // and not the artwork's flat wash either: the ink is zero on the
            // top edge, reaches 0.60 by the word's band and holds to the
            // bottom, so the card dims *gradually toward the bottom* with no
            // edge anywhere. See `lib/ui/wallpaper/wallpaper_gradient.dart` for
            // how the shape was recomputed from the artwork's own card.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: WallpaperGradient.gradient),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
          _WordOfTheDayLabel(),
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
                  style: AppText.latinDisplay.copyWith(
                    fontSize: AppText.wordOfTheDay,
                    color: onFill,
                    shadows: AppShadows.onPhoto,
                  ),
                ),
              ),
              // Static, never played: text-to-speech is out of scope by user
              // decision, so the artwork's speaker is a glyph and not a control.
              //
              // **The gold, and the gold is an accent rather than a text
              // colour**: it is the same gold the reference draws its speaker
              // in, and it sits on the ramp, which is the app's own darkest
              // navy at 0.60 — so it is legible over every one of the thirteen
              // photographs in both modes.
              const SizedBox(width: AppSpacing.s),
              const Icon(Icons.volume_up_rounded, color: AppColors.gold),
            ],
          ),
          if (entry.phonetic.isNotEmpty)
            Text(
              entry.phonetic,
              textDirection: TextDirection.ltr,
              style: AppText.latin.copyWith(
                fontSize: 14,
                color: onFill,
                shadows: AppShadows.onPhoto,
              ),
            ),
          const SizedBox(height: AppSpacing.m),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton(
              onPressed: () => onOpenWord(entry),
              style: ElevatedButton.styleFrom(
                // **The gold button, and the reference's own.** The artwork's
                // "معرفة المعنى" is a solid gold pill with near-black
                // lettering, and the new identity makes that the app's button:
                // the primary is a **fill**, and the ink on it is the darkest
                // ink in the app.
                //
                // **The old translucent dark pill is gone, and the reason it
                // existed is gone with it.** It carried 45% of the app's
                // darkest neutral so that a *white* label could clear 4.5:1
                // over the user's brightest photographs; the gold needs
                // neither, because its fill is opaque and its ink measures
                // **9.90 : 1** against it whatever is behind the pill.
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.onGold,
                shape: const StadiumBorder(),
                // `ElevatedButton` is the one Material 3 family that rests at
                // elevation **1.0** (`elevated_button.dart:570-585`), and that
                // is the same `canvas.drawShadow` defect the cards used to have:
                // the test rasteriser strokes it as an opaque black keyline
                // around the pill, 2,363 pixels of them the last time it was
                // measured. The solid fill carries the button on its own.
                //
                // **`app_theme.dart` now zeroes `elevatedButtonTheme` too**, so
                // this local line is redundant for *this* build and the comment
                // above used to be stale about why. It is kept because it is the
                // call site that pays for the gold pill specifically, and
                // because standards §3 of `docs/engineering-standards.md` — "a
                // rule without an incident gets simplified away" — says a local
                // opt-out with the incident written next to it is what stops
                // the next person deleting it as dead code. Pinned by
                // `test/design/app_theme_test.dart`.
                elevation: 0,
              ),
              child: const Text(
                _meaningButton,
                // The ink on the gold, and nothing else: the button's own label
                // no longer sits on the photograph, so it needs neither the
                // ramp nor the artwork's shadow.
                style: TextStyle(color: AppColors.onGold),
              ),
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

/// The "Word of the Day" label: a gold star, the phrase in gold, and a short
/// gold rule on the trailing side.
///
/// **The reference's own row, and all three of its parts.** The reference draws
/// `★ Word of the Day ―――`: a filled gold star, the phrase, and a short line
/// beside it that **fades away** rather than ending flat. The user named the
/// two things that were missing: «جملة word of the day ليست ذهبية و لايوجد خط
/// هبي متدرج بجانبها» — the phrase is not gold, and there is no gold gradient
/// line beside it.
///
/// **The order is the reading order.** This app reads right to left, so the
/// star is at the leading (right) end, the phrase follows it, and the rule is
/// on the trailing (left) end — the side the reading finishes on. The rule's
/// gradient therefore has to be **directional**: `AppGradients.goldRule` takes
/// the text direction, so the gold end is against the phrase and the
/// transparent end is away from it in either mode.
///
/// **The phrase is the gold, and the gold is the accent.** It is the brand's
/// `#F3AC43` and not the card's white ink, because the reference draws this
/// label in gold and the user asked for gold. The shadow stays — the artwork's
/// own mechanism for legibility, and it is what carries a gold run over a
/// photograph: measured over the thirteen photographs the app ships, the gold
/// label's shadowed edge clears 4.5 : 1 everywhere (5.31 : 1 at its worst).
class _WordOfTheDayLabel extends StatelessWidget {
  const _WordOfTheDayLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.star_rounded, color: AppColors.gold, size: 13),
        const SizedBox(width: AppSpacing.xs),
        Text(
          _wordOfTheDayLabel,
          // **The artwork's shadow.** The label sits on the photograph, and the
          // artwork keeps it legible with a soft dark halo rather than with a
          // band of ink over the picture.
          style: AppText.latin.copyWith(
            fontSize: 13,
            color: AppColors.gold,
            shadows: AppShadows.onPhoto,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // **The rule, and it is a gradient.** The reference's line starts at the
        // full brand gold and fades out until it is gone; a flat gold bar would
        // be the same defect the user named.
        Container(
          width: _labelRuleWidth,
          height: _labelRuleHeight,
          decoration: BoxDecoration(
            gradient: AppGradients.goldRule,
          ),
        ),
      ],
    );
  }
}

/// The width of the rule beside the "Word of the Day" label, in logical px.
///
/// **Measured off the reference**: the rule runs `x 733..771` in a 852-px-wide
/// image of a 360-px phone, so it is **16 logical px** of visible gold with a
/// faint tail beyond it. It is drawn a little wider here — 28 — so that the
/// gradient has room to die out rather than ending in a hard edge.
const double _labelRuleWidth = 28;

/// The height of that rule, in logical px. The reference's is 2 image px, which
/// is 0.85 logical px; it is drawn 2 so that it survives a screenshot.
const double _labelRuleHeight = 2;

/// The 2×2 quick-launch grid the artwork draws under the card.
///
/// Children are in *reading* order, top-right first, because the grid lays out
/// directionally. The artwork's mock transposes both rows, which is what a
/// left-to-right mock of an Arabic grid looks like; the reading order is the one
/// the brand reference names the tiles in. Recorded in
/// `docs/design/style-direction.md` → Amendments.
///
/// **One of the four tiles switches the bottom bar; the other three push.**
/// `بطاقات التعلم` is the bar's `البطاقات`. Pushing a route for a destination
/// the bar can already show leaves the bar highlighting `الرئيسية` under a
/// screen the user did not choose, and makes Back return to Home instead of to
/// the bar. `المفضلة`, `إحصائياتك` and the user's own dictionary are genuinely
/// not tabs — the artwork reaches all three from the grid and none from
/// anywhere else, and its bar has only the four items above — so they have
/// nothing to switch to and are pushed. The bar's index and its handler come
/// from `ShellTabScope`, which `HomeShell` publishes because this screen's
/// constructor cannot take a callback.
///
/// **The custom dictionary replaces the quiz tile, and the quiz is not lost.**
/// The user's artwork draws the grid this way and the brief says why: the quiz
/// is still one tap away in the bottom bar, so the quiz's old place is worth
/// more as a door to the words the user typed themselves.
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
          // **The artwork's own glyph for this tile is a gold plus** — the
          // action is "add to your own dictionary", not "read the dictionary".
          // The book belongs to the landing screen and to the bar's dictionary
          // chip; copying it here would make two doors look like one.
          icon: Icons.add_rounded,
          iconColor: AppColors.accentInk(
            Theme.of(context).brightness == Brightness.dark,
          ),
          title: customDictionaryTitle,
          subtitle: 'أنشئ قاموسك الخاص',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const CustomDictionaryScreen(),
          )),
        ),
        _QuickLaunchTile(
          // **The reference's own glyph for this tile**: a tilted card, drawn in
          // outline — the same glyph the reference's bottom bar uses for
          // `البطاقات`, which is the app's `Icons.style_outlined` too. The old
          // `auto_stories_rounded` was a filled open book, which is neither the
          // reference's shape nor its weight.
          icon: Icons.style_outlined,
          iconColor: AppColors.accentInk(
            Theme.of(context).brightness == Brightness.dark,
          ),
          title: 'بطاقات التعلم',
          subtitle: 'ابدأ الآن',
          onTap: () => _goToTab(context, 1),
        ),
        _QuickLaunchTile(
          // **The reference draws three solid bars**, not a line with sparkles.
          icon: Icons.bar_chart_rounded,
          iconColor: AppColors.accentInk(
            Theme.of(context).brightness == Brightness.dark,
          ),
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
        _QuickLaunchTile(
          // **The reference draws an outlined heart**, not a filled one.
          icon: Icons.favorite_outlined,
          iconColor: AppColors.accentInk(
            Theme.of(context).brightness == Brightness.dark,
          ),
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
      ],
    );
  }
}

/// One of the four quick-launch tiles.
///
/// **The reference's tile, and the three things it has.** The reference draws
/// the icon inside a **circular badge** with a **gradient in it**, puts the
/// badge and the two lines of text **against the leading edge**, and puts a
/// **chevron on the trailing side** level with the title. All three are here.
///
/// **The reference is a left-to-right mock of an Arabic screen**, and the tile
/// is mirrored for the same reason the grid's rows are: the badge and the text
/// are against the **right** edge here, and the chevron is on the **left**,
/// pointing the way the reading goes. The mock draws its badge on the left and
/// its `›` on the right, which is the same arrangement seen from the other
/// side.
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
          // **A `Column`, and not a `Stack`.** The reference's chevron is on the
          // title's own line, at the far end of it — so the title and the
          // chevron are one row, and the badge and the subtitle are rows of
          // their own. The old layout centred every line and floated the
          // chevron in a `Stack` against the tile's edge, which is neither the
          // reference's arrangement nor this one's.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _TileBadge(icon: icon, colour: iconColor),
              const SizedBox(height: AppSpacing.s),
              Row(
                children: <Widget>[
                  // **Flexible, and not Expanded.** The title's box has to be
                  // the width of its own ink, so that the box a test taps is
                  // the text and not an empty gap beside it — and so that the
                  // row's free space falls between the title and the chevron,
                  // which is where the reference puts it.
                  Flexible(
                    child: Text(
                      title,
                      textAlign: TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // **The chevron, on the trailing side.**
                  //
                  // The reference draws it pointing along the reading
                  // direction, on the side the reading finishes. This app reads
                  // right to left, so the trailing side is the **left** and the
                  // glyph points left — the mirror of the mock's own `›`, which
                  // is a left-to-right mock and therefore has it on its right.
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    // The gold, as ink, where the mode can carry it: the
                    // reference draws the tile's chevron in the brand's accent.
                    color: AppColors.accentInk(isDark),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                textAlign: TextAlign.start,
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

/// The circle behind a quick-launch tile's icon.
///
/// **The reference's badge, measured off the artwork** — and **it is a disc with
/// a gradient in it, not a flat colour.** The user named this as one of the
/// four defects: «لون هذه المربعات ليس متدرجا كما في new theme.png بل هو لون
/// ثابت ليس متدرجا».
///
/// The two ends of the ramp are measured, not chosen: a vertical slice down
/// the reference's badge reads **`#172B4F` at the disc's top and `#091C3B` at
/// its foot** (`AppColors.iconBadgeDarkTop` and `AppColors.iconBadgeDarkBottom`),
/// with the tile's own fill around it at `#0D2245`. So the badge is *lighter*
/// than the tile at its top and *darker* at its foot.
///
/// **The badge is against the leading edge**, not centred: the reference puts
/// the disc on the same edge as the title and the subtitle, and the mirror of
/// that in this right-to-left app is the right edge.
class _TileBadge extends StatelessWidget {
  const _TileBadge({required this.icon, required this.colour});

  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          // **The gradient, and it is the reference's own ramp.** A flat fill
          // here was the defect; the ramp lives in the tokens so that no
          // screen carries a colour of its own.
          gradient: AppGradients.iconBadge(isDark),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: colour, size: 24),
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
