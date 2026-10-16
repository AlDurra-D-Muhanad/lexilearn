import 'package:flutter/material.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';

/// The brand's **fourth** destination: `المزيد`, reached from the bottom bar.
///
/// It is the fourth of four, not a fifth thing that statistics belongs to.
/// `docs/design/brand-reference.png` draws exactly four items in the bar —
/// الرئيسية, البطاقات, الاختبارات, المزيد — in the light phone and again in the
/// dark one, and Amendment 1 in `docs/design/style-direction.md` corrects an
/// earlier five-destination draft back to four. **Statistics is not on that bar
/// and is not here either**: it is reached from the `إحصائياتك` tile in Home's
/// 2×2 quick-launch grid, which pushes `StatsScreen` the way `المفضلة` pushes
/// `FavoritesScreen`. See `lib/ui/stats/stats_screen.dart` and
/// `lib/ui/home/home_screen.dart`.
///
/// Task 9's shell. Task 13 replaces the body with that page and owns switching
/// the active pack through [onPackSelected].
class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.packKey,
    required this.onPackSelected,
  });

  final String packKey;
  final ValueChanged<String> onPackSelected;

  @override
  Widget build(BuildContext context) => _Placeholder(
        title: 'المزيد',
        icon: Icons.tune_outlined,
        headline: 'لا يوجد شيء هنا بعد',
        // Task 13 owns this string along with the rest of the body. It used to
        // say "statistics, packs and backup live on this page", which stopped
        // being true in Task 12: statistics is on the Home grid tile, not here.
        // Left as a placeholder's own text until Task 13 writes the real page —
        // it is not a statement about where statistics can be found.
        supporting: 'الحزم والنسخ الاحتياطي في هذه الصفحة.',
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
                // The pack this page would report on. Latin run, so Inter by
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
