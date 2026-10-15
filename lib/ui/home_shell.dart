import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

import 'flashcards/flashcards_screen.dart';
import 'favorites/favorites_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'quiz/quiz_setup_screen.dart';

/// The bottom-bar shell: one destination at a time, and the pack they share.
///
/// [repository] is used once, at start-up, to resolve which pack the app is
/// working on. Everything after that is state local to this widget, so the five
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

  /// The brand's five destinations, in bar order.
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
  /// match the expected five, and every one of them lands on its own screen.
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
      icon: Icon(Icons.checklist_rtl),
      selectedIcon: Icon(Icons.checklist),
      label: 'الاختبارات',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_border),
      selectedIcon: Icon(Icons.favorite),
      label: 'المفضلة',
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz),
      selectedIcon: Icon(Icons.more_horiz),
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

  /// Opens the word detail view for [entry].
  ///
  /// Deliberately empty until Task 14 lands: `WordDetailScreen` does not exist
  /// yet and this task must not import a path that does not exist. Both callers
  /// are Task 9 shells that never fire it. Task 14 replaces this body with the
  /// `Navigator.push` of `WordDetailScreen(entry: entry)`.
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
      FavoritesScreen(packKey: _activePackKey, onOpenWord: _openWordDetail),
      MoreScreen(packKey: _activePackKey, onPackSelected: _selectPack),
    ];

    return Scaffold(
      body: SafeArea(
        // One movement per tab change, at the brand's fast duration — the
        // style direction reserves `AppDurations.fast` for exactly this. The
        // key is the index, so changing packs inside a destination updates the
        // screen in place instead of replaying the transition.
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          child: KeyedSubtree(
            key: ValueKey<int>(_index),
            child: screens[_index],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: _destinations,
      ),
    );
  }
}
