import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/word_detail/word_detail_screen.dart';
import 'package:provider/provider.dart';

/// The chrome, in Arabic, like every other screen in this app.
const String _title = 'تفاصيل الكلمة';
const String _sensesHeading = 'المعاني';
const String _examplesHeading = 'أمثلة';
const String _addToFavorites = 'أضف إلى المفضلة';
const String _removeFromFavorites = 'إزالة من المفضلة';
const String _youMeant = 'هل تقصد';
const String _fromStem = 'صيغة مشتقة';
const String _fromTypo = 'خطأ إملائي محتمل';

/// One dictionary entry, in full.
///
/// **The screen is a pure function of its arguments**, exactly as
/// `WordDetailScreen` is: the truth about whether the word is saved belongs to
/// [DictionaryWordRoute], which owns it.
///
/// ## The long text, and why this screen exists
///
/// The shipped dictionary's longest English gloss is **616 characters**, its
/// longest Arabic is **366** and its longest example sentence is **236**. A
/// screen that lays those out as fixed-height cards either overflows or is
/// sized by the worst case in the corpus — and the worst case in the corpus
/// is one word out of 31,600.
///
/// So: **every card is sized by its own content**, nothing here has a fixed
/// height, and every run of text is allowed to wrap. The headword is the only
/// string with a line limit, and that is because a headword is one word.
///
/// ## The two directions
///
/// The headword, the phonetic and the English gloss are Latin and say so;
/// the Arabic keeps the app's direction. An unmarked English run in an RTL
/// paragraph is reordered by the paragraph, which reads as a bug rather than
/// as a decision.
class DictionaryWordScreen extends StatelessWidget {
  const DictionaryWordScreen({
    super.key,
    required this.entry,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final DictionaryEntry entry;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_title),
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
            Text(_sensesHeading, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            for (final sense in entry.senses) ...<Widget>[
              _SenseCard(sense: sense),
              const SizedBox(height: AppSpacing.s),
            ],
            const SizedBox(height: AppSpacing.m),
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

/// The word itself: the headword, its pronunciation, and how many senses it
/// has.
///
/// **One card, and it is content-sized.** The headword is the one string with
/// a line limit, and the reason is that a headword is a single word: a
/// two-line cap on a word that is one line long costs nothing and saves a
/// multi-word entry from pushing the rest of the screen off the fold.
class _HeadCard extends StatelessWidget {
  const _HeadCard({required this.entry});

  final DictionaryEntry entry;

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
          Text(
            entry.word,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineLarge?.merge(AppText.latinDisplay),
          ),
          if (entry.ipa != null && entry.ipa!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s),
            Row(
              children: <Widget>[
                // **Flexible, and that is load-bearing.** A phonetic
                // transcription is a run of Latin and IPA symbols, and a `Row`
                // with an unbounded `Text` in it overflows the moment the
                // string is longer than the card. `Flexible` lets it wrap
                // instead, and the speaker glyph beside it keeps its size.
                Flexible(
                  child: Text(
                    entry.ipa!,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodyLarge
                        ?.merge(AppText.latin)
                        .copyWith(color: secondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                const Icon(Icons.volume_up_rounded, color: AppColors.accent),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One sense: its Arabic, its part of speech, its English gloss, its examples.
///
/// **Every string here is allowed to wrap, and nothing here has a height.**
/// The Arabic can be 366 characters and the gloss 616, and the card is
/// therefore as tall as its own content is and no taller. A card sized by
/// the longest string in the corpus would leave one word out of 31,600 with
/// a screen full of empty space.
class _SenseCard extends StatelessWidget {
  const _SenseCard({required this.sense});

  final DictionarySense sense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (sense.arabic != null && sense.arabic!.trim().isNotEmpty)
            // **The Arabic, at a title size and not at a display size.** A
            // 366-character Arabic string set at `headlineSmall` is a wall,
            // and the first sense's Arabic is the one thing a user reads
            // first - it has to be readable, not impressive.
            Text(
              sense.arabic!,
              textDirection: TextDirection.rtl,
              style: theme.textTheme.titleLarge,
            ),
          if (sense.pos != null && sense.pos!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              sense.pos!,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
          if (sense.gloss != null && sense.gloss!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s),
            Text(
              sense.gloss!,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.merge(AppText.latin),
            ),
          ],
          if (sense.examples.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s),
            Text(
              _examplesHeading,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final example in sense.examples)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  example,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall?.merge(AppText.latin),
                ),
              ),
          ],
        ],
      ),
    );
  }
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

/// The pushed route: it owns whether this word is saved.
///
/// **The same two-path split as `WordDetailRoute`**, and for the same
/// reason: the screen is a pure function of its arguments so it can be
/// mounted with any state in a test, and something owns the truth.
///
/// The favourite is filed under the **dictionary's** pack key and its
/// **namespaced** entry id, so it cannot collide with a favourite of the same
/// word in the starter pack.
class DictionaryWordRoute extends StatefulWidget {
  const DictionaryWordRoute({
    super.key,
    required this.entry,
    this.packKey = dictionaryFavoritesPackKey,
  });

  final DictionaryEntry entry;

  /// The pack the favourite is filed under.
  final String packKey;

  @override
  State<DictionaryWordRoute> createState() => _DictionaryWordRouteState();
}

class _DictionaryWordRouteState extends State<DictionaryWordRoute> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final saved = await context.read<VocabRepository>().isFavorite(
          packKey: widget.packKey,
          entryId: dictionaryEntryId(widget.entry.norm),
        );
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
            entryId: dictionaryEntryId(widget.entry.norm),
            isFavorite: value,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFavorite = !value);
    }
  }

  @override
  Widget build(BuildContext context) => DictionaryWordScreen(
        entry: widget.entry,
        isFavorite: _isFavorite,
        onToggleFavorite: _toggle,
      );
}

/// The card that **offers** a word the user might have meant.
///
/// **It never shows the word as if the user had typed it.** The typed form is
/// on the card in the user's own spelling, the offered word is named beside
/// it, and the reason is named too. A memorisation app that quietly swapped
/// `childern` for `child` would teach the user that typos do not matter, and
/// this one is for memorising.
class DictionarySuggestionCard extends StatelessWidget {
  const DictionarySuggestionCard({
    super.key,
    required this.typed,
    required this.entry,
    required this.reason,
    required this.onOpen,
  });

  /// What the user typed, verbatim.
  final String typed;

  /// The word being offered.
  final DictionaryEntry entry;

  /// Why it is being offered: `stem` or `spelling`.
  final String reason;

  /// Opens the offered word.
  final VoidCallback onOpen;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$_youMeant ${entry.word}؟',
            textDirection: TextDirection.rtl,
            style: theme.textTheme.titleMedium?.copyWith(color: ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            typed,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodyMedium
                ?.merge(AppText.latin)
                .copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason == 'stem' ? _fromStem : _fromTypo,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.s),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                elevation: 0,
                shape: const StadiumBorder(),
              ),
              child: const Text('افتح'),
            ),
          ),
        ],
      ),
    );
  }
}
