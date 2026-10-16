import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/quiz_session_result.dart';
import 'package:lexilearn/domain/stats_summary.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

import 'stats_controller.dart';

/// The chrome, in Arabic — the app is RTL end to end and the artwork's chrome
/// is Arabic. Every number on this screen is a Latin run and says so: the value
/// widgets below all carry `textDirection: TextDirection.ltr` and `AppText.latin`,
/// because an RTL paragraph reorders a run of digits and slashes.
const String _title = 'إحصائياتك';
const String _loading = 'جارٍ التحميل…';
const String _emptyHeadline = 'لا توجد إجابات بعد';
const String _emptySupporting = 'أجب عن بعض الأسئلة وستظهر إحصائياتك هنا.';
const String _loadFailed = 'تعذّر تحميل الإحصائيات.';
const String _retry = 'إعادة المحاولة';
const String _accuracyLabel = 'نسبة الدقة';
const String _attemptsLabel = 'إجمالي الإجابات';
const String _practisedLabel = 'كلمات تدربت عليها';
const String _masteredLabel = 'كلمات أتقنتها';
const String _recentHeading = 'آخر الجلسات';
const String _noSessions = 'لا توجد جلسات بعد.';
const String _reset = 'مسح التقدم';
const String _resetTitle = 'مسح التقدم؟';
const String _resetBody =
    'سيؤدي هذا إلى حذف كل إجاباتك وسجل جلساتك في هذه الحزمة، ولا يمكن التراجع.';
const String _cancel = 'إلغاء';
const String _resetFailed = 'تعذّر مسح التقدم. لم يتغيّر شيء.';

/// The accuracy ring's outer diameter.
///
/// A fixed size rather than a token because it is a shape, not a gap: no entry
/// in `AppSpacing` describes a 128 px circle. Named here for the same reason
/// `quiz_setup_screen.dart` names `_pickerHeight` — so the one number that
/// describes this shape is stated once and read from, not re-typed per call.
const double _ringDiameter = 128;

/// A session row's verdict ring, against the height of that row's text.
const double _badgeDiameter = 40;

/// The weight of every ring this screen draws: the accuracy track and the three
/// session-score badges.
///
/// 2 px, not 1: these are the screen's only use of colour-as-verdict, and at
/// 1 px they stop reading as an edge on a low-density screen. The colour itself
/// is the constraint that matters more — `#16A34A` on white is 3.3:1, which is
/// over the 3:1 a border or an icon needs and under the 4.5:1 body text needs, so
/// these are rings and icons and never a coloured word. See `_ScoreBadge`.
const double _ringStroke = 2;

/// Statistics for one pack: accuracy, volume, mastery, and the session history.
///
/// **Statistics is a Home tile, not a bottom-bar destination.** The artwork's
/// bar draws exactly four items — الرئيسية, البطاقات, الاختبارات, المزيد — in
/// the light phone and again in the dark one, with no statistics item in either;
/// `docs/design/style-direction.md` records the same in its Navigation section
/// and in Amendment 1, and `lib/ui/home_shell.dart` cites both. What the
/// artwork *does* draw is a fourth Home tile carrying the bar-chart glyph, so the
/// statistics screen is a route pushed from that tile. See `_QuickLaunchGrid` in
/// `lib/ui/home/home_screen.dart`, which pushes rather than selecting index 3.
///
/// Stateless, and it reads its controller from the tree when there is one.
/// Two callers exist and they disagree about who owns the read: the app has no
/// `StatsController` provider, so the pushed route has to create, fire and
/// dispose one, while a test that wants to mount a controller that has *not*
/// loaded yet — or one whose read it has already failed — needs to hand the same
/// instance in. `context.read<StatsController?>()` returns null when nothing is
/// there, so both paths run [_StatsBody] and cannot drift apart.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.packKey});

  /// The pack every number on this screen belongs to. Fixed at construction and
  /// never re-read: `StatsController` holds the same key, and every query behind
  /// it filters on `pack_key`.
  final String packKey;

  @override
  Widget build(BuildContext context) {
    // Nullable read rather than a `try`/`catch` around a non-null one: provider
    // resolves an absent `StatsController?` to null and a present one to the
    // instance, so "is there one" is a null check and not a control-flow trick.
    final injected = context.read<StatsController?>();
    if (injected != null) return _StatsBody(controller: injected);
    return _StatsOwner(packKey: packKey);
  }
}

/// Owns the controller for the app's path, where nothing else provides one.
///
/// Split out from [StatsScreen] rather than inlined so that the screen can stay
/// a `StatelessWidget` — the signature the rest of the app is written against —
/// while the lifecycle still has somewhere to live.
class _StatsOwner extends StatefulWidget {
  const _StatsOwner({required this.packKey});

  final String packKey;

  @override
  State<_StatsOwner> createState() => _StatsOwnerState();
}

class _StatsOwnerState extends State<_StatsOwner> {
  late StatsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _create();
  }

  /// Fired from `initState`, not from a post-frame callback.
  ///
  /// The read is genuinely in flight while the first frame is being built, which
  /// is why [StatsController] guards every notification with `_notifyIfAlive`:
  /// a fast Back tears this route down while the query is still out, and
  /// `ChangeNotifier` asserts on `notifyListeners()` after `dispose()` rather
  /// than ignoring it.
  StatsController _create() => StatsController(
        repository: context.read<VocabRepository>(),
        packKey: widget.packKey,
      )..load();

  @override
  void didUpdateWidget(_StatsOwner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packKey == widget.packKey) return;
    // A pack switch is a new controller, not a re-read: the key is held on the
    // controller on purpose so that no call site can forget to pass it, and that
    // is only true while the instance matches the pack on screen.
    final previous = _controller;
    _controller = _create();
    previous.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StatsBody(controller: _controller);
}

/// The screen, rebuilt whenever the controller notifies.
class _StatsBody extends StatefulWidget {
  const _StatsBody({required this.controller});

  final StatsController controller;

  @override
  State<_StatsBody> createState() => _StatsBodyState();
}

class _StatsBodyState extends State<_StatsBody> {
  /// Whether the confirmation is open. Local, because it is a fact about this
  /// route and nothing else reads it.
  bool _confirming = false;

  StatsController get _controller => widget.controller;

  /// Closes the confirmation without resetting.
  ///
  /// Named so the `إلغاء` button and the `PopScope` callback are literally the
  /// same behaviour rather than two expressions that happen to agree.
  void _cancel() => setState(() => _confirming = false);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text(_title),
          // The header sits on the background rather than on a raised surface,
          // matching the artwork's word-card header. The AppBar's own default
          // would be `surfaceContainer`, which would draw a second tone across
          // the top of a screen whose only surfaces are the cards below it.
          backgroundColor:
              isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Stack(
            // `Positioned.fill` rather than a bare child: the content needs a
            // *tight* width so the full-width reset pill measures exactly
            // `screenWidth - 2 * AppSpacing.m` instead of stretching to the
            // screen under a Stack's loose constraints.
            children: <Widget>[
              Positioned.fill(child: _content()),
              if (_confirming)
                Positioned.fill(
                  // Back is *cancelled*, not blocked and not allowed through.
                  // Measured before this wrapper existed: with the confirm layer
                  // open, `tester.binding.handlePopRoute()` returned `true`, the
                  // `StatsScreen` count went to 0 and the host route came back —
                  // so Android's back silently left the screen mid-confirmation.
                  // A user who presses back expecting to dismiss a modal
                  // expects the modal to go, and on this screen nothing is lost
                  // either way (the reset has not been invoked), but the screen
                  // vanishing under an open destructive confirmation is not a
                  // state to design for.
                  //
                  // `canPop: false` keeps the route; the callback turns the
                  // blocked pop into a cancel, so back and `إلغاء` do the same
                  // thing. Pinned by *the system back cancels the confirmation
                  // rather than leaving the screen* in
                  // `test/ui/stats_screen_test.dart`.
                  child: PopScope<void>(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) {
                      // `didPop` is always false while `canPop` is false; the
                      // guard is here so a future `canPop` cannot turn a
                      // cancellation into a navigation.
                      if (didPop) return;
                      setState(() => _confirming = false);
                    },
                    child: _ConfirmLayer(
                      onCancel: _cancel,
                      onConfirm: _reset,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final controller = _controller;

    // Loading first. A fresh controller and a controller that has just reset
    // both read `isLoading` with an empty summary, and the line is the honest
    // thing to show for both.
    if (controller.isLoading) {
      return const _Notice(message: _loading, emphasised: false);
    }

    // A failure is the full-screen state only when there is nothing real behind
    // it. `StatsController` blanks the summary when a *read* fails, so
    // `error != null && summary.isEmpty` is that case exactly; a *reset* that
    // fails leaves the last real read standing, and blanking the screen in
    // response to a reset that did nothing would be the opposite of honest.
    if (controller.error != null && controller.summary.isEmpty) {
      return _Notice(
        message: _loadFailed,
        emphasised: true,
        actionLabel: _retry,
        onAction: controller.load,
      );
    }

    final summary = controller.summary;
    // "Nothing to show" is neither a number being zero nor a list being empty —
    // it is there being nothing at all. A pack with sessions but no recorded
    // word answers has a history worth reading and tiles that would be lies.
    if (summary.totalAttempts == 0 && summary.recentSessions.isEmpty) {
      return const _EmptyState();
    }

    return _Dashboard(
      summary: summary,
      // A reset that failed sits beside the data it failed to clear, rather than
      // replacing it. The message is here and not in the full-screen state
      // because the full-screen state means "the read failed", which is not
      // what happened.
      errorMessage: controller.error == null ? null : _resetFailed,
      onRequestReset: () => setState(() => _confirming = true),
    );
  }

  Future<void> _reset() async {
    setState(() => _confirming = false);
    await _controller.reset();
  }
}

/// Four stat cards, the session history, and the destructive action.
class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.summary,
    required this.onRequestReset,
    this.errorMessage,
  });

  final StatsSummary summary;
  final VoidCallback onRequestReset;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    // Each of the two sections is gated on its own data, and they are not the
    // same condition. A pack with answers and no sessions shows the tiles and a
    // "no sessions yet" card; a pack with sessions and no recorded answers shows
    // only the history. A pack with neither is [_EmptyState] and reaches
    // neither. What is never drawn is a tile reading 0, or 0%, next to a
    // history that is plainly not empty.
    final hasAnswers = summary.totalAttempts > 0;
    final hasSessions = summary.recentSessions.isNotEmpty;
    final hasAnything = hasAnswers || hasSessions;

    return SingleChildScrollView(
      // A scroll view rather than a `ListView` because the session test asserts
      // the *vertical order* of two rows by their laid-out positions, and a
      // `ListView` does not build the rows it has scrolled past — it would drop
      // the second one out of the tree rather than place it below the first.
      // `SingleChildScrollView` lays out every child and only clips.
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (errorMessage != null) ...<Widget>[
            _InlineError(message: errorMessage!),
            const SizedBox(height: AppSpacing.m),
          ],
          if (hasAnswers) ...<Widget>[
            _AccuracyCard(summary: summary),
            const SizedBox(height: AppSpacing.m),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      label: _attemptsLabel,
                      value: '${summary.totalAttempts}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: _StatTile(
                      label: _practisedLabel,
                      value: '${summary.wordsPracticed}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: _StatTile(
                      label: _masteredLabel,
                      value: '${summary.wordsMastered}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.m),
          ],
          if (hasAnything) ...<Widget>[
            _SessionsCard(sessions: summary.recentSessions),
            const SizedBox(height: AppSpacing.l),
            _ResetButton(onPressed: onRequestReset),
          ],
        ],
      ),
    );
  }
}

/// Accuracy as a ring, because a percentage is a proportion and a proportion
/// reads as a dial rather than as a number in a box.
///
/// The track is a hairline-bordered `Container` and the arc is a **determinate**
/// `CircularProgressIndicator` over it. Deterministic on purpose: the
/// indeterminate one schedules frames forever, so `pumpAndSettle` never returns
/// while one is on screen, which is the trap `quiz_screen.dart`'s
/// `_LoadingScreen` records. This one has a value, so it paints once and stops.
class _AccuracyCard extends StatelessWidget {
  const _AccuracyCard({required this.summary});

  final StatsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Brand ink, never `AppColors.accent`: `design_tokens.dart` permits the
    // amber for icons and fills only, because its contrast against a near-white
    // background is too low for a number a user is meant to read.
    final ink = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final track = isDark ? AppColors.borderDark : AppColors.borderLight;

    return AppSurface(
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
                    border: Border.all(color: track, width: _ringStroke),
                  ),
                ),
                SizedBox.square(
                  // Inside the track's stroke, so the arc starts at the same
                  // radius the track is drawn at instead of overlapping it.
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
                  style: theme.textTheme.headlineMedium
                      ?.merge(AppText.latinDisplay)
                      .copyWith(color: ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              _accuracyLabel,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
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
    final ink = isDark ? AppColors.primaryDark : AppColors.primaryLight;
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

/// The history, in one card. The heading and the rows share it, so the heading
/// has exactly one `AppSurface` above it.
class _SessionsCard extends StatelessWidget {
  const _SessionsCard({required this.sessions});

  final List<QuizSessionResult> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(_recentHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s),
          if (sessions.isEmpty)
            Text(
              _noSessions,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            )
          else
            for (var i = 0; i < sessions.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.s),
              _SessionRow(session: sessions[i]),
            ],
        ],
      ),
    );
  }
}

/// One finished session: its score, ringed, and when it was played.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final QuizSessionResult session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Row(
      children: <Widget>[
        _ScoreBadge(session: session),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Both runs are Latin, and both would be reordered by the app's
              // RTL direction if left to inherit it.
              Text(
                '${session.correctCount} / ${session.totalQuestions}',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleMedium
                    ?.merge(AppText.latinDisplay)
                    .copyWith(color: ink),
              ),
              Text(
                _formatWhen(session.startedAt),
                textDirection: TextDirection.ltr,
                style:
                    AppText.latin.copyWith(fontSize: AppText.caption, color: secondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `yyyy-MM-dd HH:mm`, in local time.
  ///
  /// Built here and not read from the screen's own formatter by the test, so a
  /// test that reused the implementation would agree with it whatever it
  /// formatted.
  static String _formatWhen(DateTime when) {
    final local = when.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// A session's verdict, as a ring around a glyph.
///
/// Three cases and no more: a perfect session, a scoreless one, and everything
/// between. The middle case wears the brand hairline rather than a third colour,
/// because a "good enough" threshold would be a rule with nothing behind it —
/// there is no evidence in the artwork or the data model for where 3-of-4
/// should fall.
///
/// A session with no questions at all is the hairline too: there is no verdict
/// to give, and dividing by it to find one is what `QuizSessionResult.accuracy`
/// already refuses to do.
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.session});

  final QuizSessionResult session;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final success = isDark ? AppColors.successDark : AppColors.successLight;
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;
    final neutral = isDark ? AppColors.borderDark : AppColors.borderLight;

    final bool perfect = session.totalQuestions > 0 &&
        session.correctCount == session.totalQuestions;
    final bool scoreless = session.totalQuestions > 0 && session.correctCount == 0;

    final Color colour = perfect
        ? success
        : scoreless
            ? error
            : neutral;
    final IconData glyph = perfect
        ? Icons.check_rounded
        : scoreless
            ? Icons.close_rounded
            : Icons.remove_rounded;

    return Container(
      width: _badgeDiameter,
      height: _badgeDiameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // `BoxShape.circle` and not a radius: this is the one decoration on the
        // screen that is a ring rather than a card, and the tests find it by
        // exactly that — a bordered `Container` with a circular shape.
        shape: BoxShape.circle,
        border: Border.all(color: colour, width: _ringStroke),
      ),
      child: Icon(glyph, size: _badgeDiameter / 2, color: colour),
    );
  }
}

/// A full-width destructive action, in the error colour, shaped as the
/// artwork's actions are.
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
        foregroundColor: error,
        side: BorderSide(color: error),
        shape: const StadiumBorder(),
      ),
      child: const Text(_reset),
    );
  }
}

/// The two-step confirmation.
///
/// **It is part of this screen's tree, not a route.** A `showDialog` pushes onto
/// the navigator, and the navigator sits *above* this screen, so a dialog's
/// widgets are not inside it — and `stats_screen_test.dart` finds the dialog's
/// title with `inStats`, which is scoped to this screen's subtree. Measured: a
/// probe that pushed an `AlertDialog` from a host widget found its title with a
/// bare `find.text` (1 match) and with `find.descendant(of: find.byType(Host),
/// matching: find.text(title))` (**0 matches**). A `Stack` over the body keeps
/// the two in one tree, and the body is still there underneath the barrier,
/// which is the point of asking first.
///
/// **Back cancels the confirmation and does not leave the screen.** The
/// `PopScope` in [_StatsBodyState.build] blocks the pop and turns it into this
/// layer's cancel, so Android's back button behaves the way it behaves on any
/// modal. What the barrier blocks is a *tap* — `ModalBarrier(dismissible: false)`
/// takes the taps and sends them nowhere.
///
/// The three ways out are the two buttons and back; what none of them does is
/// reset, because `onConfirm` is the only path to `StatsController.reset()`. The
/// button behaviour is pinned by *asks first, and cancelling changes nothing*
/// and this one's back behaviour by *the system back cancels the confirmation
/// rather than leaving the screen*.
class _ConfirmLayer extends StatelessWidget {
  const _ConfirmLayer({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

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
                  Text(_resetTitle, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.s),
                  Text(_resetBody, style: theme.textTheme.bodyMedium),
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
                          onPressed: onConfirm,
                          style: FilledButton.styleFrom(
                            backgroundColor: error,
                            foregroundColor: onError,
                            // Matches the pill the user just pressed, so the
                            // confirmation reads as the same action.
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(_reset),
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

/// A centred line, with an optional action under it. Never a spinner: see the
/// note on [_AccuracyCard] about `pumpAndSettle`.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.emphasised,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool emphasised;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: emphasised
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.bodyLarge?.copyWith(color: secondary),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.m),
              OutlinedButton(
                onPressed: onAction,
                // `shape` is not a constructor parameter on Flutter 3.44's
                // `OutlinedButton`; it reaches the style through `styleFrom`.
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A fresh install, in words.
///
/// A row of four zeros and a 0% would be indistinguishable from "you answered
/// everything wrong", which is not what happened, so the tiles are not drawn
/// here at all.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _emptyHeadline,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              _emptySupporting,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A failure that did not blank the screen: the data is still there, and this
/// says the action failed rather than the read.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;

    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: error, size: 20),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
