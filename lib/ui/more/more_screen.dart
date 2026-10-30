import 'package:flutter/material.dart';
// `PackSummary` is what `VocabRepository.packs()` returns and it lives in the
// DAO; `quiz_setup_screen.dart` imports it from the same place. Re-exporting it
// from the repository would be tidier and would make that import redundant,
// i.e. an analyzer issue in a file this task has no business editing.
import 'package:lexilearn/data/pack_dao.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/domain/my_favourites_pack.dart';
import 'package:lexilearn/ui/packs/packs_controller.dart';
import 'package:lexilearn/ui/home_shell.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';
import 'package:lexilearn/ui/stats/stats_controller.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

/// The chrome, in Arabic — the app is RTL end to end and the artwork's chrome is
/// Arabic. Every number, every pack key and every language pair below is a Latin
/// run and says so with `textDirection: TextDirection.ltr` and `AppText.latin`,
/// because an RTL paragraph reorders a run of digits and slashes.
const String _title = 'المزيد';
const String _statsHeading = 'إحصائياتك';
const String _packsHeading = 'الحزم';
const String _backupHeading = 'النسخ الاحتياطي';
const String _bundledChip = 'مدمجة';
const String _importPack = 'استيراد حزمة';
const String _exportBackup = 'تصدير نسخة احتياطية';
const String _restoreBackup = 'استعادة نسخة احتياطية';
const String _delete = 'حذف';
const String _deleteTooltip = 'حذف الحزمة';
const String _activePack = 'الحزمة الحالية';
const String _wordUnit = 'كلمة';
const String _cancel = 'إلغاء';
const String _busy = 'جارٍ التنفيذ…';
const String _nothingHere = 'لا توجد حزم بعد.';

/// The statistics tile labels. The same four words `stats_screen.dart` uses, so
/// the same number read on either screen is named the same way.
const String _accuracyLabel = 'نسبة الدقة';
const String _attemptsLabel = 'إجمالي الإجابات';
const String _practisedLabel = 'كلمات تدربت عليها';
const String _masteredLabel = 'كلمات أتقنتها';

/// The accuracy ring's outer diameter, the same 128 px `stats_screen.dart`
/// draws.
///
/// Re-declared rather than imported because that file names it as a private
/// constant of *its* layout, and a task not allowed to edit `stats_screen.dart`
/// cannot widen its visibility. Deliberately the same number: the two screens
/// draw one widget in two places, and a second destination rendering the same
/// proportion at a different size would read as a different widget.
const double _ringDiameter = 128;

/// The weight of the accuracy ring.
const double _ringStroke = 2;

/// The brand's **fourth** destination: `المزيد`, reached from the bottom bar.
///
/// It is the fourth of four, not a fifth thing statistics belongs to.
/// `docs/design/brand-reference.png` draws exactly four items in the bar —
/// الرئيسية, البطاقات, الاختبارات, المزيد — in the light phone and again in the
/// dark one, and Amendment 1 in `docs/design/style-direction.md` corrects an
/// earlier five-destination draft back to four. `lib/ui/home_shell.dart` and
/// `test/ui/home_shell_test.dart` pin all four.
///
/// **What is on this page, in this order, and why.** One scrollable page behind
/// one AppBar:
///
/// 1. the active pack's accuracy ring and its three figures;
/// 2. every installed pack, the active one marked, an imported one deletable;
/// 3. import a `.json` pack, export a whole backup, restore a whole backup;
/// 4. one reset control, confirmed before it acts.
///
/// **Two inferences, marked as inferences.** The artwork draws no `المزيد`
/// screen at all — `brand-reference.png` shows the Home, word-detail and
/// flashcards phones — so this layout came from the brief plus the surrounding
/// screens and not from the PNG. And statistics is *also* reached from the
/// `إحصائياتك` tile on Home, which is where `lib/ui/home/home_screen.dart` puts
/// it and which `test/ui/stats_screen_test.dart` still pins. The two doors are
/// additive; neither replaces the other, and no bar destination changed.
///
/// `StatsScreen`'s own body is not embedded here: it is a `Scaffold` whose
/// confirm layer is a `Stack` of `Positioned.fill`, and neither can live inside
/// the unbounded-height scroll view this page is. The four figures are re-drawn
/// instead, from the same controller and the same tokens — duplicated on
/// purpose, because `stats_screen.dart` is outside this task's file list and its
/// body is private. What is deliberately *not* duplicated is the destructive
/// control: two `مسح التقدم` buttons on one page would be two controls for one
/// action.
class MoreScreen extends StatefulWidget {
  const MoreScreen({
    super.key,
    required this.packKey,
    required this.onPackSelected,
  });

  /// The pack every figure on this page is scoped to, and the one its row marks
  /// as active. Empty until `HomeShell` resolves it at start-up, and empty for
  /// good when nothing is installed.
  final String packKey;

  /// Switches the app's active pack.
  ///
  /// This is the only place in the app that offers the choice:
  /// `lib/ui/home/home_screen.dart` deliberately *shows* the pack and says so —
  /// "the pack picker is Task 13's".
  final ValueChanged<String> onPackSelected;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  /// The pack list and the file actions.
  ///
  /// Read from the tree when a test has provided one and created here when
  /// nothing has — the same two-path shape `StatsScreen` uses for its own
  /// controller, and for the same reason: the app provides neither, while a test
  /// that needs a `pickJsonFile` it controls (so no file dialog is ever
  /// involved) has to hand the same instance in.
  late final PacksController _packs;

  /// True when this state created [_packs] and so owns its lifetime.
  bool _ownsPacks = false;

  /// [StatsController] for the active pack.
  ///
  /// Owned, never injected: the figures come from the database the screen
  /// already has, and a test seeds that database before pumping rather than
  /// handing over a half-built controller. See `StatsScreen` → `_StatsOwner`.
  late StatsController _stats;

  /// What the open confirmation is asking about, or null when nothing is open.
  ///
  /// One field rather than a `bool` plus a second: two fields describing one
  /// state are two fields that can disagree, and a screen with a "delete this
  /// pack" confirmation open behind a "reset your progress" confirmation is not
  /// a state worth being able to represent.
  _Confirmation? _confirmation;

  /// What just happened, in words.
  ///
  /// A line in the page rather than a `SnackBar`: a `SnackBar` schedules its own
  /// dismissal timer, which is one more reason `pumpAndSettle` can outlast the
  /// thing a test is waiting for, and a pack switch should still be readable
  /// after the message has gone.
  String? _notice;

  @override
  void initState() {
    super.initState();
    _packs = _resolvePacks()..load();
    _stats = _createStats();
  }

  /// The provided controller, or a new one.
  ///
  /// `context.read` is safe in `initState` — it does not subscribe — which is the
  /// same reason `home_screen.dart` reads its repository there.
  PacksController _resolvePacks() {
    final provided = context.read<PacksController?>();
    if (provided != null) return provided;
    _ownsPacks = true;
    return PacksController(repository: context.read<VocabRepository>());
  }

  /// Fired from `initState`, not from a post-frame callback: the read is
  /// genuinely in flight while the first frame is built, which is why
  /// `StatsController` guards every notification with its own liveness check.
  StatsController _createStats() => StatsController(
        repository: context.read<VocabRepository>(),
        packKey: widget.packKey,
      )..load();

  @override
  void didUpdateWidget(MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packKey == widget.packKey) return;
    // A pack switch is a new controller, not a re-read: the key is held on the
    // controller so no call site can forget to pass it, and that is only true
    // while the instance matches the pack on screen.
    final previous = _stats;
    _stats = _createStats();
    previous.dispose();
  }

  @override
  void dispose() {
    // Only what this state made. A controller handed in by a test outlives the
    // widget, and disposing it here would tear down the caller's own fixture.
    if (_ownsPacks) _packs.dispose();
    _stats.dispose();
    super.dispose();
  }

  /// Closes the confirmation without acting.
  ///
  /// Named so the three ways out are one behaviour rather than three expressions
  /// that happen to agree: the `إلغاء` button, the `PopScope` callback Android's
  /// back reaches, and the close at the top of [_run].
  void _cancel() => setState(() => _confirmation = null);

  /// Closes the confirmation and then does what it asked about.
  ///
  /// The layer is dismissed *first* so the screen does not sit showing a dialog
  /// it is already acting on — the same ordering `stats_screen.dart` records.
  Future<void> _run(_Confirmation confirmation) async {
    _cancel();
    final pack = confirmation.pack;
    if (pack == null) {
      await _stats.reset();
      return;
    }
    await _packs.deletePack(pack.packKey);
    if (!mounted) return;
    setState(() => _notice = 'تم حذف «${pack.title}».');
  }

  void _selectPack(String packKey) {
    if (packKey == widget.packKey) return;
    widget.onPackSelected(packKey);
    setState(() => _notice = 'تم اختيار الحزمة النشطة.');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // **The app's back button, and the reason this screen has exactly one
    // `PopScope`.** Back from a bar destination goes to Home
    // (`ShellBackToHome`). This screen also has a destructive confirmation to
    // close, and for a long time each of those wanted its own `PopScope`. They
    // cannot both have one: a `PopScope` is a veto, not a consumer, so a blocked
    // pop fires *every* `PopEntry` registered on the route with `didPop ==
    // false` — measured: one back press closed the confirmation **and** jumped
    // the bar to Home. So the confirmation is folded into the one handler through
    // `onBack`, and it is `onBack` (rather than a second scope) that keeps the tab
    // where the user is while a dialog is up. See `ShellBackToHome`.
    //
    // `null` while no confirmation is open, which is what lets the default
    // "go to Home" behaviour through.
    return ShellBackToHome(
      onBack: _confirmation == null ? null : _cancel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(_title),
          // The header sits on the background rather than on a raised surface,
          // matching the artwork's word-card header. The AppBar's own default is
          // `surfaceContainer`, which would draw a second tone across the top of a
          // screen whose only surfaces are the cards below it.
          backgroundColor:
              isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          surfaceTintColor: Colors.transparent,
          // The app's overflow menu, in the actions slot this bar already has and
          // was not using. One of four destinations that carry it — see
          // `AppOverflowMenu` for why the control is on all four and not only on
          // Home, and for the three pushed screens that deliberately do not.
          actions: const <Widget>[AppOverflowMenu()],
        ),
        body: SafeArea(
          child: Stack(
            // `Positioned.fill` rather than a bare child, so the confirmation
            // layer can cover the scroll view and so its own `Positioned.fill`
            // has a bounded box to fill. The same two reasons
            // `stats_screen.dart` stacks its own body this way.
            children: <Widget>[
              Positioned.fill(child: _page()),
              if (_confirmation != null)
                Positioned.fill(
                  // **No `PopScope` here any more, and that is the fix rather
                  // than a simplification.** This layer used to carry its own
                  // `canPop: false` wrapper so that Android's back would cancel
                  // the confirmation instead of leaving the screen — a defect
                  // measured on `stats_screen.dart`'s identical layer first
                  // (`tester.binding.handlePopRoute()` returned `true`, the
                  // screen's count went to 0 and the host route came back). The
                  // wrapper worked, and then it stopped being the only one:
                  // `ShellBackToHome` above also vetoes the same route, and both
                  // `PopEntry`s fire on every blocked pop. Two vetoes for one
                  // press meant one press cancelled the dialog *and* left the
                  // tab. The cancel now arrives through `ShellBackToHome.onBack`
                  // and this layer is a plain child, which is what makes
                  // `test/ui/more_screen_test.dart` → *back cancels the
                  // confirmation and stays on the tab* green rather than a test
                  // that has to pick which of two scopes won.
                  child: _ConfirmLayer(
                    confirmation: _confirmation!,
                    onCancel: _cancel,
                    onConfirm: _run,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page() {
    return ListenableBuilder(
      // Both controllers in one builder, so the whole page repaints on either.
      // Two nested `ListenableBuilder`s would draw the same pixels and give two
      // places to forget one.
      listenable: Listenable.merge(<Listenable>[_stats, _packs]),
      builder: (context, _) {
        final busy = _packs.isBusy;
        return SingleChildScrollView(
          // A scroll view rather than a `ListView` because the tests assert the
          // *vertical order* of two sections by their laid-out positions, and a
          // `ListView` does not build the children it has scrolled past — it
          // would drop the second one out of the tree rather than place it below
          // the first. `SingleChildScrollView` lays out every child and only
          // clips.
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _StatsSection(controller: _stats),
              const SizedBox(height: AppSpacing.l),
              _PacksSection(
                packs: _packs.packs,
                activePackKey: widget.packKey,
                busy: busy,
                onSelected: _selectPack,
                onDeleteRequested: (pack) => setState(
                    () => _confirmation = _Confirmation.delete(pack)),
              ),
              const SizedBox(height: AppSpacing.l),
              _BackupSection(
                busy: busy,
                message: _packs.message,
                error: _packs.error,
                notice: _notice,
                onImport: _packs.importFromPicker,
                onExport: _packs.exportBackup,
                onRestore: _packs.restoreFromPicker,
              ),
              const SizedBox(height: AppSpacing.l),
              _ResetButton(
                onPressed: () =>
                    setState(() => _confirmation = const _Confirmation.reset()),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What an open confirmation is asking about.
///
/// A value rather than two booleans, so "which destructive action is pending" is
/// one answer and not a combination. [pack] is null exactly for a progress
/// reset; every other field is the copy that action shows.
@immutable
class _Confirmation {
  const _Confirmation.reset()
      : pack = null,
        title = 'مسح التقدم؟',
        body =
            'سيؤدي هذا إلى حذف كل إجاباتك وسجل جلساتك في هذه الحزمة، ولا يمكن التراجع.',
        confirmLabel = 'مسح التقدم';

  const _Confirmation.delete(PackSummary this.pack)
      : title = 'حذف الحزمة؟',
        body =
            'سيؤدي هذا إلى حذف مفرداتها وكل ما سُجّل عنها من تقدّم، ولا يمكن التراجع.',
        confirmLabel = _delete;

  final PackSummary? pack;
  final String title;
  final String body;
  final String confirmLabel;
}

/// The active pack's figures: accuracy as a ring, then three numbers.
///
/// Drawn from [StatsController] to the same rules as
/// `lib/ui/stats/stats_screen.dart`: brand ink rather than the accent, a
/// **determinate** progress indicator, numerals as an explicit Latin run, and a
/// hairline-bordered track. A determinate indicator is what makes `pumpAndSettle`
/// return at all — the indeterminate one schedules frames forever.
class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.controller});

  final StatsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = AppColors.accentInk(isDark);
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final summary = controller.summary;

    // Nothing to show is not "zero". A fresh install and a pack with no answers
    // draw the same numbers, and a row of zeros next to a 0% is
    // indistinguishable from having answered everything wrong.
    final nothing = summary.totalAttempts == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(_statsHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.s),
        if (controller.isLoading)
          Text(_busy, style: theme.textTheme.bodySmall?.copyWith(color: secondary))
        else if (controller.error != null && nothing)
          Text(
            'تعذّر تحميل الإحصائيات.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.errorDark : AppColors.errorLight),
          )
        else if (nothing)
          Text('لا توجد إجابات بعد.',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary))
        else ...<Widget>[
          AppSurface(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: _ringDiameter,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Container(
                        width: _ringDiameter,
                        height: _ringDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                            width: _ringStroke,
                          ),
                        ),
                      ),
                      SizedBox.square(
                        // Inside the track's stroke, so the arc starts at the
                        // same radius the track is drawn at.
                        dimension: _ringDiameter - 2 * _ringStroke,
                        child: CircularProgressIndicator(
                          value: summary.accuracy,
                          strokeWidth: _ringStroke,
                          color: ink,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                      Text(
                        '${(summary.accuracy * 100).round()}%',
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.headlineSmall
                            ?.merge(AppText.latinDisplay)
                            .copyWith(color: ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(_accuracyLabel, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          // `IntrinsicHeight` because the row *stretches* its children, and a
          // stretched child needs a bounded cross-axis height to stretch
          // *into*. This page's body is a scroll view, so the row's own height
          // is unbounded and without this the layout asserts "BoxConstraints
          // forces an infinite height". `stats_screen.dart` wraps its identical
          // row the same way, for the same reason.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                    child: _StatTile(
                        label: _attemptsLabel, value: '${summary.totalAttempts}')),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                    child: _StatTile(
                        label: _practisedLabel, value: '${summary.wordsPracticed}')),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                    child: _StatTile(
                        label: _masteredLabel, value: '${summary.wordsMastered}')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One number and its label. The number is a Latin run and says so.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = AppColors.accentInk(isDark);
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.titleLarge
                ?.merge(AppText.latinDisplay)
                .copyWith(color: ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}

/// The installed packs, the active one marked and an imported one deletable.
class _PacksSection extends StatelessWidget {
  const _PacksSection({
    required this.packs,
    required this.activePackKey,
    required this.busy,
    required this.onSelected,
    required this.onDeleteRequested,
  });

  final List<PackSummary> packs;
  final String activePackKey;
  final bool busy;
  final ValueChanged<String> onSelected;
  final ValueChanged<PackSummary> onDeleteRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **The heading, and nothing else beside it.**
        //
        // **The active pack used to be named here as well as in its own row,
        // and the user reported it: «حزمة القاموس الشامل معروضة مرتين» — the
        // Comprehensive Dictionary pack is shown twice.** The row is the one
        // that was kept, and the reason is that the row is the *content*: the
        // list of packs is what this section is, every pack in it is named
        // there, and the active one is marked with a tick and the words
        // «الحزمة الحالية». A section whose list named nothing would be a
        // list of anonymous rows.
        //
        // The pill was the decoration, and it repeated the list's own first
        // entry. It also carried the pack's name from a *second* read — the
        // screen's own, beside the list's — which is a second source of the
        // same fact, and the screen no longer takes that name at all: the
        // `packTitle` parameter is gone, so there is nothing for it to drift
        // from.
        Text(_packsHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.s),
        if (packs.isEmpty)
          // Not a spinner and not a zero. "No packs yet" and "reading the packs"
          // are different facts, and neither is an empty card.
          Text(_nothingHere, style: theme.textTheme.bodySmall?.copyWith(color: secondary))
        else
          for (final pack in packs) ...<Widget>[
            _PackRow(
              pack: pack,
              isActive: pack.packKey == activePackKey,
              busy: busy,
              onSelected: onSelected,
              onDeleteRequested: onDeleteRequested,
            ),
            const SizedBox(height: AppSpacing.s),
          ],
      ],
    );
  }
}

/// One pack: its name, its size, its language pair, its key, and whether it is
/// the one the app is working on.
class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.pack,
    required this.isActive,
    required this.busy,
    required this.onSelected,
    required this.onDeleteRequested,
  });

  final PackSummary pack;
  final bool isActive;
  final bool busy;
  final ValueChanged<String> onSelected;
  final ValueChanged<PackSummary> onDeleteRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = AppColors.accentInk(isDark);
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final radius = BorderRadius.circular(AppRadii.md);

    return Semantics(
      // A row is a button, and a screen reader has to be told so: `InkWell`
      // alone exposes a tap but not the role, and the whole card is one target.
      container: true,
      button: true,
      selected: isActive,
      label: pack.title,
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: () => onSelected(pack.packKey),
                borderRadius: radius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      pack.title,
                      // A pack's name is free text from a file the user chose, so
                      // its direction is a fact about the file rather than
                      // something this screen can assume. Latin — which is every
                      // pack in this app — names Inter explicitly rather than
                      // inheriting Tajawal's own Latin; Arabic keeps the
                      // ambient family and the app's direction.
                      textDirection:
                          _writesArabic(pack.title) ? null : TextDirection.ltr,
                      style: _writesArabic(pack.title)
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleMedium?.merge(AppText.latin),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${pack.entryCount} $_wordUnit',
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: secondary),
                    ),
                    Text(
                      // A Latin run: two language codes and an arrow, which an
                      // RTL paragraph would reorder.
                      '${pack.sourceLanguage} → ${pack.targetLanguage}',
                      textDirection: TextDirection.ltr,
                      style: AppText.latin
                          .copyWith(fontSize: AppText.caption, color: secondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Which pack is active. A check plus the words, not the key:
                    // the key is already named once, in the pill above, and a
                    // second copy of it on every row would make "how many packs
                    // are installed" unanswerable by eye.
                    if (isActive)
                      Row(
                        children: <Widget>[
                          Icon(Icons.check_circle, size: 14, color: ink),
                          const SizedBox(width: AppSpacing.xs),
                          Text(_activePack,
                              style:
                                  theme.textTheme.bodySmall?.copyWith(color: ink)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            // A bundled pack cannot be deleted: the app seeds it on first launch
            // and re-seeds it on the next start, so a control here would promise
            // a change the next launch silently undoes. The chip says so in
            // words instead of leaving the user to wonder.
            //
            // **And the derived "My Favourites" pack cannot be deleted either,
            // for a different reason** — it has no rows on the device at all;
            // it is computed from the words the user has saved. So it gets its
            // own chip, and the chip says where its words come from rather
            // than calling it "bundled": the two integrated packs are the ones
            // the user called «المدمجتين», and this one is «حزمة جديدة يتم
            // ملؤها و تفريغها من قبل المستخدم». The key is checked rather
            // than a flag, because the flag means "re-seeded on the next
            // launch" and that is not what is true of this one.
            //
            // **The user's own dictionary is hidden by key as well, and for
            // the opposite reason to the bundled pack.** Its row is
            // `isBundled: false` because it is the user's data and a backup
            // must carry it — so `isBundled` cannot be what decides. It still
            // must not be deletable from here: its words are the user's own,
            // and the way to empty it is to delete the words themselves, one
            // confirmed deletion at a time. A pack-level delete would throw
            // away a whole vocabulary in one tap.
            if (pack.packKey == myFavouritesPackKey)
              const _FavouritesChip()
            else if (pack.packKey == customDictionaryPackKey)
              const _CustomChip()
            else if (pack.isBundled)
              const _BundledChip()
            else
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: _deleteTooltip,
                onPressed: busy ? null : () => onDeleteRequested(pack),
              ),
          ],
        ),
      ),
    );
  }
}

/// Whether [value] carries an Arabic letter.
///
/// U+0600–U+06FF covers the Arabic block, including the marks a pasted name may
/// carry; U+0750–U+077F and U+08A0–U+08FF (Arabic Supplement and Extended-A) are
/// included so a name in either cannot be mis-read as a Latin one and refaced.
bool _writesArabic(String value) => value.runes.any(
      (rune) => (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF),
    );

class _BundledChip extends StatelessWidget {
  const _BundledChip();

  @override
  Widget build(BuildContext context) => Chip(
        label: const Text(_bundledChip),
        // `elevation: 0` here, and **a `Chip` is not one of the
        // families Material elevates** — `chip.dart:1350-1352` resolves
        // `widget.elevation ?? chipTheme.elevation ?? chipDefaults.elevation ??
        // 0`, so the last fallback is already zero. This line therefore pins an
        // existing value rather than fixing the 2,363-black-pixel defect the
        // amber `ElevatedButton` carried; it is kept because `app_theme.dart` now
        // pins the same value for every chip app-wide and a reader of *this* file
        // should not have to leave it to find that out.
        elevation: 0,
        visualDensity: VisualDensity.compact,
      );
}

/// The chip on the derived "My Favourites" pack's row.
///
/// **Its own chip, and not the «مدمجة» one.** The bundled chip says "this pack
/// is re-seeded on the next launch, so you cannot delete it". The derived pack
/// cannot be deleted for a different reason — it is not on the device at all,
/// it is computed from the words the user has saved — and calling it
/// "bundled" would say it is a third dataset shipped with the app, which is
/// the opposite of what it is. The words in it are the user's own curation.
///
/// `elevation: 0` for the same reason as `_BundledChip`, and the theme pins it
/// app-wide anyway.
class _FavouritesChip extends StatelessWidget {
  const _FavouritesChip();

  @override
  Widget build(BuildContext context) => Chip(
        label: const Text(myFavouritesPackChip),
        elevation: 0,
        visualDensity: VisualDensity.compact,
      );
}

/// The chip on the user's own dictionary's row.
///
/// **Its own chip, and not «مدمجة».** The pack does not ship with the app; it
/// is written by the user, stored like any imported pack, and carried in the
/// backup. Calling it bundled would say it is a dataset the app installs, which
/// is the opposite of what it is. «كلماتك» says whose words they are, and —
/// together with the missing delete control — says how to empty it: delete the
/// words themselves.
///
/// `elevation: 0` for the same reason as [_BundledChip], and the theme pins it
/// app-wide anyway.
class _CustomChip extends StatelessWidget {
  const _CustomChip();

  @override
  Widget build(BuildContext context) => Chip(
        label: const Text(customDictionaryChip),
        elevation: 0,
        visualDensity: VisualDensity.compact,
      );
}

/// Import a pack, export a backup, restore a backup — and say what happened.
class _BackupSection extends StatelessWidget {
  const _BackupSection({
    required this.busy,
    required this.message,
    required this.error,
    required this.notice,
    required this.onImport,
    required this.onExport,
    required this.onRestore,
  });

  final bool busy;
  final String? message;
  final Object? error;
  final String? notice;
  final Future<void> Function() onImport;
  final Future<String?> Function() onExport;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(_backupHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.s),
        // A line, not a spinner, and the same one the statistics section uses
        // while it reads. `CircularProgressIndicator` schedules frames forever, so
        // `pumpAndSettle` would never return while one was on screen.
        if (busy)
          Text(_busy, style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
        if (busy) const SizedBox(height: AppSpacing.s),
        // `elevation: 0` on both: Material's M3 default of 1 reintroduces the
        // black keyline that `AppSurface` exists to avoid, and neither the
        // theme's `cardTheme` nor `elevatedButtonTheme` covers these two.
        FilledButton.icon(
          onPressed: busy ? null : onImport,
          icon: const Icon(Icons.file_upload_outlined),
          label: const Text(_importPack),
          style: FilledButton.styleFrom(
            elevation: 0,
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        OutlinedButton.icon(
          onPressed: busy ? null : onExport,
          icon: const Icon(Icons.ios_share),
          label: const Text(_exportBackup),
          style: OutlinedButton.styleFrom(
            elevation: 0,
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        OutlinedButton.icon(
          onPressed: busy ? null : onRestore,
          icon: const Icon(Icons.settings_backup_restore),
          label: const Text(_restoreBackup),
          style: OutlinedButton.styleFrom(
            elevation: 0,
            shape: const StadiumBorder(),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s),
            child: Text(
              '$error',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: isDark ? AppColors.errorDark : AppColors.errorLight),
            ),
          ),
        // Two lines, kept apart: one says what failed and one says what worked,
        // and collapsing them would mean a success could hide a failure that
        // came before it.
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(message!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.successDark
                        : AppColors.successLight)),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(notice!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// The one destructive action on this page: clear the active pack's progress.
///
/// Full width and in the error colour, shaped as the artwork's actions are.
/// `stats_screen.dart` draws its own reset as the same pill in the same place on
/// its own screen; there is deliberately only one of them here.
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        elevation: 0,
        foregroundColor: error,
        side: BorderSide(color: error),
        shape: const StadiumBorder(),
      ),
      child: const Text('مسح التقدم'),
    );
  }
}

/// The two-step confirmation.
///
/// **It is part of this screen's tree, not a route.** A `showDialog` pushes onto
/// the navigator, which sits *above* this screen, so a dialog's widgets are not
/// inside it — and the tests here find the layer's title scoped to this screen.
/// A `Stack` over the body keeps the two in one tree, and the body is still there
/// underneath the barrier, which is the point of asking first.
///
/// **Back cancels the confirmation and does not leave the screen.** The
/// `PopScope` in `_MoreScreenState.build` blocks the pop and turns it into this
/// layer's cancel. What the barrier blocks is a *tap* —
/// `ModalBarrier(dismissible: false)` takes the taps and sends them nowhere.
class _ConfirmLayer extends StatelessWidget {
  const _ConfirmLayer({
    required this.confirmation,
    required this.onCancel,
    required this.onConfirm,
  });

  final _Confirmation confirmation;
  final VoidCallback onCancel;
  final Future<void> Function(_Confirmation) onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;
    final onError = isDark ? AppColors.backgroundDark : AppColors.surfaceLight;

    return Stack(
      children: <Widget>[
        const ModalBarrier(dismissible: false),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: AppSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(confirmation.title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.s),
                  Text(confirmation.body, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.l),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton(
                          onPressed: onCancel,
                          child: const Text(_cancel),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onConfirm(confirmation),
                          style: FilledButton.styleFrom(
                            elevation: 0,
                            backgroundColor: error,
                            foregroundColor: onError,
                            // Matches the pill the user just pressed, so the
                            // confirmation reads as the same action.
                            shape: const StadiumBorder(),
                          ),
                          child: Text(confirmation.confirmLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}