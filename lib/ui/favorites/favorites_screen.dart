import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';

/// The chrome, in Arabic — the app is RTL end to end and the artwork's chrome is
/// Arabic.
const String _title = 'المفضلة';
const String _loading = 'جارٍ التحميل…';
const String _emptyHeadline = 'لا توجد كلمات مفضلة';
const String _emptySupporting = 'اضغط القلب في تفاصيل الكلمة لحفظها هنا.';
const String _loadFailed = 'تعذّر تحميل المفضلة.';
const String _retry = 'إعادة المحاولة';
const String _removeTitle = 'إزالة من المفضلة؟';
const String _remove = 'إزالة';
const String _cancel = 'إلغاء';

/// The saved words of one pack.
///
/// **Not a bottom-bar destination, and nothing was cut.** The artwork's bar draws
/// exactly four items — الرئيسية, البطاقات, الاختبارات, المزيد — in the light
/// phone and again in the dark one, with no heart in either. So this screen is
/// pushed as a route from the `المفضلة` tile in Home's 2×2 quick-launch grid, and
/// `lib/ui/home_shell.dart` carries the comment saying so. `test/ui/
/// favorites_screen_test.dart` pins the tile reaching it *and* that the bar's
/// selected index stays on `الرئيسية` underneath.
///
/// Its constructor is unchanged from the placeholder Task 9 shipped, byte for
/// byte, so `home_screen.dart`'s call site did not have to move; only the class
/// type did, `StatelessWidget` → `StatefulWidget`, because this screen owns a
/// list and a confirmation.
///
/// **The repository comes from `provider`, like every other screen.** The
/// constructor cannot take it — the signature is fixed by the call site above —
/// and `HomeShell`'s is exactly the same trade `StatsScreen` and `MoreScreen`
/// make.
///
/// The order is the pack's own `sort_index`, not the order things were saved in.
/// `VocabRepository.favorites` walks the pack's entries and tests membership, so
/// the favourites list reads the same way the search results and the flashcards
/// deck do. See `FavoriteDao.favoritesIn` for why the DAO hands back a `Set`.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.packKey,
    required this.onOpenWord,
  });

  final String packKey;
  final ValueChanged<VocabEntry> onOpenWord;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<VocabEntry> _entries = const <VocabEntry>[];

  /// True until the first read answers. A spinner would be the obvious choice and
  /// it is the one thing this screen must not draw: an indeterminate
  /// `CircularProgressIndicator` schedules frames forever, so `pumpAndSettle`
  /// never returns while one is on screen. `stats_screen.dart` and `more_screen
  /// .dart` both record this decision for the same reason.
  bool _isLoading = true;

  /// Whether the last read failed. Kept apart from [_entries] so a failure after a
  /// good read does not blank a list that is still on screen — and, the other way
  /// round, so a failure *with* nothing behind it reads as a failure rather than
  /// as a fresh install.
  ///
  /// A `bool` and not an `Object?` carrying the exception: nothing on this screen
  /// renders the exception, and a sentinel string parked in a field typed as one
  /// is a value a future reader has to work out. `stats_screen.dart` holds a
  /// `String? error` because it also shows the message; this screen shows the
  /// sentence [_loadFailed] either way.
  bool _failed = false;

  /// The word whose un-favourite confirmation is open, or null when none is.
  ///
  /// One field rather than a `bool`: "which destructive action is pending" is one
  /// answer, and a screen that could represent a confirmation with no subject is a
  /// screen that can render a dialog about nothing. The same shape
  /// `more_screen.dart` uses.
  VocabEntry? _removing;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packKey == widget.packKey) return;
    // A pack switch is a fresh read, and the confirmation belongs to the pack it
    // was opened against — carrying it across would ask about a word the new
    // pack may not even have.
    _removing = null;
    _isLoading = true;
    unawaited(_load());
  }

  /// Reads the pack's favourites.
  ///
  /// Fires from `initState`, not from a post-frame callback: the read is
  /// genuinely in flight while the first frame is built.
  Future<void> _load() async {
    final packKey = widget.packKey;
    try {
      final entries = await context.read<VocabRepository>().favorites(packKey);
      // A back that beat the read, or a pack switch this read no longer answers.
      if (!mounted || packKey != widget.packKey) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || packKey != widget.packKey) return;
      setState(() {
        _isLoading = false;
        _failed = true;
      });
    }
  }

  /// Closes the confirmation without removing anything.
  ///
  /// Named so the three ways out are one behaviour rather than three expressions
  /// that happen to agree: the `إلغاء` button, the `PopScope` callback Android's
  /// back reaches, and the close at the top of [_remove].
  void _cancel() => setState(() => _removing = null);

  /// Closes the confirmation and then removes what it asked about.
  ///
  /// The layer is dismissed **first** so the screen does not sit showing a dialog
  /// it is already acting on — the same ordering `stats_screen.dart` records.
  ///
  /// And then the list is **read again**, not patched. A row removed from the
  /// local list would leave the screen claiming a state the database had never
  /// been asked about, and the next re-read — a pack switch, a retry, a pull to
  /// refresh that does not exist here — would bring the word back with no
  /// explanation. This is the write, then the read; two sequential round trips,
  /// which is why the test that drives it waits three turns rather than one.
  Future<void> _remove() async {
    final entry = _removing;
    if (entry == null) return;
    _cancel();
    try {
      await context.read<VocabRepository>().setFavorite(
            packKey: widget.packKey,
            entryId: entry.id,
            isFavorite: false,
          );
    } catch (_) {
      // The list is left standing and the failure is not invented onto a screen
      // whose chrome the artwork specifies down to the words. The word staying on
      // screen is the honest report: it is still a favourite.
      if (mounted) await _load();
      return;
    }
    // **Measured load-bearing.** Deleting this line — the reload that follows the
    // write — turns three tests red in `test/ui/favorites_screen_test.dart`:
    // *confirming takes the word off the list and the disk*, *removing the last
    // word falls back to the empty state* and *leaves another pack's favourite
    // alone*. A screen that removed the row locally instead would have passed the
    // two that never press remove.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_title),
        // The header sits on the background rather than on a raised surface,
        // matching the artwork's word-card header and every other screen in the
        // app. The AppBar's own default would be `surfaceContainer`, drawing a
        // second tone across the top of a screen whose only surfaces are the rows.
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Stack(
          // `Positioned.fill` rather than a bare child, so the confirmation layer
          // can cover the list and so its own `Positioned.fill` has a bounded box
          // to fill. The same two reasons `stats_screen.dart` stacks its own body
          // this way.
          children: <Widget>[
            Positioned.fill(child: _content()),
            if (_removing != null)
              Positioned.fill(
                // Back *cancels* the confirmation and does not leave the screen.
                // `canPop: false` keeps the route; the callback turns the blocked
                // pop into a cancel, so back and `إلغاء` do the same thing.
                //
                // `maybePop` returns `true` for a *deliberately blocked* pop as
                // well as for a real one — it means "handled", and being blocked
                // on purpose counts. So what pins this is the screen still being
                // in the tree afterwards, not the value.
                child: PopScope<void>(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    // `didPop` is always false while `canPop` is false; the guard
                    // is here so a future `canPop` cannot turn a cancellation into
                    // a navigation.
                    if (didPop) return;
                    _cancel();
                  },
                  child: _ConfirmLayer(
                    term: _removing!.term,
                    onCancel: _cancel,
                    onConfirm: _remove,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_isLoading) return const _Notice(message: _loading, emphasised: false);

    if (_failed && _entries.isEmpty) {
      return _Notice(
        message: _loadFailed,
        emphasised: true,
        actionLabel: _retry,
        onAction: () {
          setState(() {
            _isLoading = true;
            _failed = false;
          });
          unawaited(_load());
        },
      );
    }

    // "Nothing to show" is not a count of zero. A fresh install and a pack with
    // nothing saved draw the same words, so there is no number here to be wrong
    // about — there is simply nothing.
    if (_entries.isEmpty) return const _EmptyState();

    // A failure that did not blank the list sits beside the data it did not
    // blank, rather than replacing it.
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.m),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s),
      itemBuilder: (context, index) => _FavoritesRow(
        entry: _entries[index],
        onOpen: widget.onOpenWord,
        onRequestRemove: (entry) => setState(() => _removing = entry),
      ),
    );
  }
}

/// One saved word: its term, its meanings, and the control that unsaves it.
///
/// **Two controls in one card, and they are not the same control.** Tapping the
/// word opens it; tapping the heart asks whether to remove it. A heart that also
/// opened the word would make "read this" and "delete this" one gesture, and
/// pinned by *the heart does not open the word*.
class _FavoritesRow extends StatelessWidget {
  const _FavoritesRow({
    required this.entry,
    required this.onOpen,
    required this.onRequestRemove,
  });

  final VocabEntry entry;
  final ValueChanged<VocabEntry> onOpen;
  final ValueChanged<VocabEntry> onRequestRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: () => onOpen(entry),
              // The card's own radius, so the ink follows the surface rather than
              // the row inside it.
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // An English term in an Arabic app must not be reordered by
                    // the app's direction, and must not render in Tajawal's own
                    // Latin — so it names Inter and LTR explicitly, as
                    // `home_screen.dart`'s `_EntryRow` does.
                    Text(
                      entry.term,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.merge(AppText.latin),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // **A meaning is content, not a caption.** The first
                    // translation is what the word means and it is drawn in the
                    // primary ink at `bodyLarge`; further translations are
                    // alternate readings of the same word, so they step down to
                    // the secondary ink. Reading a saved word's *meaning* as
                    // secondary text was a design decision nobody made — it came
                    // from copying the list row's styling wholesale. Caught by
                    // eye, on the dark reference image.
                    for (var i = 0; i < entry.translations.length; i++)
                      Text(
                        entry.translations[i],
                        textDirection: TextDirection.rtl,
                        style: i == 0
                            ? theme.textTheme.bodyLarge
                            : theme.textTheme.bodyMedium
                                ?.copyWith(color: secondary),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          FavoriteButton(
            // Every word on this screen is a favourite — that is what the screen
            // is — so the heart is always filled and amber, and its tap asks
            // whether to empty it.
            isFavorite: true,
            onPressed: () => onRequestRemove(entry),
          ),
        ],
      ),
    );
  }
}

/// The two-step confirmation.
///
/// **It is part of this screen's tree, not a route.** A `showDialog` pushes onto
/// the navigator, which sits *above* this screen, so a dialog's widgets would not
/// be inside it — and this file's tests find the layer's title scoped to this
/// screen. A `Stack` over the body keeps the two in one tree, and the list is
/// still readable underneath the barrier, which is the point of asking first.
///
/// What the barrier blocks is a *tap*; `ModalBarrier(dismissible: false)` takes
/// them and sends them nowhere. Back does not leave the screen — see the
/// `PopScope` above.
class _ConfirmLayer extends StatelessWidget {
  const _ConfirmLayer({
    required this.term,
    required this.onCancel,
    required this.onConfirm,
  });

  /// The word being asked about, named in the copy. A word's name is English in
  /// every pack this app ships, so it is interpolated into the Arabic sentence
  /// the way `more_screen.dart` interpolates a pack's title into its own.
  final String term;

  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;

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
                  Text(_removeTitle, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'سيؤدي هذا إلى حذف «$term» من كلماتك المفضلة.',
                    style: theme.textTheme.bodyMedium,
                  ),
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
                          onPressed: () => onConfirm(),
                          style: FilledButton.styleFrom(
                            backgroundColor: error,
                            foregroundColor: onError,
                            // Matches the pill the user just pressed, so the
                            // confirmation reads as the same action.
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(_remove),
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
/// note on [_FavoritesScreenState._isLoading].
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

/// A fresh install, or a pack with nothing saved, in words.
///
/// **No card and no AppSurface.** Every other screen's empty state in this app
/// is bare text over the background, and this one says so with nothing on it: a
/// card with nothing in it would be a shape standing in for an answer.
/// Pinned by *an empty favourites list says so in words*, which asserts no
/// `AppSurface` is on screen at all in this state.
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
              style:
                  theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
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