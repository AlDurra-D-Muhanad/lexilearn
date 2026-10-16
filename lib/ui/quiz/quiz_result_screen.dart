import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

import 'quiz_controller.dart';

/// The chrome, in Arabic — see `quiz_screen.dart` for why.
const String _title = 'انتهت الجلسة';
const String _scoreLabel = 'إجابة صحيحة من';
const String _accuracyLabel = 'نسبة الدقة';
const String _backToSetup = 'العودة إلى الإعداد';

/// What one finished session scored.
///
/// Reached from `QuizScreen`, which swaps to this the moment the controller
/// reports the session finished. The controller is still alive and still holds
/// the counters, so nothing here is recomputed from the database.
class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<QuizController>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    // Accuracy, not progress. `progress` is how far through the session the user
    // got, which on the last question is always 1 — printing that as a
    // percentage correct tells a user who got one of two right that they scored
    // 100%.
    final percent = (controller.accuracy * 100).round();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: const Text(_title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: AppSurface(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '$_scoreLabel ${controller.answeredCount}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  // Numerals, so Inter and LTR.
                  Text(
                    '${controller.correctCount} / ${controller.answeredCount}',
                    textDirection: TextDirection.ltr,
                    style: AppText.latinDisplay.copyWith(
                      fontSize: theme.textTheme.displayMedium?.fontSize,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Text(
                    _accuracyLabel,
                    style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    // ASCII `%`, not the Arabic `٪`: this whole run is set in
                    // Inter, which carries no U+066A, so the Arabic sign would
                    // render as a tofu box beside the numeral.
                    '$percent%',
                    textDirection: TextDirection.ltr,
                    style: AppText.latinDisplay.copyWith(
                      // The brand purple: this is the one place a number is the
                      // headline rather than a label. Never `AppColors.accent` —
                      // amber fails contrast as light-mode body text.
                      fontSize: theme.textTheme.headlineMedium?.fontSize,
                      color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  FilledButton(
                    // `canPop` rather than an unconditional `pop`: this screen
                    // is what `QuizScreen` returns, so it is the root route
                    // whenever the quiz is mounted on its own, and popping the
                    // root route throws.
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      if (navigator.canPop()) navigator.pop();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                      // A pill, like every other full-width action in the app
                      // and every action button in the artwork; the theme's
                      // default is a 20px radius, which the brand does not use.
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(_backToSetup),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
