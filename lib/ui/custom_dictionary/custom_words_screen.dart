import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/domain/search_matcher.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';

import 'add_custom_word_screen.dart';

/// The chrome, in Arabic — the app is right to left end to end.
const String _title = 'الكلمات المضافة';
const String _searchHint = 'ابحث في كلماتك...';
const String _backTooltip = 'رجوع';
const String _deleteTooltip = 'حذف الكلمة';
const String _loading = 'جارٍ التحميل…';
const String _loadFailed = 'تعذّر تحميل كلماتك.';
const String _retry = 'إعادة المحاولة';
const String _noMatches = 'لا توجد كلمات تطابق بحثك.';
const String _emptyHeadline = 'لا توجد كلمات في قاموسك بعد.';
const String _emptySupporting = 'أضف كلمتك الأولى لتظهر هنا.';
const String _addWord = 'إضافة كلمة';

/// The delete confirmation.
const String _confirmQuestion = 'هل أنت متأكد من حذف هذه الكلمة';
const String _yes = 'نعم';
const String _no = 'لا';

/// The screen the landing screen's `الكلمات المضافة` card opens.
///
/// **The list is the database's, not a snapshot patched in memory.** Saving a
/// heart and deleting a word both end with [_load], so the count, the rows and
/// the empty state all come from the same read; a row removed locally would let
/// the screen claim a state the database was never asked about.
///
/// **The heart and the bin are two different controls.** The heart toggles
/// [VocabRepository.setFavorite] and does not open or delete anything; the bin
/// asks first and then calls [VocabRepository.deleteCustomWord]. A card whose
/// whole surface opened a detail screen would make the two icons compete with a
/// third gesture, and the brief gives this screen no detail route of its own, so
/// the card itself is not a tap target.
///
/// **The artwork's controls sit on the physical left**, which is the trailing
/// side in this app, so the row is laid out right to left: the term and the
/// meaning at the start, the bin and then the heart at the end.
class CustomWordsScreen extends StatefulWidget {
  const CustomWordsScreen({super.key});

  @override
  State<CustomWordsScreen> createState() => _CustomWordsScreenState();
}

class _CustomWordsScreenState extends State<CustomWordsScreen> {
  final TextEditingController _search = TextEditingController();

  List<VocabEntry> _words = const <VocabEntry>[];

  /// Which of [_words] are saved as favourites.
  ///
  /// A `Set` of ids rather than a field on [VocabEntry]: the entry is the
  /// pack's data and the favourite is the user's, stored in another table. The
  /// read fills this set and the heart reads it.
  Set<String> _favoriteIds = <String>{};

  String _query = '';

  /// True until the first read answers. A spinner is deliberately not drawn:
  /// an indeterminate `CircularProgressIndicator` schedules frames for ever, so
  /// `pumpAndSettle` never returns while one is on screen. `FavoritesScreen`
  /// records the same decision.
  bool _isLoading = true;

  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Reads the words and their favourite marks.
  ///
  /// The two reads are sequential rather than `Future.wait`: the screen needs
  /// both answers before it draws a row, and one extra round trip on an
  /// in-memory database is cheaper than a pair of error paths that would have
  /// to agree about which one failed.
  Future<void> _load() async {
    try {
      final repository = context.read<VocabRepository>();
      final words = await repository.customWords();
      final favorites = await repository.favorites(customDictionaryPackKey);
      if (!mounted) return;
      setState(() {
        _words = words;
        _favoriteIds = <String>{for (final entry in favorites) entry.id};
        _isLoading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _failed = true;
      });
    }
  }

  /// Flips one word's favourite mark and writes the answer.
  ///
  /// The pixels change first so the heart answers the tap at once; a failed
  /// write puts the old value back, because a filled heart the database does
  /// not know about is a lie about what will be there next launch.
  Future<void> _toggleFavorite(VocabEntry entry) async {
    final wasFavorite = _favoriteIds.contains(entry.id);
    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(entry.id);
      } else {
        _favoriteIds.add(entry.id);
      }
    });
    try {
      await context.read<VocabRepository>().setFavorite(
        packKey: customDictionaryPackKey,
        entryId: entry.id,
        isFavorite: !wasFavorite,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(entry.id);
        } else {
          _favoriteIds.remove(entry.id);
        }
      });
    }
  }

  /// Asks, then deletes.
  ///
  /// **Every way out that is not `نعم` is a cancellation**, and none of them
  /// writes: the barrier is dismissible, so an outside tap answers null; the
  /// system back pops the dialog with null; `لا` pops it with false. Only the
  /// explicit `true` reaches [_delete].
  Future<void> _requestDelete(VocabEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteDialog(term: entry.term),
    );
    if (confirmed != true || !mounted) return;
    await _delete(entry);
  }

  /// Deletes the word and re-reads the dictionary.
  ///
  /// The row is not removed from [_words] by hand. The write is followed by
  /// [_load], so a deletion that failed cannot leave the screen showing a word
  /// the database still has — and the count is recomputed from the same read.
  Future<void> _delete(VocabEntry entry) async {
    try {
      await context.read<VocabRepository>().deleteCustomWord(entry.id);
    } catch (_) {
      // The word stays on screen, which is the honest report: it is still
      // there. There is no separate sentence for a failed delete because the
      // artwork specifies the chrome and the repository has no message for it.
      return;
    }
    if (!mounted) return;
    await _load();
  }

  /// Opens the add screen and re-reads on the way back.
  ///
  /// The add screen deliberately does not pop on save, so the read happens when
  /// the user leaves it rather than when the success dialog closes.
  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddCustomWordScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              countLabel: _isLoading
                  ? null
                  : customWordCountLabel(_words.length),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: _searchHint,
                        hintTextDirection: TextDirection.rtl,
                        // The drawing puts the magnifier at the field's
                        // right-hand end, which is the start side in this app —
                        // so it is a `prefixIcon`, not a suffix.
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.accentInk(isDark),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    if (_isLoading)
                      _Notice(
                        message: _loading,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: secondary,
                        ),
                      )
                    else if (_failed && _words.isEmpty)
                      _Notice(
                        message: _loadFailed,
                        style: theme.textTheme.headlineSmall,
                        actionLabel: _retry,
                        onAction: () {
                          setState(() {
                            _isLoading = true;
                            _failed = false;
                          });
                          unawaited(_load());
                        },
                      )
                    else if (_words.isEmpty)
                      _EmptyState(onAdd: _openAdd)
                    else
                      ..._list(secondary, error),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The rows, or the sentence that says the search found nothing.
  ///
  /// The query is filtered in the widget rather than in SQL: the screen already
  /// has every word, and `SearchMatcher` is the app's one search rule — the same
  /// one the pack search uses.
  List<Widget> _list(Color secondary, Color error) {
    final visible = SearchMatcher.filter(_words, _query);
    if (visible.isEmpty) {
      return <Widget>[
        _Notice(
          message: _noMatches,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: secondary),
        ),
      ];
    }

    return <Widget>[
      for (var i = 0; i < visible.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: AppSpacing.s),
        _WordCard(
          entry: visible[i],
          isFavorite: _favoriteIds.contains(visible[i].id),
          error: error,
          onToggleFavorite: () => _toggleFavorite(visible[i]),
          onRequestDelete: () => _requestDelete(visible[i]),
        ),
      ],
    ];
  }
}

/// The back control, the title and the count.
///
/// **The title sits against the start edge — the right in this app — with the
/// back control on that same edge and the count on the other**, which is the
/// drawing's order and the pushed screens' own (`FavoritesScreen`,
/// `StatsScreen`). A `Stack` keeps the two edge controls out of the title's
/// measured width.
class _Header extends StatelessWidget {
  const _Header({this.countLabel});

  /// Null while the first read is in flight: a count of zero before the answer
  /// is a number the screen does not know yet.
  final String? countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 64, end: 80),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: _backTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              // The back chevron points towards the right edge, where the user
              // came from in a right-to-left app.
              icon: const Icon(Icons.chevron_right_rounded, size: 32),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              child: Text(
                countLabel ?? '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accentInk(isDark),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One stored word: its Latin term, its Arabic meaning, a heart and a bin.
class _WordCard extends StatelessWidget {
  const _WordCard({
    required this.entry,
    required this.isFavorite,
    required this.error,
    required this.onToggleFavorite,
    required this.onRequestDelete,
  });

  final VocabEntry entry;
  final bool isFavorite;
  final Color error;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRequestDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppRadii.lg);

    return AppSurface(
      borderRadius: radius,
      fill: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      borderColor: isDark ? AppColors.borderDark : AppColors.borderLight,
      padding: EdgeInsets.zero,
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppGradients.card(isDark),
          borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The term is English in an Arabic app, so it names LTR and
                    // Inter explicitly. A term reordered by the paragraph or set
                    // in Tajawal's Latin would read as an accident.
                    Text(
                      entry.term,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.merge(AppText.latin)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      entry.primaryTranslation,
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              // The bin comes first in the row's children and therefore sits at
              // the right of this pair in RTL, with the heart at the physical
              // left — the artwork's placement. The two tooltips name them for a
              // screen reader, which cannot see which glyph is which.
              IconButton(
                tooltip: _deleteTooltip,
                onPressed: onRequestDelete,
                icon: Icon(Icons.delete_outline_rounded, color: error),
              ),
              FavoriteButton(
                isFavorite: isFavorite,
                onPressed: onToggleFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The delete confirmation: one sentence and two solid answers.
///
/// The green and the red are the saturated fills the brief specifies, not the
/// quiz's pale tonal containers — see [AppColors.successFill] and
/// [AppColors.errorFill] for the measured white contrast of each.
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.term});

  final String term;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      elevation: 0,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              // The word is drawn in Latin inside the Arabic sentence, and the
              // sentence names it so the user knows which row they are about to
              // lose.
              '$_confirmQuestion "$term"؟',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(_yes),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.successFill,
                      foregroundColor: AppColors.onSolidFill,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text(_no),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.errorFill,
                      foregroundColor: AppColors.onSolidFill,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A centred line, with an optional action under it. Never a spinner.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.style,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final TextStyle? style;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center, style: style),
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: AppSpacing.m),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dictionary with nothing in it yet, and the door to fix that.
///
/// **Bare text over the background, no empty card.** Every other empty state in
/// this app is text, and a card with nothing in it would be a shape standing in
/// for an answer; the action is under the sentence because the brief asks for an
/// add action here, not only for an explanation.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.m,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _emptyHeadline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            _emptySupporting,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.l),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text(_addWord),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
          ),
        ],
      ),
    );
  }
}
