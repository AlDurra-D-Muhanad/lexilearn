import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

/// The chrome and the copy, in Arabic — the app is RTL end to end and the
/// artwork's chrome is Arabic.
const String _title = 'تفاصيل الكلمة';
const String _synonymsHeading = 'المترادفات';
const String _examplesHeading = 'أمثلة أخرى';
const String _noteHeading = 'ملاحظة';
const String _addToFavorites = 'أضف إلى المفضلة';
const String _removeFromFavorites = 'إزالة من المفضلة';

/// The heart, in the AppBar and nowhere else.
///
/// **Amber when the word is saved, and only then.** `design_tokens.dart` permits
/// `#F59E0B` for icons and fills only, and this is the icon case the brand
/// reserves it for. Un-saved it wears the secondary grey, so the control reads
/// as "you can do this" rather than as "this is already done" — and the shape
/// says the same thing twice, filled versus outlined, for anyone who cannot see
/// the colour.
///
/// Stateless and controlled: [isFavorite] is what the caller believes and
/// [onPressed] is what it does about it. Nothing here touches a database, so the
/// same widget serves the pushed route, a golden, and a test that counts taps.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onPressed,
  });

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The brand reserves the amber for the book mark and for favourites.
    //
    // On the **`Icon`**, not on the `IconButton`. `IconButton` would resolve this
    // through its own `IconTheme.merge`, which is invisible on the `Icon` widget
    // itself — `Icon.build` reads `color ?? iconTheme.color!`
    // (`flutter/lib/src/widgets/icon.dart`), so an `IconButton.color` leaves
    // `Icon.color` null and the only way to read what was rendered is to walk the
    // inherited theme. Putting it on the `Icon` states it where it is drawn, and
    // wins over the button's theme for the same reason.
    final colour = isFavorite
        ? AppColors.accentInk(isDark)
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);
    return IconButton(
      onPressed: onPressed,
      tooltip: isFavorite ? _removeFromFavorites : _addToFavorites,
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: colour,
      ),
    );
  }
}

/// The artwork's Word Detail phone: the word, its pronunciation, what kind of
/// word it is, every meaning, then the optional sections, then one primary
/// action.
///
/// **Two Latin runs and one Arabic run, and each says which it is.** The term,
/// the phonetic, the synonyms, the examples and the note are English and are
/// marked `TextDirection.ltr` with `AppText.latin`; the translations are Arabic
/// and keep the app's direction and the ambient family. The app is RTL
/// end-to-end (`LexiLearnApp`), so an unmarked English run would be reordered by
/// the paragraph and would render in Tajawal's own Latin, which reads as an
/// accident rather than a decision.
///
/// **Every optional section is hidden when it has nothing to show.** The bundled
/// dataset is `English.txt`, which carries no phonetic, no part of speech, no
/// synonyms and no examples — so the common case is the *bare* one and an
/// always-visible heading over nothing would be a lie in the app as it ships.
///
/// **One inference, marked as an inference.** The artwork draws a speaker glyph
/// 🔊 beside the pronunciation. Text-to-speech is out of scope by user decision,
/// so it is an `Icon` and not a control, exactly as `home_screen.dart`'s
/// word-of-the-day card already draws it — same glyph, same amber, no tap target.
class WordDetailScreen extends StatelessWidget {
  const WordDetailScreen({
    super.key,
    required this.entry,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final VocabEntry entry;

  /// What the caller believes about this word. Passed in rather than read here,
  /// so the screen is a pure function of its arguments and can be mounted with
  /// any state in a test. [WordDetailRoute] is the thing that owns the truth.
  final bool isFavorite;

  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_title),
        // The header sits on the background rather than on a raised surface,
        // matching the artwork's word-card header and every other screen in the
        // app. The AppBar's own default would be `surfaceContainer`, drawing a
        // second tone across the top of a screen whose only surfaces are the
        // cards below it.
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          FavoriteButton(
            isFavorite: isFavorite,
            onPressed: onToggleFavorite,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.m),
          children: <Widget>[
            _HeadCard(entry: entry),
            const SizedBox(height: AppSpacing.l),
            // The artwork's second-biggest element, so the first translation is
            // set at `headlineSmall`. Any further ones are alternate readings of
            // the same word rather than further content, so they step down to
            // `titleLarge` — otherwise a word with three translations would make
            // the meanings section longer than the word's own card.
            for (var i = 0; i < entry.translations.length; i++) ...<Widget>[
              Text(
                entry.translations[i],
                style: i == 0
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.titleLarge,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.s),
            ],
            if (entry.note.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.s),
              Text(_noteHeading, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                entry.note,
                textDirection: TextDirection.ltr,
                style: AppText.latin.merge(theme.textTheme.bodyMedium),
              ),
            ],
            if (entry.synonyms.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.l),
              _SynonymsCard(synonyms: entry.synonyms),
            ],
            if (entry.examples.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.l),
              _ExamplesCard(examples: entry.examples),
            ],
            const SizedBox(height: AppSpacing.l),
            _FavoriteAction(
              isFavorite: isFavorite,
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}

/// The word itself: the term at display size, its pronunciation, and what kind
/// of word it is. One card, so the three belong together and the meanings below
/// read as a list rather than as a fourth thing the word is.
class _HeadCard extends StatelessWidget {
  const _HeadCard({required this.entry});

  final VocabEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // `headlineLarge` rather than a raw `fontSize`. It is 32, which is what
          // this screen wants, and it comes from the app's own type scale rather
          // than from a sixth `copyWith(fontSize: …)` — see `docs/
          // engineering-standards.md` §8 on literals that drift.
          Text(
            entry.term,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineLarge?.merge(AppText.latinDisplay),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: <Widget>[
              if (entry.phonetic.isNotEmpty)
                Flexible(
                  child: Text(
                    entry.phonetic,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.merge(AppText.latin)
                        .copyWith(color: secondary),
                  ),
                ),
              // Static, never played: text-to-speech is out of scope by user
              // decision, so the artwork's speaker is a glyph and not a control.
              // `home_screen.dart`'s word-of-the-day card draws the same one.
              if (entry.phonetic.isNotEmpty) ...<Widget>[
                const SizedBox(width: AppSpacing.s),
                Icon(
                  Icons.volume_up_rounded,
                  color: AppColors.accentInk(
                    Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ],
            ],
          ),
          if (entry.partOfSpeech.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.m),
            _LatinChip(label: entry.partOfSpeech),
          ],
        ],
      ),
    );
  }
}

/// The artwork's synonyms, as chips.
///
/// One `AppSurface` for the heading and the chips together, so the heading has
/// exactly one card above it — the same rule `stats_screen.dart`'s `_SessionsCard`
/// follows.
class _SynonymsCard extends StatelessWidget {
  const _SynonymsCard({required this.synonyms});

  final List<String> synonyms;

  @override
  Widget build(BuildContext context) => AppSurface(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_synonymsHeading,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: <Widget>[
                for (final synonym in synonyms) _LatinChip(label: synonym),
              ],
            ),
          ],
        ),
      );
}

/// The artwork's example sentences.
///
/// English prose, so each is a Latin run with an explicit direction, the way
/// `home_screen.dart`'s `_EntryRow` writes a note.
class _ExamplesCard extends StatelessWidget {
  const _ExamplesCard({required this.examples});

  final List<String> examples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_examplesHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s),
          for (var i = 0; i < examples.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.s),
            Text(
              examples[i],
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.merge(AppText.latin),
            ),
          ],
        ],
      ),
    );
  }
}

/// A chip whose label is English.
///
/// `ChipThemeData.labelStyle` names Tajawal, because every other chip in the app
/// is Arabic. This one is dataset free text that is Latin in every pack the app
/// ships, so it asks for Inter and LTR explicitly rather than being re-faced by
/// the theme or reordered by the paragraph.
///
/// No `elevation: 0`: `app_theme.dart`'s `chipTheme` pins it app-wide, and
/// `chip.dart`'s own last fallback is already 0, so a local override here would
/// pin a value that is already right.
class _LatinChip extends StatelessWidget {
  const _LatinChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(
          label,
          textDirection: TextDirection.ltr,
          style: AppText.latin,
        ),
      );
}

/// The one primary action, full width, in the artwork's purple.
class _FavoriteAction extends StatelessWidget {
  const _FavoriteAction({required this.isFavorite, required this.onPressed});

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          label: Text(
            isFavorite ? _removeFromFavorites : _addToFavorites,
          ),
          style: FilledButton.styleFrom(shape: const StadiumBorder()),
        ),
      );
}

/// The pushed route: it owns whether this word is saved, and it is what
/// `HomeShell._openWordDetail` and `FavoritesScreen`'s `onOpenWord` push.
///
/// **Separate from [WordDetailScreen] on purpose.** The screen's own signature is
/// fixed — `entry`, `isFavorite`, `onToggleFavorite` — so it cannot hold state
/// without turning into a `StatefulWidget` that a test could not mount with a
/// chosen answer. This is the same two-path split `StatsScreen` and `MoreScreen`
/// use for their controllers: the screen stays a pure function of its arguments,
/// and something owns the lifetime.
///
/// The toggle is **optimistic and rolls back**, rather than waiting for the
/// write before the heart moves. A local SQLite write is fast, but "fast" is not
/// "instant", and a heart that waits for a round trip before it fills reads as a
/// dropped tap. The rollback is what makes that honest: if the write fails the
/// heart goes back, so the screen never claims a save that did not happen.
class WordDetailRoute extends StatefulWidget {
  const WordDetailRoute({
    super.key,
    required this.entry,
    required this.packKey,
  });

  final VocabEntry entry;

  /// The pack the word belongs to. Favourites are scoped to a pack, so the heart
  /// cannot be answered without it — and a word is reachable from two packs'
  /// screens, which share no favourites.
  final String packKey;

  @override
  State<WordDetailRoute> createState() => _WordDetailRouteState();
}

class _WordDetailRouteState extends State<WordDetailRoute> {
  /// What the heart shows. Starts false, so the very first frame after the route
  /// is pushed has a heart rather than nothing — and [_read] corrects it one
  /// turn later, which is the same shape as every other screen's start-up read.
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final saved = await context
        .read<VocabRepository>()
        .isFavorite(packKey: widget.packKey, entryId: widget.entry.id);
    // A back that beat the read must not leave a setState on a dead State.
    if (!mounted) return;
    setState(() => _isFavorite = saved);
  }

  void _toggle() {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    unawaited(_write(next));
  }

  Future<void> _write(bool value) async {
    try {
      await context.read<VocabRepository>().setFavorite(
            packKey: widget.packKey,
            entryId: widget.entry.id,
            isFavorite: value,
          );
    } catch (_) {
      // Put the heart back rather than leaving a claim the database refuses to
      // keep. There is no message: the screen has one line of chrome and an
      // artwork that specifies none, and a stale heart is a smaller lie than an
      // invented error state.
      if (!mounted) return;
      setState(() => _isFavorite = !value);
    }
  }

  @override
  Widget build(BuildContext context) => WordDetailScreen(
        entry: widget.entry,
        isFavorite: _isFavorite,
        onToggleFavorite: _toggle,
      );
}