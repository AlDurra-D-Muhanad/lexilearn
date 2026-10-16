import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

import 'flashcards/flashcards_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'quiz/quiz_setup_screen.dart';

/// The bottom-bar shell: one destination at a time, and the pack they share.
///
/// [repository] is used once, at start-up, to resolve which pack the app is
/// working on. Everything after that is state local to this widget, so the four
/// screens never have to reach back into the data layer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final VocabRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The pack every destination is scoped to. Empty until [widget.repository]
  /// answers, and empty for good when no pack is installed.
  String _activePackKey = '';

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
  /// heart action on the word card (`Task 14` builds `WordDetailScreen` and
  /// pushes `FavoritesScreen` from there) and from the `المفضلة` tile in Home's
  /// 2×2 quick-launch grid (`Task 10` builds that grid). `FavoritesScreen`
  /// already exists at `lib/ui/favorites/favorites_screen.dart`; it is simply
  /// not a bar destination, so this file no longer imports it. See
  /// `docs/design/style-direction.md` → Navigation.
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
    _loadActivePack();
  }

  Future<void> _loadActivePack() async {
    final packs = await widget.repository.packs();
    // A shell torn down mid-query, or an install with no pack at all, leaves
    // the key empty and every screen renders its own empty state.
    if (!mounted || packs.isEmpty) return;
    setState(() => _activePackKey = packs.first.packKey);
  }

  void _selectPack(String packKey) => setState(() => _activePackKey = packKey);

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
  /// Deliberately empty until Task 14 lands: `WordDetailScreen` does not exist
  /// yet and this task must not import a path that does not exist. Its only
  /// caller is Home's quick-launch grid, which is itself a Task 10 placeholder
  /// that never fires it. Task 14 replaces this body with the `Navigator.push`
  /// of `WordDetailScreen(entry: entry)`.
  void _openWordDetail(VocabEntry entry) {}

  @override
  Widget build(BuildContext context) {
    // Same order as `_destinations`, and the same length. Index-for-index.
    final screens = <Widget>[
      HomeScreen(
        packKey: _activePackKey,
        onPackSelected: _selectPack,
        onOpenWord: _openWordDetail,
      ),
      FlashcardsScreen(packKey: _activePackKey),
      QuizSetupScreen(packKey: _activePackKey, onPackSelected: _selectPack),
      MoreScreen(packKey: _activePackKey, onPackSelected: _selectPack),
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
