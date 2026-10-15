import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';

/// The brand's third destination: setting up and running a quiz.
///
/// Task 9's shell. Task 11 replaces the body with the pack picker and the quiz
/// options.
class QuizSetupScreen extends StatelessWidget {
  const QuizSetupScreen({
    super.key,
    required this.packKey,
    required this.onPackSelected,
  });

  final String packKey;
  final ValueChanged<String> onPackSelected;

  @override
  Widget build(BuildContext context) => _Placeholder(
        title: 'الاختبارات',
        icon: Icons.quiz_outlined,
        headline: 'لا يوجد اختبار جاهز',
        supporting: 'اختر الحزمة وعدد الأسئلة ثم ابدأ.',
        packKey: packKey,
      );
}

/// Task 9's placeholder body. Private to this file — see `home_screen.dart`.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.icon,
    required this.headline,
    required this.supporting,
    required this.packKey,
  });

  final String title;
  final IconData icon;
  final String headline;
  final String supporting;
  final String packKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(title),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: AppSurface(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 40,
                  color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                ),
                const SizedBox(height: AppSpacing.m),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  supporting,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
                ),
                const SizedBox(height: AppSpacing.l),
                // The pack the quiz would be drawn from. Latin run, so Inter by
                // name rather than inheriting Tajawal's Latin.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.m,
                    vertical: AppSpacing.s,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Text(
                    packKey.isEmpty ? '—' : packKey,
                    textDirection: TextDirection.ltr,
                    style: AppText.latin.copyWith(fontSize: 13, color: secondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
