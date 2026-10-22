import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/dictionary/attribution_screen.dart';
import 'package:lexilearn/ui/dictionary/dictionary_controller.dart';
import 'package:lexilearn/ui/settings/app_info_screen.dart';
import 'package:lexilearn/ui/settings/app_settings_controller.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_verdict_colors.dart';
import 'package:provider/provider.dart';

/// The menu's copy. Arabic, like every other chrome string in this app.
const String _appInfoLabel = 'معلومات التطبيق';
const String _attributionLabel = 'المصادر';
const String _themeSystem = 'حسب النظام';
const String _themeLight = 'فاتح';
const String _themeDark = 'داكن';

/// Spelled out rather than left null, so a screen reader announces what the
/// control is instead of only its glyph — the same reason `_PackKeyBadge` and
/// `more_screen.dart`'s delete `IconButton` both carry one.
const String _menuTooltip = 'المزيد من الخيارات';

/// How wide the panel is.
///
/// **A fixed width, and the reason it is fixed.** The panel is a column of
/// rows whose widest content is an Arabic label, and a panel that sized itself
/// to its content would be a different width on every row — or narrower than
/// the label it carries. 248 logical px fits the longest of the app's own
/// labels («تواصل معي على تيلغرام» used to be the longest; the Telegram row
/// has moved to the app-info screen) with the icon column and the padding
/// around it.
const double _panelWidth = 248;

/// The gap between the button and the panel it opens.
const double _panelGap = 6;

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
  const _MenuValue.attribution()
      : action = _MenuAction.attribution,
        themeMode = null;
  const _MenuValue.theme(ThemeMode this.themeMode)
      : action = _MenuAction.theme;

  final _MenuAction action;

  /// Non-null exactly when [action] is [_MenuAction.theme].
  final ThemeMode? themeMode;
}

enum _MenuAction { appInfo, attribution, theme }

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
/// menu builds its panel each time it opens, so the check beside `داكن` is
/// correct the moment the menu is next opened even if the choice was made
/// minutes ago on another screen. See `AppSettingsController` for why the
/// choice is stored rather than flipped.
///
/// ## The panel, and why it is not `PopupMenuButton`
///
/// **The user's own words: «نافذة الثلاث نقاط بدائية وغير ملائمة للثيم و تعطي
/// طابع غير احترافي»** — the three-dot window is primitive, does not suit the
/// theme, and gives an unprofessional impression. The screenshot shows what
/// they mean: Material's default panel is a grey rectangle with square-ish
/// corners, stock Material glyphs, and it hangs off the top-left corner over
/// the content.
///
/// **So the panel is this app's own surface.** It is an `AppSurface` — the
/// brand's radius, the brand's hairline, the brand's shadow — and its rows
/// carry the brand's accent. `PopupMenuButton` was replaced rather than
/// restyled, because Material's popup route brings its own background, its own
/// shape and its own anchoring, and every one of those three is what the user
/// objected to.
///
/// **The panel is drawn in the app's `Overlay`, not in the button's own
/// subtree**, so it is not clipped by the `AppBar` it hangs out of and it
/// paints over the bottom bar rather than under it.
///
/// **The exact look is a judgement, and it is marked as one.** The reference
/// image does not show an open menu, so there is no artwork to copy: the
/// radius, the surface and the border are the app's own tokens and the
/// accent-coloured icons are the brand's, and everything else is the obvious
/// thing to do with those.
class AppOverflowMenu extends StatefulWidget {
  const AppOverflowMenu({super.key, this.edgeInset = AppSpacing.m});

  /// **The gap between the screen's outer edge and the button's own box.**
  ///
  /// **Why this is a parameter and not a constant.** The button is at the
  /// outer edge of the screen on all four destinations, but the two layouts
  /// that put it there give it a different amount of room:
  ///
  /// * the three destinations with an `AppBar` put it in the bar's `actions`
  ///   slot, which is **flush against the screen's edge** — the bar's own
  ///   margin is the title's, not the actions';
  /// * Home has no `AppBar` at all and puts it at the end of the header row,
  ///   whose own padding is the page's **16 px** margin.
  ///
  /// **So the AppBar screens had the glyph 16 px further out than Home's** —
  /// measured off the committed reference images, the glyph's centre sits at
  /// **28 logical px** from the screen's edge on Home and at **11.8** on the
  /// More screen. The user named it: «زر الثلاث نقاط قريب جدا من حافة الشاشة
  /// اجعله كما في الشاشة الرئيسية» — the three-dot button is far too close to
  /// the edge of the screen; make it as it is on the home screen.
  ///
  /// **The default is the AppBar's case**, because three of the four
  /// destinations are AppBar screens and a new one should be right by
  /// default. **Home passes zero**, because its row already carries the page's
  /// margin and adding this one on top of it would double it.
  ///
  /// `test/ui/app_settings_test.dart` → *the button is the same distance from
  /// the edge on every destination* is what holds the two together.
  final double edgeInset;

  @override
  State<AppOverflowMenu> createState() => _AppOverflowMenuState();
}

class _AppOverflowMenuState extends State<AppOverflowMenu> {
  /// The link between the button and the panel, so the panel knows where the
  /// button is without the button's position being written down anywhere.
  final LayerLink _link = LayerLink();

  final OverlayPortalController _portal = OverlayPortalController();

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
      return;
    }
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _MenuPanel(
          link: _link,
          settings: settings,
          onDismiss: _portal.hide,
        ),
        child: Padding(
          // **The end side, and the end is the screen's outer edge.** The
          // button sits at the end of the row in both directions, so the gap
          // belongs on the end side in both — and in this Arabic app the end
          // is the physical left.
          padding: EdgeInsetsDirectional.only(end: widget.edgeInset),
          child: _MenuButton(onTap: _toggle),
        ),
      ),
    );
  }
}

/// The three dots themselves.
///
/// **The button the reference draws, and the position the user asked for.**
///
/// The reference puts the ellipsis at the header's outer edge: measured off
/// `new theme.png`, the glyph's centre sits at **28.9 logical px** from the
/// screen's left edge, while the content's own margin is 16 — so the glyph is
/// **12.9 px inside the margin**, not in the middle of a 48 px button.
///
/// The app's own button was Material's `IconButton` inside the
/// `PopupMenuButton`, whose glyph is centred in a 48 px tap target and so
/// landed at **39.8 logical px** — more than eleven pixels further in, and
/// visibly not "in the corner". This button keeps a **48 px touch target**
/// and moves the **glyph** to the reference's position instead, which is the
/// only way to have both: a finger-sized target and the artwork's mark.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Semantics(
      button: true,
      label: _menuTooltip,
      child: Tooltip(
        message: _menuTooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          // **The 48 px target, and the glyph at the reference's place.**
          //
          // The reference puts the ellipsis at the header's outer edge:
          // measured off `new theme.png`, the glyph's centre sits at **28.9
          // logical px** from the screen's left edge, while the content's own
          // margin is 16 — so the glyph is essentially flush with the margin.
          //
          // The app's own button was Material's `IconButton` inside the
          // `PopupMenuButton`, whose glyph is centred in a 48 px tap target
          // and so landed at **39.8 logical px** — more than eleven pixels
          // further in, and visibly not "in the corner". This button keeps a
          // **48 px touch target** and moves the **glyph** to the reference's
          // position instead, which is the only way to have both: a
          // finger-sized target and the artwork's mark.
          //
          // `AlignmentDirectional.centerEnd` puts the glyph at the *end* of
          // the tap target. The app is right-to-left throughout, so the end
          // is the physical left — which is the header's outer edge and the
          // side the reference draws the ellipsis on.
          //
          // The target is 48 wide and the glyph's own box is 24, so the
          // glyph's centre lands at 16 + 12 = **28 logical px** from the
          // screen's left edge, against the reference's measured **28.9**.
          child: SizedBox(
            width: 48,
            height: 48,
            // **The 48 px target, and the glyph at the reference's place.**
            //
            // `AlignmentDirectional.centerEnd` puts the glyph at the *end* of
            // the tap target. The app is right-to-left throughout, so the end
            // is the physical left — which is the header's outer edge and the
            // side the reference draws the ellipsis on.
            //
            // The target is 48 wide and the glyph's own box is 24, so the
            // glyph's centre lands at 16 + 12 = **28 logical px** from the
            // screen's left edge, against the reference's measured **28.9**.
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Icon(Icons.more_vert, color: secondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel the button opens.
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.link,
    required this.settings,
    required this.onDismiss,
  });

  final LayerLink link;
  final AppSettingsController settings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.accentInk(isDark);

    return Stack(
      children: <Widget>[
        // The barrier, so a tap anywhere else closes the panel. It is
        // transparent and it takes the tap, which is what a menu wants.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          // **Below the button, and aligned with its outer edge.**
          //
          // The button is at the header's outer — the left — edge, and the
          // panel is 248 wide, so aligning the panel's *left* edge with the
          // button's keeps it on the screen. Aligning the other way would push
          // most of it off the left edge, which is what the stock popup did.
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, _panelGap),
          child: Material(
            // The panel is transparent: the `AppSurface` below is the whole
            // of its look, and a `Material` here would add a second one.
            type: MaterialType.transparency,
            child: AppSurface(
              borderRadius: BorderRadius.circular(AppRadii.md),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: SizedBox(
                width: _panelWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _MenuRow(
                      icon: Icons.info_outline,
                      label: _appInfoLabel,
                      colour: accent,
                      onTap: () => _run(context, _MenuValue.appInfo()),
                    ),
                    // **The dictionary's licence, and it is an obligation rather
                    // than a courtesy.** The dictionary is CC-BY-SA-4.0, and
                    // that licence obliges an application shipping it to name
                    // the licence and its sources. The screen reads them out of
                    // the dictionary's own `meta` table and invents nothing.
                    //
                    // **The icon is a library of books, and the reason is what
                    // the row is.** The user's own words: «تعديل اخير: ايقونة
                    // الميزان بجانب كلمة المصادر غير مناسبة ابدلها» — the
                    // balance icon beside «المصادر» is not suitable; change
                    // it. A pair of scales reads as *justice*, *weighing* and
                    // *balance*, and the row it sits beside is about where the
                    // words came from and who wrote them — a licence, three
                    // upstream projects and their credits.
                    //
                    // **A library is what that is.** `library_books_outlined` is
                    // a shelf of books: the collection the app's words are read
                    // out of, which is exactly what the screen it opens lists.
                    // It is in the Material set, it is in the same *book* family
                    // the identity already uses (the gold book mark on Home,
                    // the book disc on the results screen), and it says
                    // "sources" where a pair of scales said "weighing".
                    _MenuRow(
                      icon: Icons.library_books_outlined,
                      label: _attributionLabel,
                      colour: accent,
                      onTap: () => _run(context, _MenuValue.attribution()),
                    ),
                    const Divider(height: AppSpacing.l),
                    // Three items, one of which is always the current mode — not
                    // a single "flip" entry. A toggle cannot express "go back
                    // to following the system", and the user is entitled to
                    // that: `ThemeMode.system` is a real option, not the
                    // absence of one.
                    _MenuRow(
                      icon: Icons.brightness_auto,
                      label: _themeSystem,
                      colour: accent,
                      checked: settings.mode == ThemeMode.system,
                      onTap: () =>
                          _run(context, _MenuValue.theme(ThemeMode.system)),
                    ),
                    _MenuRow(
                      icon: Icons.light_mode,
                      label: _themeLight,
                      colour: accent,
                      checked: settings.mode == ThemeMode.light,
                      onTap: () =>
                          _run(context, _MenuValue.theme(ThemeMode.light)),
                    ),
                    _MenuRow(
                      icon: Icons.dark_mode,
                      label: _themeDark,
                      colour: accent,
                      checked: settings.mode == ThemeMode.dark,
                      onTap: () =>
                          _run(context, _MenuValue.theme(ThemeMode.dark)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _run(BuildContext context, _MenuValue value) {
    // **The navigator and the controller are read before the panel closes.**
    //
    // The panel's own context is unmounted the moment it is hidden, and the
    // attribution's read is a *real* one that takes a turn — so a liveness
    // check on that context after the await would give up and never open the
    // screen. The navigator is a `NavigatorState`, which is mounted for as
    // long as the app is, so the check moves to something that is still true.
    final navigator = Navigator.of(context);
    final controller = context.read<DictionaryController>();

    onDismiss();
    switch (value.action) {
      case _MenuAction.appInfo:
        // `Navigator.of(context)` resolves the nearest navigator — the one that
        // owns the shell's route — so the pushed screen lands inside the app
        // and the bottom bar's own overlay is not disturbed. Left un-discarded
        // because that is how every other push in `lib/ui/` writes it.
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AppInfoScreen()),
        );
      case _MenuAction.attribution:
        _openAttribution(navigator, controller);
      case _MenuAction.theme:
        settings.setMode(value.themeMode!).ignore();
    }
  }

  /// Opens the dictionary's attribution screen.
  ///
  /// **The licence obligation, and the read is off the menu's own path.** The
  /// attribution comes out of the dictionary's `meta` table, so the screen
  /// cannot be built until the dictionary is there; the read is awaited and
  /// the route is pushed when it answers.
  Future<void> _openAttribution(
    NavigatorState navigator,
    DictionaryController controller,
  ) async {
    final attribution = await controller.attribution();
    if (!navigator.mounted) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AttributionScreen(attribution: attribution),
      ),
    );
  }
}

/// A menu row: leading icon, label, and an optional check.
///
/// One private widget for all three kinds, so the icon column and the gap are
/// decided once. Three near-identical `Row`s inside one `itemBuilder` is how
/// the Telegram row used to end up with its icon 4px off the other two.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
    this.checked = false,
  });

  final IconData icon;
  final String label;

  /// The icon's colour: the brand's accent, as ink.
  final Color colour;

  /// Draw the tick beside this row. Used by the theme rows only.
  final bool checked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.s,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: colour),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (checked)
              Icon(
                Icons.check_circle,
                size: 18,
                // The brand's success token for this brightness, the same value the
                // quiz draws its right-answer tick in. Read through the verdict
                // extension rather than written as an `isDark ? … : …`, because
                // `AppVerdictColors.correctBorder` already is that value and a
                // second spelling of it is a second thing to keep right.
                color: AppVerdictColors.of(context).correctBorder,
              ),
          ],
        ),
      ),
    );
  }
}
