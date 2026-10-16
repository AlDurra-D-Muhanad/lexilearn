import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/quiz_option.dart';
import 'package:lexilearn/domain/quiz_question.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

import 'quiz_controller.dart';
import 'quiz_result_screen.dart';

/// The chrome, in Arabic: the app is RTL end to end and the artwork's chrome is
/// Arabic. Only the English term being asked about is a Latin run, and it says
/// so with [AppText.latinDisplay] and an explicit LTR direction.
const String _title = 'الاختبارات';
const String _prompt = 'ما معنى هذه الكلمة؟';
const String _chooseOne = 'اختر الترجمة الصحيحة';
const String _correctBanner = 'إجابة صحيحة';
const String _wrongBanner = 'إجابة خاطئة';
const String _next = 'التالي';
const String _finish = 'إنهاء';
const String _loading = 'جارٍ التحميل…';

/// The counter row's height: the Latin caption line plus the gap under it, and
/// the thickness of the fill it sits beside.
///
/// Named rather than written as three literals at the three call sites, for the
/// same reason `_pickerHeight` is named on the setup screen: `AppSpacing` carries
/// a scale for gaps, and `AppText` one for type, and neither scale has a value
/// for a stroked track — so the numbers are pinned here once rather than
/// scattered as bare magic numbers.
const double _progressRowHeight = AppSpacing.l + AppSpacing.xs;
const double _progressTrackHeight = AppSpacing.s - AppSpacing.xs;

/// The vertical padding inside an option row.
///
/// Between `AppSpacing.s` and `AppSpacing.m`: enough for a 56px-tall target with
/// room to read. Named here for the same reason as the two above.
const double _optionVerticalPadding = AppSpacing.m - AppSpacing.xs;

/// One question: the word, four translations, and — once an answer is given —
/// whether it was right.
class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<QuizController>();
    final question = controller.question;

    // Between being pushed and the pack read answering there is no question yet
    // and the session has not finished either. Showing the result screen here
    // would open every quiz on "session complete".
    if (question == null) {
      return controller.isFinished
          ? const QuizResultScreen()
          : const _LoadingScreen();
    }

    final answered = controller.canAdvance;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text(_title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_progressRowHeight),
          child: _ProgressRow(controller: controller),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.s),
              _QuestionCard(question: question),
              const SizedBox(height: AppSpacing.m),
              if (answered) ...<Widget>[
                _FeedbackBanner(controller: controller),
                const SizedBox(height: AppSpacing.m),
              ],
              // `Expanded` rather than a scroll view: the four options are the
              // whole point of the screen and a user must be able to see all of
              // them at once. The column above is fixed-height for that reason.
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (var i = 0; i < question.options.length; i++)
                      _OptionTile(
                        index: i,
                        option: question.options[i],
                        question: question,
                        controller: controller,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              FilledButton(
                // `FilledButton` draws no elevation shadow at all, so it needs no
                // local `elevation: 0` — unlike `ElevatedButton`, whose default
                // M3 elevation this rasteriser strokes as a black keyline.
                onPressed: answered ? controller.next : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                  // A pill, like every other full-width action in the app and
                  // every action button in the artwork: the theme's default is a
                  // 20px radius, which is a shape the brand does not use.
                  shape: const StadiumBorder(),
                ),
                child: Text(controller.isLastQuestion ? _finish : _next),
              ),
              const SizedBox(height: AppSpacing.m),
            ],
          ),
        ),
      ),
    );
  }
}

/// The counter and the bar, as the artwork draws them under the flashcards
/// heading: the fraction asked on the left of the row, the fill on the rest.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.controller});

  final QuizController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: Row(
        children: <Widget>[
          Text(
            // Numerals, so Inter and LTR rather than the ambient family.
            '${controller.questionNumber} / ${controller.questionCount}',
            textDirection: TextDirection.ltr,
            style: AppText.latin.copyWith(fontSize: AppText.caption, color: secondary),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: controller.progress,
                minHeight: _progressTrackHeight,
                backgroundColor: isDark ? AppColors.borderDark : AppColors.borderLight,
                // The artwork's **dark** phone draws the progression beneath the
                // heading in the brand amber, not in the primary purple it uses
                // in light. `null` leaves the theme's value alone, which is the
                // purple `colorScheme.primary` already carries. This is the
                // accent doing the job `design_tokens.dart` says it may do —
                // filling, never body text.
                color: isDark ? AppColors.accent : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The word being asked about, on the brand surface.
///
/// The English term is the largest text on this screen, per
/// `docs/design/style-direction.md` → Typography.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final QuizQuestion question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _prompt,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            question.answer.term,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: AppText.latinDisplay.copyWith(
              fontSize: theme.textTheme.displaySmall?.fontSize,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _chooseOne,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The verdict on the answer just given, and — when it was wrong — the
/// translation that was wanted.
///
/// This is the quiz form of the artwork's «أعرف» / «لا أعرف» pairing on the
/// flashcards screen: the same reveal, reached by picking an option instead of
/// swiping.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.controller});

  final QuizController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final correct = controller.lastSelectedWasCorrect;

    return AnimatedContainer(
      // The answer reveal is a movement, so it gets the brand's fast duration —
      // `AppDurations.fast`, reserved for exactly this — rather than the
      // standard one `AppSurface` cross-fades themes with.
      duration: AppDurations.fast,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: correct ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Text(
        correct
            ? _correctBanner
            : '$_wrongBanner — الإجابة الصحيحة: ${controller.lastAnswerText}',
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: correct ? scheme.onPrimaryContainer : scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One option: a full-width button, as the artwork draws its answer choices.
///
/// **Not a lettered chip.** The original printed `a:` / `b:` / `c:` / `d:`
/// before each option; the artwork has no lettering here at all, and a column of
/// lettered chips is what a left-to-right mock of an Arabic list looks like. So
/// the options are four full-width rows of Arabic, which is also why the answer
/// is a tap target big enough to hit without reading it.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.index,
    required this.option,
    required this.question,
    required this.controller,
  });

  final int index;
  final QuizOption option;
  final QuizQuestion question;
  final QuizController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // "Answered" means the user has committed, so feedback is revealed;
    // "selected" means *this* is the row they chose. They are different things:
    // a wrong pick goes red while the genuinely right option goes green, and
    // `answerCorrectness` alone cannot tell the two apart.
    final answered = controller.canAdvance;
    final selected = controller.isSelectedOption(index);
    final isRight = question.isCorrect(index);

    var fill = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    var border = isDark ? AppColors.borderDark : AppColors.borderLight;
    var width = 1.0;
    var ink = scheme.onSurface;
    if (answered && isRight) {
      // The brand's success/insets tokens, not `colorScheme.primary`: "that was
      // right" must read the same in either brightness, and the theme's primary
      // is a different colour from the one the flashcards screen draws success
      // in. Measured against the brand: `#16A34A` on white is 3.3:1 and on the
      // dark background 5.5:1, both over the 3:1 a 2px border and an icon need.
      fill = scheme.primaryContainer;
      border = AppColors.successLight;
      width = 2;
      ink = scheme.onPrimaryContainer;
    } else if (answered && selected) {
      fill = scheme.errorContainer;
      border = AppColors.errorLight;
      width = 2;
      ink = scheme.onErrorContainer;
    } else if (answered) {
      // The options that were neither picked nor right recede rather than
      // vanish: they were real options and the user may be reading them.
      ink = scheme.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: border, width: width),
          // The same composition `AppSurface` uses, and for the same reason: a
          // bare `Card` would trade this for Material's elevation shadow, which
          // the test rasteriser strokes as an opaque black keyline. It cannot be
          // an `AppSurface` because a supplied `fill` paints the border in the
          // fill colour, and this row's border is the one thing on screen that
          // says whether the answer was right.
          boxShadow: isDark ? AppShadows.none : AppShadows.light,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: answered ? null : () => controller.answer(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: _optionVerticalPadding,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      option.text,
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.titleMedium?.copyWith(color: ink),
                    ),
                  ),
                  if (answered && isRight)
                    const Icon(Icons.check_circle, color: AppColors.successLight),
                  if (answered && selected && !isRight)
                    const Icon(Icons.cancel, color: AppColors.errorLight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pack read the controller issued when it was created, still in flight.
///
/// **A static label rather than a `CircularProgressIndicator`.** An indeterminate
/// progress indicator schedules frames forever, so `pumpAndSettle` never settles
/// while one is on screen — and every route onto this screen is a push followed
/// by a `pumpAndSettle`, so a spinner here hangs the very tests that drive the
/// transition this state exists for. What it is waiting on is one indexed SQLite
/// query over an already-installed pack, so a static line names the state for as
/// long as it lasts and the question simply replaces it.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text(
            _loading,
            style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
          ),
        ),
      ),
    );
  }
}
