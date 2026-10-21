
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:provider/provider.dart';

import 'dictionary/dictionary_controller.dart';
import 'dictionary/dictionary_word_screen.dart';
import 'flashcards/flashcards_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'quiz/quiz_setup_screen.dart';
import 'word_detail/word_detail_screen.dart';

/// The bottom-bar shell: one destination at a time, and the pack they share.
///
/// [repository] is used once, at start-up, to resolve which pack the app is
/// working on. Everything after that is state local to this widget, so the four
/// screens never have to reach back into the data layer.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.repository,
    this.wallpaperSeed,
  });

  final VocabRepository repository;

  /// Seeds the rotating photograph on Home's card and on the flashcard panel.
  ///
  /// **A seam, and nothing else.** Null is the app's own behaviour; a seed is
  /// what `golden_test.dart` passes, because a reference image that shows a
  /// different photograph on every regeneration is a reference nobody can
  /// compare against. Same reasoning, and same shape, as `HomeScreen
  /// .wallpaperSeed` and `FlashcardsScreen.wallpaperSeed`; there is one
  /// seed for both surfaces so the light and the dark image of a screen are the
  /// same screen in two modes rather than two different screens.
  final int? wallpaperSeed;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The pack every destination is scoped to. Empty until [widget.repository]
  /// answers, and empty for good when no pack is installed.
  String _activePackKey = '';

  /// The active pack's **name**, as every destination's chip shows it.
  ///
  /// **The name, never the key.** The key is `dictionary_en_ar` — an
  /// identifier, and the chip is in front of the user.
  ///
  /// **It is read once, here, and handed down.** The shell already reads the
  /// pack list at start-up, so the title comes with it and every destination
  /// has it without a read of its own — which matters, because
  /// `test/ui/home_shell_test.dart` switches to a destination and settles
  /// without giving the real event loop a turn, so anything waiting on a read
  /// there never arrives.
  String _activePackTitle = '';

  /// The dictionary's controller, so the shell can react to it becoming
  /// ready.
  late final DictionaryController _dictionary;

  /// Whether the user has picked a pack by hand.
  ///
  /// **The dictionary becoming ready must not overrule a choice the user
  /// made.** The dictionary is the default, so it wins when nobody has
  /// chosen; a user who picked the starter set before the copy finished meant
  /// it.
  bool _userChosePack = false;

  /// The brand's four destinations, in bar order.
  ///
  /// Count and order come from the artwork, not from a word of mouth:
  /// `docs/design/brand-reference.png` draws exactly four items — الرئيسية,
  /// البطاقات, الاختبارات, المزيد — in both the light and the dark phone, with
  /// no heart anywhere in either bar. `docs/design/style-direction.md` records
  /// the same in its **Navigation** section and in **Amendment 1**, which
  /// corrects an earlier five-destination draft back to four.
  ///
  /// **Favourites is not one of these four, and nothing was cut.** It is a
  /// shipped feature reached the way the artwork itself reaches it: from the
  /// `المفضلة` tile in Home's 2×2 quick-launch grid (`Task 10` builds that grid),
  /// which is **the only place in `lib/` that constructs a `FavoritesScreen`**
  /// (`home_screen.dart`, `_QuickLaunchGrid`). `FavoritesScreen` already exists
  /// at `lib/ui/favorites/favorites_screen.dart`; it is simply not a bar
  /// destination, so this file no longer imports it. See
  /// `docs/design/style-direction.md` → Navigation.
  ///
  /// **An earlier version of this comment claimed a second door that does not
  /// exist** — that `Task 14` builds `WordDetailScreen` and *"pushes
  /// `FavoritesScreen` from there"*, i.e. from the heart. It does not, and it
  /// should not: the heart **writes** the favourite in place
  /// (`WordDetailRoute._toggle`), which is what
  /// `docs/design/brand-reference.md` §4ب specifies as an `أضف إلى المفضلة`
  /// button on the word's own screen, and there is no artwork anywhere showing a
  /// navigation from a heart to a list. Corrected in Task 14's fix round, after
  /// counting the call sites: `FavoritesScreen(` appears in `lib/` exactly once.
  ///
  /// The icons are the artwork's too, verified glyph-by-glyph against the PNG
  /// rather than chosen by name:
  ///
  /// * `home_outlined` / `home` — the artwork's house is filled while active
  ///   and outlined while not, which is exactly this pair.
  /// * `style_outlined` / `style` — two overlapping rounded cards, back one
  ///   offset up and right.
  /// * `check_box_outlined` / `check_box` — the artwork draws a rounded square
  ///   with a checkmark breaking out through the top-right corner and nothing
  ///   inside the box. `checklist_rtl` is two check rows beside three text
  ///   lines; measured against the artwork it scores 11.6% mean pixel IoU where
  ///   `check_box_outlined` scores 25.1%.
  /// * `apps` — the artwork draws a *cluster* of marks on a 3×3 lattice, not
  ///   three dots in a row. `apps` is the only candidate that puts a mark at
  ///   **every** position either phone draws (5 of 5 on the light phone, 7 of 7
  ///   on the dark one) at the same relative pitch; `more_horiz` reaches 3 of 5
  ///   and 3 of 7, and `blur_on` — the only other dot-shaped candidate — is a
  ///   24-dot bokeh cluster with five times the density.
  ///
  /// The active destination is the brand purple and the rest the secondary grey
  /// — both come from `NavigationBarThemeData` in `AppTheme`, which sets the
  /// bar's background, its indicator and its label style, so the bar is never
  /// coloured here.
  ///
  /// This list and the `screens` list in [build] MUST stay the same length and
  /// in the same order — the bar indexes into `screens` directly, so a mismatch
  /// is an out-of-range crash on tap, not a cosmetic bug.
  /// `test/ui/home_shell_test.dart` asserts both: the labels and icons here
  /// match the expected four, and every one of them lands on its own screen.
  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'الرئيسية',
    ),
    NavigationDestination(
      icon: Icon(Icons.style_outlined),
      selectedIcon: Icon(Icons.style),
      label: 'البطاقات',
    ),
    NavigationDestination(
      icon: Icon(Icons.check_box_outlined),
      selectedIcon: Icon(Icons.check_box),
      label: 'الاختبارات',
    ),
    NavigationDestination(
      icon: Icon(Icons.apps),
      selectedIcon: Icon(Icons.apps),
      label: 'المزيد',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // `context.read` is safe in `initState` — it does not subscribe — which is
    // the same reason `home_screen.dart` reads its repository there.
    _dictionary = context.read<DictionaryController>();
    _dictionary.addListener(_onDictionaryChanged);
    _loadActivePack();
  }

  @override
  void dispose() {
    _dictionary.removeListener(_onDictionaryChanged);
    super.dispose();
  }

  /// Switches to the dictionary when its copy finishes.
  ///
  /// **The dictionary is the default pack**, and the default has to be
  /// reachable even when the copy is still running: the app opens, the home
  /// screen shows, and a few seconds later the dictionary is there and the
  /// whole app is scoped to it.
  void _onDictionaryChanged() {
    if (!mounted || _userChosePack) return;
    if (!_dictionary.isReady) return;
    if (_activePackKey == dictionaryPackKey) return;
    setState(() {
      _activePackKey = dictionaryPackKey;
      _activePackTitle = dictionaryPackTitle;
    });
  }

  Future<void> _loadActivePack() async {
    final packs = await widget.repository.packs();
    // A shell torn down mid-query, or an install with no pack at all, leaves
    // the key empty and every screen renders its own empty state.
    if (!mounted || packs.isEmpty) return;
    setState(() {
      _activePackKey = packs.first.packKey;
      _activePackTitle = packs.first.title;
    });
  }

  void _selectPack(String packKey) {
    _userChosePack = true;
    // The title is cleared rather than left stale: a chip that still names the
    // pack the app was on a moment ago is worse than a chip that says nothing
    // for the fraction of a second the new name takes to arrive.
    setState(() {
      _activePackKey = packKey;
      _activePackTitle = '';
    });
    unawaited(_readPackTitle(packKey));
  }

  /// The name of the pack the user just picked.
  ///
  /// **A read of its own, because the shell's start-up list may not have the
  /// pack in it** — a pack imported after the app opened is not in the list the
  /// shell read at start-up.
  Future<void> _readPackTitle(String packKey) async {
    final title = await widget.repository.packTitle(packKey);
    if (!mounted || _activePackKey != packKey) return;
    setState(() => _activePackTitle = title);
  }

  /// Switches the bottom bar to [index].
  ///
  /// Named separately from the bar's `onDestinationSelected` closure so the same
  /// one handler serves both the bar and Home's quick-launch grid. It is also
  /// what `ShellTabScope` below exposes to descendants, which is the whole
  /// reason that widget exists — see its documentation.
  void _selectTab(int index) {
    if (index < 0 || index >= _destinations.length) return;
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// Opens the word detail view for [entry].
  ///
  /// **A pushed route, not a bar destination**, for the same reason statistics
  /// and favourites are: the artwork's bar draws exactly four items and none of
  /// them is a word. Both of Home's doors into a word arrive here — the
  /// word-of-the-day card's `معرفة المعنى` and a search result row.
  ///
  /// `WordDetailRoute` and not `WordDetailScreen`: the screen's own signature
  /// takes `isFavorite` and `onToggleFavorite`, so the truth about whether this
  /// word is saved has to live in something that owns it. The route does.
  ///
  /// The repository is not handed to the route explicitly — it comes from the
  /// `Provider` `LexiLearnApp` installs above this shell, which is where every
  /// other screen reads it from.
  ///
  /// **Task 14 wrote this body.** It was an empty method with a comment saying
  /// Task 14 would replace it, and Task 14's own file list does not name this
  /// file — but a no-op that documents the thing that is supposed to do it is
  /// precisely the false comment `docs/engineering-standards.md` §1 is about, and
  /// `onOpenWord` reaching nothing is the artefact the artwork draws. Pinned by
  /// `test/ui/word_detail_screen_test.dart` → *the معرفة المعنى button opens it
  /// and leaves the bar where it was*, which taps the real card through the real
  /// app.
  void _openWordDetail(VocabEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordDetailRoute(entry: entry, packKey: _activePackKey),
      ),
    );
  }

  /// Opens a dictionary word.
  ///
  /// **A different route from [\_openWordDetail], and it has to be.** The
  /// starter pack's word shows one translation and one note; a dictionary
  /// entry has 81,451 senses between its 31,600 headwords, and the longest
  /// gloss in the corpus is 616 characters. A screen sized for the first
  /// would overflow on the second.
  void _openDictionaryWord(DictionaryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DictionaryWordRoute(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same order as `_destinations`, and the same length. Index-for-index.
    final screens = <Widget>[
      HomeScreen(
        packKey: _activePackKey,
        packTitle: _activePackTitle,
        onPackSelected: _selectPack,
        onOpenWord: _openWordDetail,
        onOpenDictionaryWord: _openDictionaryWord,
        wallpaperSeed: widget.wallpaperSeed,
      ),
      FlashcardsScreen(
        packKey: _activePackKey,
        packTitle: _activePackTitle,
        wallpaperSeed: widget.wallpaperSeed,
      ),
      QuizSetupScreen(
        packKey: _activePackKey,
        packTitle: _activePackTitle,
        onPackSelected: _selectPack,
      ),
      MoreScreen(
        packKey: _activePackKey,
        onPackSelected: _selectPack,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: ShellTabScope(
          // The grid's tiles select bar destinations rather than pushing a
          // second copy of them. `HomeScreen` predates this and cannot take a
          // callback — its constructor is fixed by the interfaces later tasks
          // depend on — so the shell publishes the handler down the tree instead.
          // Descendants re-read [index] on every tab change, so a tile can also
          // tell which destination is showing.
          index: _index,
          selectTab: _selectTab,
          child: AnimatedSwitcher(
            // One movement per tab change, at the brand's fast duration — the
            // style direction reserves `AppDurations.fast` for exactly this. The
            // key is the index, so changing packs inside a destination updates
            // the screen in place instead of replaying the transition.
            duration: AppDurations.fast,
            child: KeyedSubtree(
              key: ValueKey<int>(_index),
              child: screens[_index],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: _destinations,
      ),
    );
  }
}

/// Wraps a bottom-bar destination so Android's back returns to Home.
///
/// **THE BACK BUTTON, and the reason this widget exists.** The user reported that
/// entering a screen and pressing back on the phone left the app entirely.
/// Measured before any of this, on the unmodified tree, with a throwaway test
/// that called `tester.binding.handlePopRoute()` and then read the tree
/// (`docs/engineering-standards.md` §2 — the return value is never asserted,
/// because `NavigatorState.maybePop` returns `true` for a deliberately blocked
/// pop too):
///
/// | where | handlePopRoute | HomeScreen after |
/// |---|---|---|
/// | bottom-bar destination 4 (`المزيد`) | **false** | **0** |
/// | Home | false | 1 |
/// | a pushed route (word detail) | true | 1 |
///
/// Read the first row. `MaterialApp`'s `home:` **is** the root route and the four
/// bar destinations are not routes at all — they are four widgets the bar swaps
/// inside one `AnimatedSwitcher`. So there was nothing for Android's back to pop
/// on any of the three non-Home tabs. `maybePop` reached the root route, found
/// `RoutePopDisposition.bubble` (the first route has nothing below it to bubble
/// *to*), returned `false` — and `false` is what tells the engine to call
/// `SystemNavigator.pop()`, which closes the app. That is the user's report, and
/// it explains why the pushed screens were fine: a pushed route is a real route
/// and popped normally all along.
///
/// **Why this lives on each destination and not on the shell**, which is where
/// it went first and where it was wrong. A `PopScope` is a *veto*, not a
/// consumer: when the root route's `popDisposition` comes back `doNotPop`,
/// `Route.onPopInvokedWithResult` fires **every** registered `PopEntry` on that
/// route with `didPop == false` — including entries that had nothing to do with
/// the block. Measured on `MoreScreen` with a confirmation open: the
/// confirmation's own `PopScope` cancelled the dialog as designed **and** the
/// shell's `PopScope` fired too, so one back press closed the dialog *and*
/// jumped the bar to Home. A control that cannot tell whether the block was its
/// own is not a control. With one `PopScope` per destination — and
/// `MoreScreen`'s folding its confirmation into the same one through [onBack] —
/// each back press has exactly one decision and one owner.
///
/// **Home has none, and that is the other half of what the user asked for.** On
/// Home nothing vetoes the pop, `maybePop` bubbles, and the engine closes the
/// app: «وان كان المستخدم في الصفحة الرئيسية عندها يخرج من التطبيق». Pinned by
/// `test/ui/back_navigation_test.dart` → *nothing vetoes the pop while Home is
/// showing*, which asserts the absence of a blocking `PopScope` in the tree
/// rather than a return value that means two different things.
class ShellBackToHome extends StatelessWidget {
  const ShellBackToHome({super.key, required this.child, this.onBack});

  final Widget child;

  /// Handles the back press instead of switching to Home.
  ///
  /// `MoreScreen` passes its confirmation's cancel here so that a back press
  /// closes the dialog **and stays on the tab**, rather than closing the dialog
  /// and jumping to Home. Null on the other destinations, which have nothing
  /// that could want a back press of its own.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      // Always false, on every destination. There is nothing above a
      // bottom-bar destination for back to pop to, so the route must not move;
      // what the press *means* is this widget's decision.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // `didPop` is always false while `canPop` is false; the guard is here so
        // a future `canPop` cannot turn the switch into a navigation. Same guard,
        // same reason, as `more_screen.dart` and `stats_screen.dart`.
        if (didPop) return;
        final handle = onBack;
        if (handle != null) {
          handle();
          return;
        }
        ShellTabScope.of(context)?.selectTab(_homeIndex);
      },
      child: child,
    );
  }
}

/// The index of `الرئيسية`, which is also index 0.
///
/// **Named rather than written as `0` at each use**, for the reason the rest of
/// this file repeats: a bare `0` in three places is three places a future
/// reordering of [_destinations] has to be found in, and two of them are
/// behaviour — the back button's target and the shell's own start — where
/// getting it wrong does not crash.
///
/// It is asserted equal to the index of `الرئيسية` in
/// `test/ui/back_navigation_test.dart`, so reordering the bar without moving
/// this is a red test rather than a back button that leaves from the wrong tab.
const int _homeIndex = 0;

/// The shell's selected destination, published to the screens inside it.
///
/// **Why this exists.** `HomeShell` owns the bottom bar's index, and Home's
/// quick-launch grid links to three of those same destinations. Pushing a route
/// for a destination the bar can already show leaves the bar highlighting
/// `الرئيسية` under a screen the user did not choose, and makes Back return to
/// Home rather than to the bar. Passing `onSelectTab` down through a constructor
/// is not available: `HomeScreen`'s signature is fixed by the interfaces Tasks 11
/// onwards depend on. So the shell hands the handler down the tree.
///
/// Read it with [ShellTabScope.of], and **only inside `build` or a callback** —
/// this depends on the inherited widget, so a `build` of an ancestor will not
/// see a later change. That is the right trade here: the grid is the only reader,
/// and it rebuilds anyway because the shell rebuilds.
class ShellTabScope extends InheritedWidget {
  const ShellTabScope({
    super.key,
    required this.index,
    required this.selectTab,
    required super.child,
  });

  /// Which destination is showing, as an index into the bar's order.
  final int index;

  /// Switches the bar to [index]. Out-of-range values are ignored by the shell,
  /// so a bad index cannot crash it.
  final ValueChanged<int> selectTab;

  /// The nearest enclosing scope, or null when there is none — which is what a
  /// screen mounted outside the shell sees, and what makes `HomeScreen` usable
  /// on its own in a test.
  static ShellTabScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellTabScope>();

  @override
  bool updateShouldNotify(ShellTabScope oldWidget) =>
      oldWidget.index != index || oldWidget.selectTab != selectTab;
}
