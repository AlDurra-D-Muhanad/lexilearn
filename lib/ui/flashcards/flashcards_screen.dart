import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/ui/home_shell.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/wallpaper/nature_photo.dart';
import 'package:lexilearn/ui/wallpaper/nature_rotation.dart';
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
  const FlashcardsScreen({
    super.key,
    required this.packKey,
    this.packTitle = '',
    this.wallpaperSeed,
  });

  /// Seeds the rotation that chooses which photograph the card's panel opens
  /// on. **Null means the app's own behaviour** - a fresh [Random], so two
  /// sessions begin on different photographs.
  ///
  /// The same seam `FlashcardController.random` already is, and for the same
  /// reason: `golden_test.dart` photographs this screen, and a reference image
  /// that shows a different photograph on every regeneration is a reference
  /// nobody can compare against.
  final int? wallpaperSeed;

  /// The pack the deck deals from. Empty until `HomeShell` resolves it, and
  /// empty for good when nothing is installed.
  final String packKey;

  /// The pack's **name**, for the badge that names it.
  ///
  /// **The name, never the key.** The key is `dictionary_en_ar` - an
  /// identifier, and this badge is in front of the user. The shell resolves it
  /// with the pack list it reads at start-up and hands it down.
  final String packTitle;

  @override
  Widget build(BuildContext context) {
    final injected = context.read<FlashcardController?>();
    if (injected != null) {
      return _InjectedDeck(
        controller: injected,
        packKey: packKey,
        packTitle: packTitle,
        wallpaperSeed: wallpaperSeed,
      );
    }
    return _DeckOwner(
      packKey: packKey,
      packTitle: packTitle,
      wallpaperSeed: wallpaperSeed,
    );
  }
}

/// The screen with a controller handed in from outside.
///
/// **The pack's name comes with the widget**, so the injected path draws the
/// same badge the app's own path does, and the badge never falls back to the
/// key.
class _InjectedDeck extends StatelessWidget {
  const _InjectedDeck({
    required this.controller,
    required this.packKey,
    required this.packTitle,
    this.wallpaperSeed,
  });

  final FlashcardController controller;
  final String packKey;
  final String packTitle;
  final int? wallpaperSeed;

  @override
  Widget build(BuildContext context) => _DeckBody(
        controller: controller,
        packKey: packKey,
        packTitle: packTitle,
        wallpaperSeed: wallpaperSeed,
      );
}

/// Owns the controller for the app's path, where nothing else provides one.
class _DeckOwner extends StatefulWidget {
  const _DeckOwner({
    required this.packKey,
    required this.packTitle,
    this.wallpaperSeed,
  });

  final String packKey;

  /// The pack's display name, for the badge.
  final String packTitle;

  final int? wallpaperSeed;

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
        packTitle: widget.packTitle,
        // This notice replaces the whole screen, so there is no AppBar to carry
        // the pack's name and this is the only place it can be named.
        showPackName: true,
      );
    }
    return _DeckBody(
      controller: controller,
      packKey: widget.packKey,
      packTitle: widget.packTitle,
      wallpaperSeed: widget.wallpaperSeed,
    );
  }
}

/// The screen, rebuilt whenever the controller notifies.
class _DeckBody extends StatelessWidget {
  const _DeckBody({
    required this.controller,
    required this.packKey,
    required this.packTitle,
    this.wallpaperSeed,
  });

  final FlashcardController controller;

  final int? wallpaperSeed;

  /// Shown in the bar's action slot and in the empty-pack notice.
  ///
  /// Read from the widget rather than from the controller so that an **injected**
  /// controller still names the pack it is drawing from - the name is a fact
  /// about the screen, not about the deal, and the shell's own test asserts it
  /// on every destination whichever controller happens to be driving the card.
  final String packKey;

  /// The pack's display name, for the badge.
  final String packTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: controller,
      // `ShellBackToHome` is this destination's share of the app's back button:
      // Android's back returns to `الرئيسية` rather than closing the app, which is
      // what the user asked for and what `HomeShell` documents. See that widget.
      builder: (context, _) => ShellBackToHome(
        child: Scaffold(
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
          // four destinations, and `test/ui/home_shell_test.dart` asserts the
          // pack is *visible* on every one of them - "what proves the shell
          // threads state around rather than merely swapping four widgets". The
          // placeholder this screen replaces met that with a pill in the body,
          // and the artwork has no room for one: its header is the title, a back
          // arrow and the progress row, and nothing else.
          //
          // The actions slot is where this app already puts a run that is metadata
          // rather than chrome, and it leaves the artwork's body exactly as drawn.
          //
          // **The overflow menu joins the badge here rather than replacing it.**
          // The artwork's header is the title, a back arrow and the progress row,
          // and this app already spends the actions slot on the one thing the
          // artwork has no room for; the menu is the second thing it has no room
          // for, and dropping either to make room would be a worse trade than a
          // bar that is 48px wider than the mock. The menu itself is the same
          // widget on all four destinations - see `AppOverflowMenu`.
          actions: <Widget>[
            _PackKeyBadge(title: packTitle),
            const AppOverflowMenu(),
          ],
          ),
          body: SafeArea(child: _body(context, theme, isDark)),
        ),
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
        return _DeckNotice(message: _loading, packTitle: packTitle);
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
          packTitle: packTitle,
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
                  Expanded(
                    child: _Card(
                      controller: controller,
                      entry: card,
                      wallpaperSeed: wallpaperSeed,
                    ),
                  ),
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
    final fill = AppColors.accentInk(isDark);
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

/// The card: **the user's photograph** as the header, and the word with its
/// pronunciation and its Arabic beneath it.
///
/// **One surface, not two.** In the artwork the illustrated panel and the white
/// panel under it share an edge — the illustration's bottom corners are square
/// and the word card's top edge runs straight across beneath it — so they are a
/// single rounded unit here, and a second `AppSurface` between them would put a
/// hairline across a picture.
///
/// **The photograph is the artwork's own image, and it is a `StatefulWidget`
/// panel rather than an `Image`.** §4ج names «صورة طبيعة مروسة», a hand-drawn
/// nature image, and `docs/design/brand-reference.png` draws a mountain lake;
/// what it draws is a *slot*, and the slot is what this screen owns — where the
/// image goes, how tall it is, and that it is the card's header. It used to hold
/// a brand wash and `Icons.landscape_rounded` there because the repository had
/// no image asset and photographs were out of scope by user decision. Both
/// reasons are gone: `assets/wallpapers/` now carries the user's own files.
/// **The glyph is gone with them**, and `test/ui/flashcards_screen_test.dart`
/// asserts it does not come back.
class _Card extends StatelessWidget {
  const _Card({
    required this.controller,
    required this.entry,
    this.wallpaperSeed,
  });

  final FlashcardController controller;
  final VocabEntry entry;

  final int? wallpaperSeed;

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
              child: _NaturePanel(
                entryId: entry.id,
                wallpaperSeed: wallpaperSeed,
              ),
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
      AppColors.accentInk(isDark);
}

/// The card's header: **the user's own photograph**, at the artwork's
/// proportion, with nothing drawn on it.
///
/// **This is the slot the old glyph occupied, and it is a drop-in because the
/// panel was already 2:1.** `AspectRatio(_natureAspect)` at line 478 of this file
/// is `2`, and every staged file measures **1080 x 540 — 2.0000:1** — so
/// `BoxFit.cover` trims **nothing at all** here and no photograph is ever
/// distorted. That is the whole reason a single 2:1 crop could serve both
/// surfaces.
///
/// **No scrim, and that is measured rather than asserted.** There is no ink
/// anywhere in this panel: the term, its pronunciation and its meaning are on
/// the surface *below* it, which is why the word card is a separate `Expanded`
/// and not an overlay. `test/ui/flashcards_screen_test.dart` asserts there is no
/// scrim in this panel, so the next person to add one has to argue with a red.
///
/// **The photograph changes on every card-to-card transition**, which is what
/// the user asked for: «في نافذة البطاقات تتبدل عند كل انتقال من بطاقة لأخرى».
/// That is **event-driven, not timed** — `interval: null`, no `Timer` at all —
/// so a card the user is reading does not change underneath them. See
/// `NatureRotation` for why Home and this panel are two instances of one class.
class _NaturePanel extends StatefulWidget {
  const _NaturePanel({required this.entryId, this.wallpaperSeed});

  /// Seeds this panel's rotation. See `FlashcardsScreen.wallpaperSeed`.
  final int? wallpaperSeed;

  /// The id of the card this panel is under.
  ///
  /// **Compared, not used.** A card transition is the moment the value changes,
  /// and `id` rather than the entry itself because `VocabEntry` has no
  /// identity — two equal entries from different rows would compare equal and
  /// the photograph would not move.
  final String entryId;

  @override
  State<_NaturePanel> createState() => _NaturePanelState();
}

class _NaturePanelState extends State<_NaturePanel> {
  /// **Event-driven, so `interval` is null and no `Timer` is ever created.**
  ///
  /// Built on the first `didChangeDependencies` rather than as a `late final`
  /// field, for the reason `_HomeScreenState` records: `initState` cannot read
  /// the theme, so a field initialiser would have to guess one, and correcting
  /// it afterwards draws the starting index **twice** — once per set — which is
  /// invisible on a device and makes a seeded rotation unreproducible.
  NatureRotation? _rotation;

  /// Never null by the time `build` runs: `didChangeDependencies` runs first.
  NatureRotation get rotation => _rotation!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The panel is rebuilt on every controller notification, so this is where
    // the set follows the theme. Idempotent, so the repeated calls are free.
    //
    // **No lifecycle observer here, and that is not an oversight.** With
    // `interval: null` there is no timer to pause, and `NatureRotation` only
    // registers itself with `WidgetsBinding` when it owns one — so an observer
    // on this state would be a no-op callback that only exists to be a
    // `didChangeAppLifecycleState` someone has to reason about.
    final brightness = Theme.of(context).brightness;
    final existing = _rotation;
    if (existing == null) {
      _rotation = NatureRotation(
        brightness: brightness,
        random: widget.wallpaperSeed == null ? null : Random(widget.wallpaperSeed!),
      );
      return;
    }
    existing.brightness = brightness;
  }

  @override
  void didUpdateWidget(_NaturePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // **The card-to-card transition, and the only thing that moves this
    // panel.** Not `reveal()`, which re-renders the whole card and changes
    // nothing about which card it is — hence the comparison being on the id.
    if (oldWidget.entryId != widget.entryId) rotation.advance();
  }

  @override
  void dispose() {
    _rotation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: rotation,
      builder: (context, _) => NaturePhoto(
        assetPath: rotation.assetPath,
        nextAssetPath: rotation.nextAssetPath,
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
    return SizedBox(
      height: _actionHeight,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          // **The gold, as a fill, and the gold's own ink on it.** The primary
          // is a fill in the new identity and the ink on it is the app's
          // darkest navy — **9.90 : 1** in both modes, and the same gold in
          // both, because the light palette is the same system inverted.
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.onGold,
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
    final ink = AppColors.accentInk(isDark);
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
    final colour = AppColors.accentInk(isDark);
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
    final ink = AppColors.accentInk(isDark);

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
    required this.packTitle,
    this.supporting,
    this.showPackName = false,
  });

  final String message;
  final String? supporting;

  /// Named here as well as in the bar, because the bar is not always on screen:
  /// [_DeckOwnerState.build] returns a notice *instead of* [_DeckBody], so there
  /// is no Scaffold and no AppBar and nothing else would name the pack.
  final String packTitle;

  /// **Exactly one place on the screen names the pack.**
  /// `home_shell_test.dart` asserts `findsOneWidget`, not `findsWidgets`. A notice
  /// reached through [_DeckBody] already has the bar's badge above it, and this
  /// widget is *inside* that Scaffold — so drawing a second one there found two
  /// copies and failed the assertion. `true` only for the notice that replaces the
  /// whole screen.
  final bool showPackName;

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
            if (showPackName) ...<Widget>[
              const SizedBox(height: AppSpacing.m),
              _PackKeyBadge(title: packTitle),
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
  const _PackKeyBadge({required this.title});

  /// The pack's display name, or the empty string while it is resolving.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    // The name may be Arabic and it may be Latin, and the direction is the
    // paragraph's - the same rule the pack list applies to a pack's title.
    final isArabic = _writesArabic(title);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Text(
        // The em dash is `home_screen.dart`'s stand-in for a pack the shell has
        // not resolved yet. A Latin pack name asks for Inter and LTR
        // explicitly rather than inheriting Tajawal's own Latin; an Arabic one
        // keeps the ambient family and the app's direction.
        title.isEmpty ? '—' : title,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        style: isArabic
            ? theme.textTheme.bodySmall?.copyWith(color: secondary)
            : AppText.latin.copyWith(fontSize: AppText.caption, color: secondary),
      ),
    );
  }
}

/// Whether [value] carries an Arabic letter.
///
/// **The same block the app's other screens use** — U+0600 to U+06FF, plus the
/// Arabic Supplement and Extended-A blocks — so "is this Arabic?" is answered
/// the same way everywhere it is asked.
bool _writesArabic(String value) => value.runes.any(
      (rune) => (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF),
    );

/// Shown while the pack size is being read, and again between that and the first
/// card being dealt. §4ج draws neither state; a sentence is what this app uses
/// everywhere else for "not yet" (`stats_screen.dart`'s `جارٍ التحميل…`,
/// `quiz_screen.dart`'s loading line).
const String _loading = 'جارٍ التحميل…';