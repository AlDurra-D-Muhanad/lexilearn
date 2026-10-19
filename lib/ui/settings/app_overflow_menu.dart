import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/link/external_link.dart';
import 'package:lexilearn/ui/settings/app_info_screen.dart';
import 'package:lexilearn/ui/settings/app_settings_controller.dart';
import 'package:lexilearn/ui/theme/app_verdict_colors.dart';
import 'package:provider/provider.dart';

/// The menu's copy. Arabic, like every other chrome string in this app.
const String _appInfoLabel = 'معلومات التطبيق';
const String _themeSystem = 'حسب النظام';
const String _themeLight = 'فاتح';
const String _themeDark = 'داكن';
const String _telegramLabel = 'تواصل معي على تيلغرام';

/// Spelled out rather than left null, so a screen reader announces what the
/// control is instead of only its glyph — the same reason `_PackKeyBadge` and
/// `more_screen.dart`'s delete `IconButton` both carry one.
const String _menuTooltip = 'المزيد من الخيارات';

/// What one row of the menu means.
///
/// **A value object carrying the theme mode, not a bare enum.** The check mark
/// is what distinguishes `فاتح` from `داكن`, and an enum with three constants
/// cannot carry which mode each one stands for — `onSelected` would receive
/// `theme` three times and have to guess. Each row therefore hands back the mode
/// it stands for, and the switch has nothing left to infer.
@immutable
class _MenuValue {
  const _MenuValue.appInfo() : action = _MenuAction.appInfo, themeMode = null;
  const _MenuValue.theme(ThemeMode this.themeMode)
      : action = _MenuAction.theme;
  const _MenuValue.telegram() : action = _MenuAction.telegram, themeMode = null;

  final _MenuAction action;

  /// Non-null exactly when [action] is [_MenuAction.theme].
  final ThemeMode? themeMode;
}

enum _MenuAction { appInfo, theme, telegram }

/// The three-dot menu, identical on all four bottom-bar destinations.
///
/// **Why every destination gets one, and not only Home.** The user noticed its
/// absence on Home, and putting it there alone would be the worse outcome: an
/// app-level control that exists on one screen and not three reads as a bug on
/// the other three, and a user who learns "the menu is up top" on Home would
/// look for it on `البطاقات` and find nothing. The four destinations are the
/// app's four top-level surfaces — `HomeShell` builds them as `screens[0..3]` and
/// the bar indexes into that list — so they are exactly the four places where
/// "about this app", "how this app looks" and "who made this app" belong.
///
/// **The three pushed screens do not get one** — `WordDetailScreen`,
/// `FavoritesScreen` and `StatsScreen` — and that is a decision rather than an
/// oversight. They are sub-screens reached *from* Home's grid, they keep their
/// own back arrow, and app-level chrome on a screen the user is reading a word
/// on is clutter. Each can still reach this menu by going back.
///
/// **Where it sits per screen, and why it moves no layout.** Three of the four
/// destinations own an `AppBar` and the menu goes in that bar's `actions` slot,
/// next to whatever was already there; Home has no `AppBar` at all, so its menu
/// goes at the end of the existing `_Header` row. Both are the one place each
/// layout already has for a trailing control, so no screen's measured body moves.
///
/// **It reads the theme choice from the controller rather than owning it.** A
/// `PopupMenuButton` builds its route each time it opens, so the check beside
/// `داكن` is correct the moment the menu is next opened even if the choice was
/// made minutes ago on another screen. See `AppSettingsController` for why the
/// choice is stored rather than flipped.
class AppOverflowMenu extends StatelessWidget {
  const AppOverflowMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final openUrl = context.read<OpenExternalUrl>();

    return PopupMenuButton<_MenuValue>(
      // Material's own three dots. `Icons.more_vert` is the same glyph the
      // artwork's `المزيد` bar item sits beside, so the control and the
      // destination it complements are drawn identically.
      icon: const Icon(Icons.more_vert),
      tooltip: _menuTooltip,
      // **No local colour.** `IconButton` resolves to `onSurfaceVariant`, which
      // `app_theme.dart` pins to the secondary-text role; forcing one here would
      // be the per-widget opt-out `docs/engineering-standards.md` §7 exists to
      // end.
      onSelected: (value) => _run(context, value, settings, openUrl),
      itemBuilder: (context) => <PopupMenuEntry<_MenuValue>>[
        const PopupMenuItem<_MenuValue>(
          value: _MenuValue.appInfo(),
          child: _Row(icon: Icons.info_outline, label: _appInfoLabel),
        ),
        const PopupMenuDivider(),
        // Three items, one of which is always the current mode — not a single
        // "flip" entry. A toggle cannot express "go back to following the
        // system", and the user is entitled to that: `ThemeMode.system` is a
        // real option, not the absence of one.
        _themeRow(settings, ThemeMode.system, Icons.brightness_auto, _themeSystem),
        _themeRow(settings, ThemeMode.light, Icons.light_mode, _themeLight),
        _themeRow(settings, ThemeMode.dark, Icons.dark_mode, _themeDark),
        const PopupMenuDivider(),
        const PopupMenuItem<_MenuValue>(
          value: _MenuValue.telegram(),
          // The user's own words: a Telegram entry, with a Telegram icon.
          child: _Row(icon: Icons.telegram, label: _telegramLabel),
        ),
      ],
    );
  }

  /// The row for one theme mode, checked when it is the current one.
  ///
  /// The check sits at the row's own trailing edge, which in this app's RTL
  /// reading order is the left — the same place `ListTile` puts `trailing`, and
  /// the same place a user looks for "what is selected".
  PopupMenuItem<_MenuValue> _themeRow(
    AppSettingsController settings,
    ThemeMode mode,
    IconData icon,
    String label,
  ) =>
      PopupMenuItem<_MenuValue>(
        value: _MenuValue.theme(mode),
        child: _Row(
          icon: icon,
          label: label,
          checked: settings.mode == mode,
        ),
      );

  void _run(
    BuildContext context,
    _MenuValue value,
    AppSettingsController settings,
    OpenExternalUrl openUrl,
  ) {
    switch (value.action) {
      case _MenuAction.appInfo:
        // `Navigator.of(context)` resolves the nearest navigator — the one that
        // owns the shell's route — so the pushed screen lands inside the app and
        // the bottom bar's own overlay is not disturbed. Left un-discarded
        // because that is how every other push in `lib/ui/` writes it.
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AppInfoScreen()),
        );
      case _MenuAction.theme:
        settings.setMode(value.themeMode!).ignore();
      case _MenuAction.telegram:
        openUrl(telegramContactUri).ignore();
    }
  }
}

/// A menu row: leading icon, label, and an optional check.
///
/// One private widget for all three kinds, so the icon column and the gap are
/// decided once. Three near-identical `Row`s inside one `itemBuilder` is how the
/// Telegram row ends up with its icon 4px off the other two.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.checked = false,
  });

  final IconData icon;
  final String label;

  /// Draw the tick beside this row. Used by the theme rows only.
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.onSurface),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyLarge),
        ),
        if (checked)
          Icon(
            Icons.check_circle,
            size: 18,
            // The brand's success token for this brightness, the same value the
            // quiz draws its right-answer tick in. Read through the verdict
            // extension rather than written as an `isDark ? … : …`, because
            // `AppVerdictColors.correctBorder` already is that value and a second
            // spelling of it is a second thing to keep right.
            color: AppVerdictColors.of(context).correctBorder,
          ),
      ],
    );
  }
}