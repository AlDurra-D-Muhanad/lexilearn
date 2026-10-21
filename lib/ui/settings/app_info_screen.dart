import 'package:flutter/material.dart';
import 'package:lexilearn/design/app_version.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/link/external_link.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

/// The chrome, in Arabic, as every other screen in this app is.
const String _title = 'معلومات التطبيق';
const String _appName = 'LexiLearn';
const String _whatItIs = 'تطبيق لتعلّم الكلمات الإنجليزية وترجمتها إلى العربية.';
const String _developerLabel = 'المطور';
const String _offlineLabel = 'يعمل دون إنترنت';
const String _offlineBody = 'لا يطلب التطبيق أي أذونات، ولا يتصل بأي خادم. '
    'كل بياناتك محفوظة على جهازك فقط.';
const String _versionLabel = 'الإصدار';
const String _contactLabel = 'تواصل معي على تيلغرام';
const String _contactBody = 'MUHANAD_D';

/// The developer's name, as the user gave it.
///
/// **Written once, here, and nowhere else in `lib/`.** It is the one fact in the
/// app that no other screen has any reason to know, so it lives with the screen
/// that shows it. Pinned by `test/ui/app_settings_test.dart` -> *the about screen
/// names the developer*, which fails if the string is edited or the row is
/// removed, which is what a comment cannot do.
///
/// Deliberately **not** read from `pubspec.yaml`, from
/// `package_info_plus`, or from `AndroidManifest.xml`. Each of those would mean a
/// second source of truth or a new dependency for a name that changes about once
/// a year, and none of them is what the user sees when they tap the menu.
const String developerName = 'Muhanad';

/// What the overflow menu's `معلومات التطبيق` opens.
///
/// **A pushed route, and that is how every other full screen in this app is
/// reached** — `WordDetailScreen`, `FavoritesScreen` and `StatsScreen` are all
/// `Navigator.push`ed, and a modal sheet for a static page of text would be the
/// one screen in the app that behaves differently from its siblings for no reason.
///
/// Everything on it is static. There is no controller, no read and no injected
/// state, so the screen is pumpable in a test with nothing above it at all —
/// except the Telegram row, which needs the [OpenExternalUrl] provider
/// `LexiLearnApp` installs, exactly like every other screen that uses one.
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    // Read once, not per row: the launcher is a provider, and a `watch` would
    // rebuild this whole page if the seam were ever swapped.
    final openUrl = context.read<OpenExternalUrl>();

    return Scaffold(
      appBar: AppBar(
        // On the background, for the reason `MoreScreen`'s is: Material's default
        // `surfaceContainer` would draw a second tone across the top of a screen
        // whose only surfaces are the cards below it.
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        surfaceTintColor: Colors.transparent,
        title: const Text(_title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.m),
          children: <Widget>[
            AppSurface(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The name, in the app's Latin face: it is a brand mark, not a
                  // sentence, so `AppText.latinDisplay` rather than the ambient
                  // Arabic family — the same rule every pack key follows.
                  //
                  // **The accent ink, not the primary.** The primary is the
                  // gold, and the gold is a *fill*: it measures 1.95 : 1 on the
                  // light surface this name sits on, so light mode carries the
                  // body ink here and dark mode carries the gold.
                  Text(
                    _appName,
                    textDirection: TextDirection.ltr,
                    style: AppText.latinDisplay
                        .copyWith(color: AppColors.accentInk(isDark), fontSize: 28),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(_whatItIs, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            _InfoCard(
              rows: <_InfoRow>[
                _InfoRow(
                  label: _developerLabel,
                  // Latin run: a person's name, and Inter is this app's Latin.
                  value: developerName,
                  latin: true,
                ),
                _InfoRow(
                  label: _offlineLabel,
                  value: _offlineBody,
                ),
                // **The version, and it is not a string anybody wrote here.**
                //
                // `AppVersion.version` is a compile-time constant read out of
                // the environment, and `tool/build.dart` fills that environment
                // in from `pubspec.yaml`. So there is exactly one copy of the
                // version — the manifest — and the screen cannot drift from it.
                // `test/design/app_version_test.dart` reads the manifest off disk
                // and fails if the two disagree.
                _InfoRow(
                  label: _versionLabel,
                  value: AppVersion.version,
                  latin: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            // The same contact the overflow menu offers, in words rather than as
            // a menu entry, because a person who came here to ask who made the
            // app should not have to go back and open a menu to find out.
            _ContactCard(
              secondary: secondary,
              onTap: () => openUrl(telegramContactUri),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label and a value, as one row on a card.
class _InfoRow {
  const _InfoRow({required this.label, required this.value, this.latin = false});

  final String label;
  final String value;
  final bool latin;
}

/// A card of label/value rows.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final row in rows) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Text(
                    row.label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: secondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.value,
                    textDirection: row.latin ? TextDirection.ltr : TextDirection.rtl,
                    style: row.latin
                        ? theme.textTheme.bodyMedium?.merge(AppText.latin)
                        : theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (row != rows.last) const SizedBox(height: AppSpacing.m),
          ],
        ],
      ),
    );
  }
}

/// The Telegram contact, as a whole-card tap target.
///
/// **An `AppSurface` with an `InkWell`, not a `ListTile`.** Every other card in
/// this app is an `AppSurface`, and the app-wide rule
/// (`docs/engineering-standards.md` §6) is that a card is never a bare `Card`;
/// `ListTile` inside one would put a second surface inside the first.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.secondary, required this.onTap});

  final Color secondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      container: true,
      button: true,
      label: _contactLabel,
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Row(
            children: <Widget>[
              // The Telegram mark itself, because the user asked for a Telegram
              // icon and not a generic share glyph. `Icons.telegram` is the
              // brand's own paper-plane glyph in the Material set.
              //
              // **The accent ink, and the reason it is not the gold in light
              // mode**: the gold measures 1.95 : 1 on this surface, and the
              // icon is the one thing on the card the user has to be able to
              // see.
              Icon(
                Icons.telegram,
                color: AppColors.accentInk(isDark),
                size: 28,
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_contactLabel, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      // Latin run: a handle, and LTR so the leading `@` is not
                      // reordered to the end of the line by the ambient RTL.
                      '@$_contactBody',
                      textDirection: TextDirection.ltr,
                      style: AppText.latin
                          .copyWith(color: secondary, fontSize: AppText.caption),
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