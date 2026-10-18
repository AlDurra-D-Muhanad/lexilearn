import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

import 'flashcard_controller.dart';

/// The chrome and the card copy, all of it read off
/// `docs/design/brand-reference.png` §4ج and the PNG itself.
///
/// **This is the one screen in the app where a committed raster is a reference
/// rather than an implementer's invention.** `docs/engineering-standards.md` §10
/// records Task 13 leaving `MoreScreen` without a golden *because the artwork
/// draws no such screen* — here §4ج names the screen and both phones in the PNG
/// draw it, so every string below is pinned against the artwork and
/// `test/ui/flashcards_screen_test.dart` asserts them.
///
/// Two of them disagree with the sources they came from, and both disagreements
/// are recorded where they are used rather than smoothed over:
///
/// * the **title** is `بطاقات التعلم` — plural, as the *light* phone draws it.
///   The dark phone draws `بطاقة التعلم`, singular, and this app's own Home tile
///   (`_QuickLaunchGrid`) and its bar label are both plural.
/// * the **swipe hint** is `السحب للتالي`. §4ج's prose says `<< اسحب لليوم >>`
///   and the plan's snippet says `<< اسحب للتالي >>`, and the PNG — which §10
///   makes the authority — says `السحب للتالي`, in **both** phones.
const _title = 'بطاقات التعلم';
const _knowIt = 'أعرف';
const _dontKnowIt = 'لا أعرف';
const _reveal = 'عرض المعنى';
const _swipeHint = 'السحب للتالي';
const _finished = 'انتهت الجلسة';
const _emptyPack = 'لا توجد بطاقات بعد';
const _emptyPackSupporting = 'أضف كلمات إلى حزمتك لتبدأ البطاقات.';

/// How many cards a deck deals, whatever the pack holds.
///
/// **Not from the plan and not from the data — from §4ج's own counter.** The
/// artwork draws `3/10`, and `English.txt` ships 297 entries, so a deck cannot
/// be the whole pack: `3/297` is not the screen the brand drew. A deck is the
/// pack, capped at ten cards, which is also the number of questions a session
/// reads as being worth doing.
const int _deckSize = 10;

/// The illustrated panel's proportion: width over height.
///
/// Measured off the PNG rather than chosen. In the light phone's card the panel
/// runs `x 454..623` (170 px) and, on a column through it, the illustration
/// occupies `y ≈ 286..373` (87 px) — an aspect of **1.95**, which rounds to the
/// 2:1 below.
const double _natureAspect = 2;

/// The term's size, and the largest text on this screen.
///
/// Named here for the reason `stats_screen.dart` names `_ringDiameter`: no entry
/// in `AppSpacing` or `AppText` describes a display size *this* screen needs, and
/// a literal at the call site is how two screens drift apart on what was meant to
/// be one decision. `AppText.wordOfTheDay` is Home's and is deliberately not
/// reused: the artwork draws this term larger than the word-of-the-day card's.
const double _termSize = 30;

/// The two answer buttons' height.
///
/// The artwork draws them as tall pills — 42 px in a mock phone whose content
/// column is 170 px wide, so roughly a quarter of the card's width. Material's
/// own minimum is 40. A phone-sized 52 px is the closest comfortable reading of
/// that, and it is the one number here that is a judgement rather than a
/// measurement.
const double _actionHeight = 52;

/// The brand's second destination: the flashcard deck.
///
/// **A bottom-bar destination, not a pushed route.** The artwork's bar draws
/// exactly four items — الرئيسية, البطاقات, الاختبارات, المزيد — in both the
/// light and the dark phone, and `lib/ui/home_shell.dart` indexes its `screens`
/// list straight off that bar. This screen is `screens[1]`, it replaces nothing,
/// and it takes the pack key the shell already resolved.
///
/// Stateless, and it reads its controller from the tree when there is one.
/// `StatsScreen` does the same and for the same reason: the app has no
/// `FlashcardController` provider, so [_DeckOwner] creates and disposes one,
/// while a test — or the reference-image capture — needs to hand in an instance
/// it has already dealt so the word on the card is one it can name. A fixed seed
/// in the screen itself would give every user the identical deck, which is the
/// opposite of what a vocabulary app is for.
class FlashcardsScreen extends StatelessWidget {
  const FlashcardsScreen({super.key, required this.packKey});

  /// The pack the deck deals from. Empty until `HomeShell` resolves it, and
  /// empty for good when nothing is installed.
  final String packKey;

  @override
  Widget build(BuildContext context) {
    final injected = context.read<FlashcardController?>();
    if (injected != null) {
      return _DeckBody(controller: injected, packKey: packKey);
    }
    return _DeckOwner(packKey: packKey);
  }
}

/// Owns the controller for the app's path, where nothing else provides one.
class _DeckOwner extends StatefulWidget {
  const _DeckOwner({required this.packKey});

  final String packKey;

  @override
  State<_DeckOwner> createState() => _DeckOwnerState();
}

class _DeckOwnerState extends State<_DeckOwner> {
  /// Null while the pack size is still being read, which is the screen's
  /// loading state. See [_DeckBody]'s three cases.
  FlashcardController? _controller;

  /// **Every controller this state has created, including one it is done with.**
  ///
  /// **Disposed only in [dispose], never when it is replaced, and that is a fix
  /// rather than tidiness.** Every controller issues two sequential reads — the
  /// pack size in [_DeckOwnerState._load] and `start()` behind it — and
  /// `flutter_test` tears the tree down at the end of a test whether or not those
  /// have answered. Disposing a controller whose read is still in flight does
  /// **not** cancel it: the future still lands, and against a harness that has
  /// already closed it throws `SqfliteFfiException(error, Bad state: This
  /// database has already been closed)` *from a test that had already passed*.
  /// Measured on `test/ui/home_screen_test.dart` → *the bar follows the tile and
  /// Back is not needed to return*, which taps the flashcard tile and taps
  /// straight back: `SELECT * FROM entries WHERE pack_key = ?` arrived after the
  /// harness had closed.
  final List<FlashcardController> _created = <FlashcardController>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load(widget.packKey));
  }

  @override
  void didUpdateWidget(_DeckOwner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packKey == widget.packKey) return;
    unawaited(_load(widget.packKey));
  }

  /// Reads the pack to learn how many cards the deck has, then deals the first.
  ///
  /// **One sequential database round trip, not two, and that is the screen's own
  /// shape rather than an accident.** `FlashcardController` takes its card count at
  /// construction — the §4ج `3/10` counter and the progress bar both need it, and
  /// deriving them from the cards actually dealt would make the denominator
  /// unknowable until the deck was over — so the size has to be known *before* the
  /// controller exists, and only the pack can say. The words this read returns go
  /// straight into the controller, so dealing from them costs no further round
  /// trip; see `FlashcardController.entries`. Before that, [start] read the pack a
  /// second time, and `test/ui/home_screen_test.dart` — which taps this screen
  /// from the Home grid and then taps straight back — failed with *A Timer is
  /// still pending even after the widget tree was disposed* plus a
  /// `Bad state: This database has already been closed` thrown **after** the test
  /// had completed. Halving the reads is what fixed it.
  Future<void> _load(String packKey) async {
    final repository = context.read<VocabRepository>();
    // An empty key is the shell's start-up window, not a missing pack: asking
    // about it would answer "no such pack" and turn a normal frame into an error
    // state. The same short-circuit `VocabRepository.favorites` makes.
    final entries =
        packKey.isEmpty ? const <VocabEntry>[] : await repository.entries(packKey);

    // Two pack switches in quick succession race here; only the last one wins.
    if (!mounted || widget.packKey != packKey) return;
    final controller = FlashcardController(
      repository: repository,
      packKey: packKey,
      cardCount: min(entries.length, _deckSize),
      // **The words this read just returned, handed straight in.** Without this
      // `start()` would read the same pack a second time, and this screen's whole
      // cost is that round trip: a `testWidgets` body drives the real event loop
      // only through `runAsync`, so a second read is another wait for every test
      // that reaches this screen and another chance for one to still be in flight
      // when a test ends.
      entries: entries,
    );
    // Parked before it is started, so nothing can slip between the two.
    _created.add(controller);
    setState(() => _controller = controller);
    unawaited(controller.start());
  }

  @override
  void dispose() {
    // **Every** controller this state created, the current one and every one it
    // has replaced — and only here. See the note on [_created]: disposing one
    // while its read is still in flight does not cancel that read, it just
    // guarantees a `Bad state: This database has already been closed` from a test
    // that has already finished. `_notifyIfAlive` makes every notification
    // between the two a no-op, which is the other half of why this is safe.
    for (final controller in _created) {
      controller.dispose();
    }
    _created.clear();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Still reading the pack. The same notice [_DeckBody] shows between dealing
    // the first card and its read answering, so a screen that arrives at the card
    // from either direction does not change its face.
    if (controller == null) {
      return _DeckNotice(
        message: _loading,
        packKey: widget.packKey,
        // This notice replaces the whole screen, so there is no AppBar to carry
        // the pack key and this is the only place it can be named.
        showPackKey: true,
      );
    }
    return _DeckBody(controller: controller, packKey: widget.packKey);
  }
}

/// The screen, rebuilt whenever the controller notifies.
class _DeckBody extends StatelessWidget {
  const _DeckBody({required this.controller, required this.packKey});

  final FlashcardController controller;

  /// Shown in the bar's action slot and in the empty-pack notice.
  ///
  /// Read from the widget rather than from the controller so that an **injected**
  /// controller still names the pack it is drawing from — the key is a fact about
  /// the screen, not about the deal, and the shell's own test asserts it on every
  /// destination whichever controller happens to be driving the card.
  final String packKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          // The artwork's own title reads «بطاقة التعلم» — *the* learning card,
          // singular — and §4ج never names the title at all; it names the progress
          // indicator, the image, the word, the three controls and the swipe
          // hint. This app's **bar** label is `البطاقات` and its Home tile is
          // `بطاقات التعلم`, both plural, and a screen whose title contradicts the
          // label the user just tapped reads as a typo. The app's plural wins,
          // and it is recorded in the task report rather than claimed as a match.
          title: const Text(_title),
          // On the background rather than on a raised surface, for the reason
          // `StatsScreen`'s is: Material's default would draw a second tone across
          // the top of a screen whose only surfaces are the card below it.
          backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          surfaceTintColor: Colors.transparent,
          // **The pack key, in the bar's own actions slot.**
          //
          // `HomeShell` resolves the active pack once and threads the key to all
          // four destinations, and `test/ui/home_shell_test.dart` asserts the key
          // is *visible* on every one of them — "what proves the shell threads
          // state around rather than merely swapping four widgets". The
          // placeholder this screen replaces met that with a pill in the body,
          // and the artwork has no room for one: its header is the title, a back
          // arrow and the progress row, and nothing else.
          //
          // The actions slot is where this app already puts a run that is metadata
          // rather than chrome, and it leaves the artwork's body exactly as drawn.
          actions: <Widget>[_PackKeyBadge(packKey: packKey)],
        ),
        body: SafeArea(child: _body(context, theme, isDark)),
      ),
    );
  }

  Widget _body(BuildContext context, ThemeData theme, bool isDark) {
    final card = controller.current;

    // **Three cases, and the order is the whole thing.**
    //
    // No card and not finished is *loading*: the read behind `start()` has not
    // answered. A pack with no words in it is *not* that case — it comes back
    // finished — which is the distinction `FlashcardController.isFinished` exists
    // to make, and it is why the empty-pack state is not reachable by accident.
    //
    // **Never a spinner.** An indeterminate `CircularProgressIndicator` schedules
    // frames forever, so `pumpAndSettle` never returns while one is on screen,
    // and this screen is reached by the bottom bar in both the app and every test
    // that touches it. Same decision, same reason, as `stats_screen.dart`.
    if (card == null) {
      if (!controller.isFinished) {
        return _DeckNotice(message: _loading, packKey: packKey);
      }
      // **Finished having answered nothing can only mean the pack had no words.**
      // `_cardCount` is clamped to at least 1, so a deck that ran its course
      // always has `index > 0`; the two states are otherwise the same shape —
      // no card, finished — and saying "انتهت الجلسة" over a pack with no words
      // would claim the user did a session they never started.
      if (controller.index == 0) {
        return _DeckNotice(
          message: _emptyPack,
          supporting: _emptyPackSupporting,
          packKey: packKey,
        );
      }
      return _FinishedDeck(controller: controller);
    }

    // **Scrollable, and that is a fix rather than slack.** The card is a column
    // of fixed-height pieces, and the illustrated panel's height comes from its
    // *width*: on the artwork's phone the body is 328 px across and the panel is
    // 164 px, which leaves the word card the rest. Measured, on the default
    // 800x600 test surface the same column was given 798 px, the panel became
    // 399 px, and the card overflowed **by 157 px** — a `RenderFlex` assertion,
    // not a cosmetic difference. So the body fills the viewport when it fits
    // (`ConstrainedBox` at `minHeight`) and scrolls when it does not
    // (`SingleChildScrollView`), which is what `stats_screen.dart`'s dashboard
    // and `home_screen.dart`'s do for the same reason.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          // `Expanded` needs a bounded height and `SingleChildScrollView` does
          // not give one; `IntrinsicHeight` is what lets the card take up the
          // slack on a phone *and* let the column grow past the viewport on a
          // window that cannot hold it. One column, so the cost is one column.
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ProgressRow(controller: controller),
                  const SizedBox(height: AppSpacing.m),
                  Expanded(child: _Card(controller: controller, entry: card)),
                  const SizedBox(height: AppSpacing.m),
                  _KnowItButton(onPressed: () => controller.answer(knewIt: true)),
                  const SizedBox(height: AppSpacing.s),
                  _DontKnowItButton(
                    onPressed: () => controller.answer(knewIt: false),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  _RevealLink(onPressed: controller.reveal, isDark: isDark),
                  const SizedBox(height: AppSpacing.m),
                  const _SwipeHint(),
                  const SizedBox(height: AppSpacing.m),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// §4ج's «مؤشر 3/10»: the fraction beside the bar, and the bar.
///
/// **The bar fills from the right and the counter sits at the far left, and
/// both are the app's direction rather than the artwork's.** The PNG draws this
/// row left-to-right — the fill at the track's *left* end and `3/10` at the
/// *right* — on both phones, which is what a mock's progress row looks like once
/// it is inside an Arabic screen; the mock's own title and back arrow on the same
/// screen are laid out RTL, so the row is the inconsistent part and not the
/// screen. `_Header` in `home_screen.dart` records the same call for the same
/// reason. Everything else about the row is the artwork's: determinate, rounded,
/// and no more than a fraction of the bar.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.controller});

  final FlashcardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final fill = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final track = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: controller.progress,
              minHeight: 8,
              backgroundColor: track,
              valueColor: AlwaysStoppedAnimation<Color>(fill),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        // A fraction is a Latin run: an RTL paragraph reorders digits and a
        // slash, and it would name Tajawal's own Latin rather than Inter's.
        Text(
          '${controller.index + 1}/${controller.total}',
          textDirection: TextDirection.ltr,
          style: AppText.latin.copyWith(
            fontSize: AppText.caption,
            color: secondary,
          ),
        ),
      ],
    );
  }
}

/// The card: the artwork's illustration, and the word with its pronunciation and
/// its Arabic.
///
/// **One surface, not two.** In the artwork the illustrated panel and the white
/// panel under it share an edge — the illustration's bottom corners are square
/// and the word card's top edge runs straight across beneath it — so they are a
/// single rounded unit here, and a second `AppSurface` between them would put a
/// hairline across a picture.
///
/// **The illustration is drawn, not loaded.** §4ج names «صورة طبيعة مروسة», a
/// hand-drawn nature image, and `docs/design/brand-reference.png` draws a
/// mountain lake. There is no image asset in this repository and no way to add
/// one inside this task's file list, and photographs are already out of scope by
/// user decision — `home_screen.dart`'s word-of-the-day card says so about the
/// artwork's own photograph. So the panel holds the brand's own nature glyph at
/// the artwork's proportion, and the *slot* is what this screen owns: where the
/// image goes, how tall it is, and that it is the card's header. **This is an
/// inference, and it is marked as one in the task report.**
class _Card extends StatelessWidget {
  const _Card({required this.controller, required this.entry});

  final FlashcardController controller;
  final VocabEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Only the top corners are rounded: the panel runs into the word card
          // below it, exactly as the artwork draws it.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
            child: AspectRatio(
              aspectRatio: _natureAspect,
              child: _NaturePanel(isDark: isDark),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      // **First child, so it draws at the START — the right, in
                      // RTL — and the artwork puts the speaker on that side.**
                      // It was last, which put it left of the word, and nothing
                      // noticed: the glyph is decoration, so no assertion failed
                      // and the committed reference image showed the mirror of
                      // what `brand-reference.png` draws. Verified off the raster
                      // rather than taken on trust — scanning the light phone's
                      // word row for the purple glyph against the dark word ink
                      // returns dark ink at `x 495..577` and then an isolated
                      // purple block carrying **no** dark ink at `x 585..599`.
                      //
                      // Static, never played: text-to-speech is out of scope by
                      // user decision, so the artwork's speaker is a glyph and not
                      // a control. Same as the one on the word-detail screen and
                      // on Home's card.
                      Icon(Icons.volume_up_rounded, color: _speakerColour(isDark)),
                      const SizedBox(width: AppSpacing.s),
                      Flexible(
                        child: Text(
                          entry.term,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.latinDisplay
                              .copyWith(fontSize: _termSize, color: ink),
                        ),
                      ),
                    ],
                  ),
                  // A word with no phonetic omits the row rather than stranding
                  // an empty line, which is the defect `word_detail_screen.dart`
                  // was written against.
                  if (entry.phonetic.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // First child, so it draws at the start — the right — as
                        // the artwork draws it. See the term row above for why
                        // this was worth measuring.
                        Icon(Icons.volume_up_rounded, size: 16, color: secondary),
                        const SizedBox(width: AppSpacing.s),
                        Flexible(
                          child: Text(
                            entry.phonetic,
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.latin.copyWith(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.m),
                  // Hidden until the user asks for it — that is what the
                  // «عرض المعنى» link is for. Every translation is shown, as on
                  // the word-detail screen and in a search result.
                  if (controller.revealed)
                    for (final translation in entry.translations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(
                          translation,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600, color: ink),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The speaker's colour, which is the artwork's one real mode-dependent swap
  /// besides the affirmative button: violet beside the term in the light phone,
  /// amber in the dark one — the same purple→amber substitution §4ج states for
  /// «أعرف».
  static Color _speakerColour(bool isDark) =>
      isDark ? AppColors.accent : AppColors.primaryLight;
}

/// The artwork's nature illustration, as a brand wash and a glyph.
///
/// A wash rather than the full-strength colour for the same reason `_BookMark` is
/// one in `home_screen.dart`: at full strength the fill shouts louder than the
/// word the card exists to show.
class _NaturePanel extends StatelessWidget {
  const _NaturePanel({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final colour = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    return ColoredBox(
      color: colour.withValues(alpha: isDark ? 0.24 : 0.16),
      child: Center(
        child: Icon(Icons.landscape_rounded, size: 44, color: colour),
      ),
    );
  }
}

/// «أعرف» — the filled pill.
///
/// **Purple in light, amber in dark, and that is §4ج's own sentence**: «زر أعرف
/// (بنفسجي بالوضع الفاتح / أصفر بالوضع الداكن)». It is not an accident of the
/// raster: `docs/design/brand-reference.md` §2's dark palette gives `#F59E0B`
/// to «الأزرار الذهبية الرئيسية», main golden buttons, so the mock and the
/// palette agree. Everything else on this screen swaps mode by naming the other
/// brightness's token; this one swaps hue, which is why the resolved colour is
/// asserted rather than inferred.
///
/// **No `elevation: 0`.** `AppTheme` zeroes all three elevated families, and
/// `docs/engineering-standards.md` §6 and the theme's own comment record that the
/// per-widget opt-out had already failed on three screens. `TextButton` is not in
/// that block because it needs nothing.
class _KnowItButton extends StatelessWidget {
  const _KnowItButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: _actionHeight,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? AppColors.accent : AppColors.primaryLight,
          // On the amber pill the readable ink is the *background* one, not the
          // text one — `#F59E0B` under `#F9FAFB` would be unreadable.
          foregroundColor:
              isDark ? AppColors.backgroundDark : AppColors.surfaceLight,
          shape: const StadiumBorder(),
        ),
        child: const Text(_knowIt),
      ),
    );
  }
}

/// «لا أعرف» — §4ج's «مفرغ بحواف خفيفة», an outlined button with a light border.
///
/// No background is declared at all rather than a transparent one: a `FilledButton`
/// is the affirmative control and this is deliberately not it, and
/// `OutlinedButton` already defaults to no fill.
class _DontKnowItButton extends StatelessWidget {
  const _DontKnowItButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The same swap the affirmative button makes, so the pair reads as one set.
    final ink = isDark ? AppColors.accent : AppColors.primaryLight;
    return SizedBox(
      height: _actionHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink),
          shape: const StadiumBorder(),
        ),
        child: const Text(_dontKnowIt),
      ),
    );
  }
}

/// «عرض المعنى» — §4ج's «رابط عرض المعنى», a link and not a button.
///
/// `TextButton` rather than a styled `Text`: it is the one family in the app that
/// defaults to elevation 0 in every state, it carries a real button target for
/// touch, and it gives a screen reader a control rather than a paragraph.
class _RevealLink extends StatelessWidget {
  const _RevealLink({required this.onPressed, required this.isDark});

  final VoidCallback onPressed;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // §2 assigns the primary to «الروابط», links, in the light palette. In the
    // dark phone the artwork draws this link in the plain light ink rather than
    // the amber the two buttons take, so it follows the ink and not the accent.
    final colour = isDark ? AppColors.textDark : AppColors.primaryLight;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: colour),
      child: const Text(_reveal),
    );
  }
}

/// «السحب للتالي» in the pill the artwork draws it in.
///
/// The chevrons are separate runs rather than a single `<< … >>` string so the row
/// spaces like the artwork's: glyph, label, glyph, with the label in the middle.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text('>>', textDirection: TextDirection.ltr, style: _chevron(secondary)),
          // **The Arabic face, named — not `AppText.latin`.** The hint is Arabic,
          // and Inter's `cmap` carries no Arabic, so setting it in the brand Latin
          // rasterised the whole string as tofu boxes. Every assertion on the
          // string still passed, because `find.text` matches a tofu row just as
          // happily as a legible one; only opening the generated reference image
          // showed it. Same rule as `home_screen.dart`'s search field.
          Text(
            _swipeHint,
            style: AppText.arabic
                .copyWith(fontSize: AppText.caption, color: secondary),
          ),
          Text('<<', textDirection: TextDirection.ltr, style: _chevron(secondary)),
        ],
      ),
    );
  }

  static TextStyle _chevron(Color colour) => AppText.latinDisplay.copyWith(
        fontSize: AppText.caption,
        color: colour,
      );
}

/// The deck is over.
///
/// **Not in the artwork, and marked as an inference.** `docs/design/brand-reference.md`
/// §4ج describes the card and its three controls and nothing else, so the
/// end-of-deck state is the plan's (`انتهت الجلسة` plus a count) and the
/// arrangement is this task's. It says what was known out of how many because
/// that is the one number the deck produced that the progress bar does not
/// already show — `FlashcardController.knownCount` is kept separately from
/// `progress` for exactly this reason.
class _FinishedDeck extends StatelessWidget {
  const _FinishedDeck({required this.controller});

  final FlashcardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = isDark ? AppColors.primaryDark : AppColors.primaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${controller.knownCount} / ${controller.total}',
              textDirection: TextDirection.ltr,
              style: AppText.latinDisplay.copyWith(fontSize: _termSize, color: ink),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(_finished, style: theme.textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}

/// A sentence, never a spinner — see `_DeckBody._body`.
class _DeckNotice extends StatelessWidget {
  const _DeckNotice({
    required this.message,
    required this.packKey,
    this.supporting,
    this.showPackKey = false,
  });

  final String message;
  final String? supporting;

  /// Named here as well as in the bar, because the bar is not always on screen:
  /// [_DeckOwnerState.build] returns a notice *instead of* [_DeckBody], so there
  /// is no Scaffold and no AppBar and nothing else would name the pack.
  final String packKey;

  /// **Exactly one place on the screen names the pack.**
  /// `home_shell_test.dart` asserts `findsOneWidget`, not `findsWidgets`. A notice
  /// reached through [_DeckBody] already has the bar's badge above it, and this
  /// widget is *inside* that Scaffold — so drawing a second one there found two
  /// copies and failed the assertion. `true` only for the notice that replaces the
  /// whole screen.
  final bool showPackKey;

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
              style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
            ),
            if (supporting != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s),
              Text(
                supporting!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            ],
            if (showPackKey) ...<Widget>[
              const SizedBox(height: AppSpacing.m),
              _PackKeyBadge(packKey: packKey),
            ],
          ],
        ),
      ),
    );
  }
}

/// The pack this deck deals from, named.
///
/// **Exactly once on this screen.** `home_shell_test.dart` asserts
/// `findsOneWidget`, not `findsWidgets`, so a second copy would fail it — which
/// is the right way round: a pack key repeated twice on one screen reads as two
/// different things.
///
/// Shown in two places and never both at once. The bar's action slot while a card
/// is on screen, and under the sentence while an empty pack or a loading read is
/// showing — those two states replace the body, and the bar's own AppBar does not
/// come with them.
class _PackKeyBadge extends StatelessWidget {
  const _PackKeyBadge({required this.packKey});

  final String packKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Text(
        // The em dash is `home_screen.dart`'s stand-in for a key the shell has
        // not resolved yet. A pack key is a Latin run, so it names Inter and asks
        // for LTR explicitly rather than inheriting Tajawal's own Latin — the
        // same call `_PackPill` and `_Header` make.
        packKey.isEmpty ? '—' : packKey,
        textDirection: TextDirection.ltr,
        style: AppText.latin.copyWith(fontSize: AppText.caption, color: secondary),
      ),
    );
  }
}

/// Shown while the pack size is being read, and again between that and the first
/// card being dealt. §4ج draws neither state; a sentence is what this app uses
/// everywhere else for "not yet" (`stats_screen.dart`'s `جارٍ التحميل…`,
/// `quiz_screen.dart`'s loading line).
const String _loading = 'جارٍ التحميل…';