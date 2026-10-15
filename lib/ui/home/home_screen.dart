import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';

/// The brand's first destination.
///
/// Task 9's shell: it owns the title, the empty state and the pack plumbing, so
/// `HomeShell` compiles and the bottom bar can be tested on its own. Task 10
/// replaces the body with the greeting, the word-of-the-day card, the
/// `ابحث عن كلمة...` search field and the quick-launch grid.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.packKey,
    required this.onPackSelected,
    required this.onOpenWord,
  });

  final String packKey;
  final ValueChanged<String> onPackSelected;
  final ValueChanged<VocabEntry> onOpenWord;

  @override
  Widget build(BuildContext context) => _Placeholder(
        title: 'الرئيسية',
        icon: Icons.search,
        headline: 'ابحث عن كلمة…',
        supporting: 'كلماتك في حزمة واحدة، ابدأ من هنا.',
        packKey: packKey,
      );
}

/// Task 9's placeholder body.
///
/// Private to this file on purpose. Task 9's plan asked for one `_Placeholder`
/// per destination file rather than a shared widget, and Dart allows the same
/// private name in five files — so each screen that arrives later replaces its
/// own copy instead of editing a shared one.
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
                // The active pack, named. `HomeShell` resolves it once and hands
                // the same key to every destination, so showing it here is what
                // proves the shell threads state around rather than only
                // swapping widgets. A pack key is a Latin run, so it asks for
                // Inter explicitly instead of inheriting Tajawal's own Latin.
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
