import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';
import '../../domain/custom_dictionary.dart';
import '../theme/app_surface.dart';
import 'add_custom_word_screen.dart';
import 'custom_words_screen.dart';

/// The chrome under the title, in Arabic.
const String _subtitle =
    'أنشئ قاموسك الشخصي واحفظ كلماتك المفضلة لتتعلمها في أي وقت.';
const String _addTitle = 'إضافة كلمة';
const String _addSubtitle = 'أضف كلمة جديدة إلى قاموسك الخاص.';
const String _wordsTitle = 'الكلمات المضافة';
const String _wordsSubtitle = 'عرض وإدارة كلماتك المحفوظة.';
const String _backTooltip = 'رجوع';

/// The landing screen of the user's own dictionary: the two doors, and nothing
/// else.
///
/// **The class name and its `const` constructor are the contract the Home tile
/// compiles against**, so this file replaces the stub in place rather than
/// moving the screen.
///
/// **No bottom bar.** This is a pushed route, not a bar destination: Home's
/// `قاموسك الخاص` tile pushes it and the back control is the only way out. The
/// artwork for the add screen draws the bar with `الاختبارات` selected, but the
/// bar belongs to `HomeShell` — a pushed route that drew one would be a second
/// navigation surface, and `FavoritesScreen` and `StatsScreen` are the app's
/// two precedents for pushed screens without it.
///
/// **The layout is the drawing's, right to left.** The words list is the
/// right-hand card and «إضافة كلمة» the left, as the RTL drawing has them, and
/// the chevrons point left because that is forward in this app.
///
/// **The one departure is the back control.** The landing drawing puts it on
/// the left while the other two drawings put it on the right; every pushed
/// screen in this app — `FavoritesScreen`, `StatsScreen` — puts it on the
/// right, the start edge of a right-to-left layout, and this screen follows
/// the app.
class CustomDictionaryScreen extends StatelessWidget {
  const CustomDictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Header(),
              const SizedBox(height: AppSpacing.s),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
              const SizedBox(height: AppSpacing.l),
              // One height for both cards, so the pair reads as a pair even
              // though one description is a line longer than the other.
              SizedBox(
                height: 280,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _LandingCard(
                        icon: Icons.menu_book_rounded,
                        title: _wordsTitle,
                        subtitle: _wordsSubtitle,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CustomWordsScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: _LandingCard(
                        icon: Icons.add_rounded,
                        title: _addTitle,
                        subtitle: _addSubtitle,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AddCustomWordScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The back chevron, the gold open book and the title.
///
/// **The title sits against the start edge — the right in this app — with the
/// book after it**, which is the drawing's own order. A `Stack` keeps the back
/// control on that edge without the title sharing its space; the padding is
/// what stops the two from meeting.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 56, end: 56),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      customDictionaryTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Icon(
                    Icons.menu_book_rounded,
                    size: 30,
                    color: AppColors.accentInk(isDark),
                  ),
                ],
              ),
            ),
          ),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: _BackButton(),
          ),
        ],
      ),
    );
  }
}

/// One of the two doors: a gradient card, a badge, two lines and a chevron.
///
/// The whole card is the tap target, and `Semantics(button: true)` says so to a
/// screen reader. The gradient is painted with `Ink` rather than a bare
/// `DecoratedBox`, so the ripple a tap produces is drawn **above** the ramp
/// instead of underneath it where it would be invisible.
class _LandingCard extends StatelessWidget {
  const _LandingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final radius = BorderRadius.circular(AppRadii.lg);

    return Semantics(
      container: true,
      button: true,
      label: title,
      child: AppSurface(
        borderRadius: radius,
        // A filled surface drops the hairline unless it names one; the artwork
        // draws a visible blue outline around both cards, so it names one.
        fill: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderColor: isDark ? AppColors.borderDark : AppColors.borderLight,
        padding: EdgeInsets.zero,
        child: Ink(
          // One pixel inside the surface's radius, so the ramp does not paint
          // over the hairline the `AppSurface` draws.
          decoration: BoxDecoration(
            gradient: AppGradients.card(isDark),
            borderRadius: BorderRadius.circular(AppRadii.lg - 1),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                children: <Widget>[
                  const Spacer(flex: 2),
                  _Badge(icon: icon),
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                  const Spacer(flex: 3),
                  Icon(
                    // The drawing's `›` is a left-to-right mock. The app reads
                    // right to left, so the chevron points left, the way the
                    // eye leaves the card.
                    Icons.chevron_left_rounded,
                    size: 24,
                    color: AppColors.accentInk(isDark),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular badge around a card's glyph, on the brand's icon ramp.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: AppGradients.iconBadge(isDark),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
        ),
      ),
      child: Icon(icon, size: 28, color: AppColors.accentInk(isDark)),
    );
  }
}

/// The back control, in the app's reading direction.
///
/// `maybePop` rather than `pop`: mounted on its own in a test there is no route
/// underneath, and a screen that threw on a back tap because it was the root
/// would be a screen that cannot be mounted alone.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _backTooltip,
    onPressed: () => Navigator.of(context).maybePop(),
    // `chevron_right` is the back chevron in a right-to-left app: it points
    // towards where the user came from, which is the right edge.
    icon: const Icon(Icons.chevron_right_rounded, size: 32),
  );
}
