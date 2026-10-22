import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

import 'quiz_controller.dart';

/// The chrome, in Arabic — see `quiz_screen.dart` for why.
const String _title = 'انتهت الجلسة';

/// The line under the title.
///
/// The user's own instruction was «عدل شاشة النتائج الى مثل new result
/// window.png» — adjust the results screen to be like the reference image — and
/// this line is in that image, under the title.
const String _subtitle = 'أحسنت! لقد أتممت جلسة التعلم بنجاح';

/// The line above the score, between the two gold rules.
const String _scoreLabel = 'إجابة صحيحة من';

/// The nested card's heading.
const String _accuracyLabel = 'نسبة الدقة';

/// The line under the accuracy card, with the star.
const String _keepPractising = 'استمر في الممارسة';

/// The note under that line.
const String _keepPractisingNote = 'كل جلسة تقريكك من إتقان اللغة';

/// **The gold pill's label, and it is the reference's wording.**
///
/// The reference reads «العودة إلى الإعدادات» — *back to the settings* — and
/// the app used to read «العودة إلى الإعداد», singular. The screen the button
/// goes back to is the setup screen, which is a page of settings.
const String _backToSetup = 'العودة إلى الإعدادات';

/// ## The measurements, and where they come from
///
/// **The authority is `new result window.png`**, the reference the user named:
/// «عدل شاشة النتائج الى مثل new result window.png». It is **852 × 1846** image
/// pixels of the **same phone shape** as the app's own reference phone
/// (1080 × 2340 at 3×, which is 360 × 780 logical), so **one image pixel is
/// 360 / 852 = 0.4225 logical pixels**.
///
/// **The scale is measured, not assumed.** Two independent features were
/// measured on both images and agree:
///
/// | what | the reference | the app's own reference image | ratio |
/// |---|---|---|---|
/// | the header's arrow | 34 image px wide | 48 image px wide at 3× = 16 logical | 2.13 |
/// | the header's title | 255 image px wide | 358 image px wide at 3× = 119 logical | 2.14 |
///
/// So the reference is the same layout at 0.4225 image-to-logical, and every
/// number below is the reference's own pixels multiplied by it.
///
/// **The constants here are the rounded, token-scale values**, and the
/// measurement they come from is in each one's own comment. The rounding is
/// deliberate: the app's own scale is 4, 8, 16, 24 and 32, and a layout built
/// on 43-pixel rules would be a layout built on a mock's fractions.
const double _cardMargin = 32;

/// The disc's diameter, measured off the reference's gold ring: **158 image
/// px**, which is 67 logical.
const double _discDiameter = 68;

/// The disc's radius, and therefore **how far the disc sits above the card's
/// top edge**.
///
/// **The disc is centred on the card's top edge, not floating above it.** The
/// reference's ring runs from y 344 to y 501 and the card's top edge is at
/// y 425 — the ring's centre is 422. So half the disc is over the card and
/// half is over the page, and the card's border is **notched** where the disc
/// crosses it.
const double _discRadius = _discDiameter / 2;

/// The disc's ring, measured at **4 image px**, which is under 2 logical.
const double _discRingWidth = 2;

/// The small gold disc that carries the tick, measured at **39 image px**,
/// which is 16.5 logical.
const double _checkDiscDiameter = 16;

/// The gold rule's thickness, measured at **2 image px**.
const double _ruleThickness = 1;

/// The gold rule's length, measured at **102 image px**, which is 43 logical.
///
/// **40, not 43.** The rule is the one thing in this row that gives way: the
/// words beside it have to fit, and «إجابة صحيحة من 2» is a longer run than
/// the rule is wide. Forty is the nearest value that is a multiple of eight.
const double _ruleLength = 40;

/// The accuracy bar's height, measured at **28 image px**, which is 12
/// logical.
///
/// **A literal, and not a value off the spacing scale.** `AppSpacing` is a
/// scale of *gaps* — 4, 8, 16, 24, 32 — and a 12 px bar is not on it. The
/// same reason `quiz_screen.dart` names its own `_progressTrackHeight`.
const double _barHeight = 12;

/// What one finished session scored.
///
/// Reached from `QuizScreen`, which swaps to this the moment the controller
/// reports the session finished. The controller is still alive and still holds
/// the counters, so nothing here is recomputed from the database.
///
/// ## The layout, and it is the reference's
///
/// The reference draws, from the top:
///
/// 1. the title, with the arrow the `AppBar` already carries;
/// 2. the subtitle;
/// 3. **a big card with a book disc overlapping its top edge**, the disc
///    ringed in gold and the card's border notched around it;
/// 4. inside the card, the line «إجابة صحيحة من 2» between two gold rules,
///    with a gold tick disc beside it;
/// 5. the score itself — **the correct count in gold, the rest in white**,
///    and very large;
/// 6. a nested card: «نسبة الدقة» with a target icon, the percentage in gold,
///    and a bar that is gold up to the percentage and the structure blue after;
/// 7. «⭐ استمر في الممارسة» with a gold star, and the note under it;
/// 8. a **gold pill** «العودة إلى الإعدادات» with an arrow.
class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        // **The arrow is the `AppBar`'s own**, and in this right-to-left app it
        // lands on the outer edge pointing the way the reference's does: the
        // reference puts its arrow to the *right* of the title, and Material's
        // leading slot is the right in RTL.
        title: const Text(_title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.m,
            0,
            AppSpacing.m,
            AppSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // **The subtitle, on the page's own margin.** The reference's
              // subtitle ends at x 800 image px, which is 338 logical — the
              // page's 16 px margin, not the card's 32.
              Text(
                _subtitle,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
              const SizedBox(height: AppSpacing.l),
              const _ResultCard(),
              const SizedBox(height: AppSpacing.l),
              const _BackToSettings(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big card, with the book disc overlapping its top edge.
///
/// **The disc and the card are one composition, and the disc is drawn last.**
/// The card is a surface with a border; the disc is a circle with a gold ring
/// and the surface's own fill. Drawing the disc over the card is what notches
/// the card's border: the border line runs into the disc and stops, and the
/// disc's ring takes its place.
class _ResultCard extends StatelessWidget {
  const _ResultCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _cardMargin - AppSpacing.m),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // **The card, pushed down by the disc's radius**, so the disc's
          // centre lands exactly on the card's top edge.
          Padding(
            padding: const EdgeInsets.only(top: _discRadius),
            child: AppSurface(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.l,
                // **The disc's own radius, plus a gap.** The disc reaches this
                // far *into* the card, so the card's content has to start
                // below it or the two would collide.
                _discRadius + AppSpacing.s,
                AppSpacing.l,
                AppSpacing.l,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _ScoreRow(),
                  const SizedBox(height: AppSpacing.l),
                  const _Score(),
                  const SizedBox(height: AppSpacing.l),
                  const _AccuracyCard(),
                  const SizedBox(height: AppSpacing.l),
                  const _KeepPractising(),
                ],
              ),
            ),
          ),
          // **The disc, on the card's top edge.**
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: _MedalDisc()),
          ),
        ],
      ),
    );
  }
}

/// The gold-ringed disc with the book in it.
///
/// **The fill is the surface's own colour, not the page's.** That is what
/// makes the card's border disappear behind it: the disc is the card's own
/// surface, so the border line that runs into it is simply covered.
class _MedalDisc extends StatelessWidget {
  const _MedalDisc();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: _discDiameter,
      height: _discDiameter,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: _discRingWidth),
      ),
      child: Center(
        // **The app's own book.** The reference draws an open book, and the
        // home screen's gold book mark is the same glyph
        // (`Icons.menu_book_rounded`) — the identity's own motif, and the
        // reference's.
        child: Icon(Icons.menu_book_rounded, color: AppColors.gold, size: 32),
      ),
    );
  }
}

/// «إجابة صحيحة من 2», between two gold rules, with the tick disc.
///
/// **The order, and it is the reference's.** Reading right to left: the gold
/// rule, the gold disc with its tick, the words, and the second gold rule.
/// The disc therefore sits between the text and the rule on its side.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = context.watch<QuizController>();

    return Row(
      children: <Widget>[
        // **The rule, first in the row and so first in the reading order**,
        // which in this app is the right-hand one.
        const _GoldRule(),
        const SizedBox(width: AppSpacing.m),
        const _CheckDisc(),
        const SizedBox(width: AppSpacing.xs),
        // **The words.** `Flexible` and not `Expanded`: the two rules are
        // fixed and the words take what is left, so the words are never
        // squeezed into a share of the row they do not fit in.
        Flexible(
          child: Text(
            // **The total is in the line**, exactly as the reference draws it:
            // «إجابة صحيحة من 2» — correct answers out of two.
            '$_scoreLabel ${controller.answeredCount}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // **The reference's own weight.** The words are 62 % of the
            // header's title — measured off the reference, their ink is 25
            // image px against the title's 40 — and `bodyMedium` is 64 % of
            // the AppBar's `titleLarge`.
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.textDark : AppColors.textLight,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        const _GoldRule(),
      ],
    );
  }
}

/// One of the two gold rules beside the score.
///
/// **The reference's own proportions**: 102 image px long and 2 image px
/// thick, which is 43 logical by 1.
class _GoldRule extends StatelessWidget {
  const _GoldRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _ruleLength,
      height: _ruleThickness,
      color: AppColors.gold,
    );
  }
}

/// The small gold disc with the tick knocked out of it.
///
/// **A solid gold circle with a dark tick**, which is the reference's: the
/// tick is the surface's own colour, the way the ink on a gold pill is the
/// app's darkest navy (`AppColors.onGold`).
class _CheckDisc extends StatelessWidget {
  const _CheckDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _checkDiscDiameter,
      height: _checkDiscDiameter,
      decoration: const BoxDecoration(
        color: AppColors.gold,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, color: AppColors.onGold, size: 12),
    );
  }
}

/// The score: **the correct count in gold, the rest in white**.
///
/// **Very large, and the two parts are not the same weight.** The reference
/// draws the correct count in the brand gold and bold, and the «/ 2» in white
/// and light — measured off the reference, the gold «1»'s stem is about a
/// third wider than the «2»'s strokes.
class _Score extends StatelessWidget {
  const _Score();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<QuizController>();
    final isDark = theme.brightness == Brightness.dark;

    return Text.rich(
      TextSpan(
        style: AppText.latinDisplay.copyWith(
          fontSize: theme.textTheme.displayMedium?.fontSize,
          color: isDark ? AppColors.textDark : AppColors.textLight,
        ),
        children: <InlineSpan>[
          // **The correct count, in the gold.**
          TextSpan(
            text: '${controller.correctCount}',
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
          // **The rest, in the body's ink.** The slash and the total.
          TextSpan(text: ' / ${controller.answeredCount}'),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
  }
}

/// The nested card: the accuracy's heading, its percentage, and its bar.
class _AccuracyCard extends StatelessWidget {
  const _AccuracyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = context.watch<QuizController>();
    final percent = (controller.accuracy * 100).round();

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                _accuracyLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              // **The target icon.** The reference draws a target with a dart
              // in it — concentric rings and a shot — which is Material's
              // `gps_fixed` and not `my_location`'s plain crosshair.
              Icon(
                Icons.gps_fixed,
                size: 20,
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            // ASCII `%`, not the Arabic `٪`: this whole run is set in
            // Inter, which carries no U+066A, so the Arabic sign would
            // render as a tofu box beside the numeral.
            '$percent%',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: AppText.latinDisplay.copyWith(
              fontSize: theme.textTheme.headlineMedium?.fontSize,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          _AccuracyBar(value: controller.accuracy),
        ],
      ),
    );
  }
}

/// The bar: **gold up to the percentage, the structure blue after**.
///
/// **It fills from the left, and that is the reference's own direction.** The
/// reference's bar is gold from its left edge to the halfway mark and the
/// structure blue from there to its right edge — measured, the gold covers
/// image x 168 to 434 of a track that runs 168 to 660, which is 54 % of it,
/// and the percentage it draws is 50 %.
///
/// The direction is therefore **pinned rather than inherited**: the bar is
/// given an explicit left-to-right direction so that the app's own
/// right-to-left layout does not mirror it. The reference is the authority for
/// this screen — the user asked for this screen to be like it — and a bar that
/// filled the other way would be a visible disagreement with the picture the
/// user is holding.
class _AccuracyBar extends StatelessWidget {
  const _AccuracyBar({required this.value});

  /// The proportion the bar is filled to, 0.0 to 1.0.
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: SizedBox(
          height: _barHeight,
          child: Stack(
            children: <Widget>[
              // **The track: the structure's own blue.**
              Container(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              // **The fill: the brand gold**, and it is the gold as a fill,
              // which is what the identity says the gold is for.
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(color: AppColors.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «⭐ استمر في الممارسة» and the note under it.
class _KeepPractising extends StatelessWidget {
  const _KeepPractising();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _keepPractising,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            // **The gold star.** The reference draws a filled five-pointed
            // star, which is Material's `star` and not `star_border`.
            const Icon(Icons.star, color: AppColors.gold, size: 20),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          _keepPractisingNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: secondary),
        ),
      ],
    );
  }
}

/// The gold pill: «العودة إلى الإعدادات» with an arrow.
///
/// **The arrow is on the far side of the text from the reader's eye**, which
/// in this app is the left, and it points the way the reference's does.
///
/// **`Icons.arrow_back` and not `Icons.arrow_forward`.** Every one of
/// Material's four arrows carries `matchTextDirection: true`, so in a
/// right-to-left app they are all mirrored: `arrow_back` is drawn pointing
/// **right**, which is the direction the reference draws. And the action *is*
/// a way back — «العودة إلى الإعدادات» is *back to the settings* — so the
/// glyph says what the label says.
class _BackToSettings extends StatelessWidget {
  const _BackToSettings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: FilledButton(
        onPressed: () {
          final navigator = Navigator.of(context);
          // `canPop` rather than an unconditional `pop`: this screen is what
          // `QuizScreen` returns, so it is the root route whenever the quiz is
          // mounted on its own, and popping the root route throws.
          if (navigator.canPop()) navigator.pop();
        },
        style: FilledButton.styleFrom(
          elevation: 0,
          // **The pill's own measurements.** The reference's is 44 logical px
          // tall, and its label is 119 logical px wide with the arrow beside
          // it — so the pill is sized to its contents and is **not** the
          // full-width action the other screens use.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l,
            vertical: AppSpacing.s,
          ),
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _backToSetup,
              style: theme.textTheme.bodyLarge?.copyWith(
                // **The ink on the gold is the app's darkest navy**, which is
                // what the identity says the ink on a gold fill is.
                color: AppColors.onGold,
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            const Icon(Icons.arrow_back, color: AppColors.onGold, size: 20),
          ],
        ),
      ),
    );
  }
}
