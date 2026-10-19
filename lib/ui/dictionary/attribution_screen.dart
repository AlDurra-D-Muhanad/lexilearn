import 'package:flutter/material.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/link/external_link.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

/// The chrome, in Arabic.
const String _title = 'المصادر والنسب';
const String _licenseHeading = 'الترخيص';
const String _sourcesHeading = 'المصادر';
const String _countsHeading = 'الأرقام';
const String _openLink = 'فتح الرابط';
const String _upstreamLabel = 'المشروع المصدر';

/// The dictionary's licence and its sources, as `meta` records them.
///
/// **This screen is a licence obligation, not a courtesy.** The dictionary is
/// **CC-BY-SA-4.0**, and that licence obliges an application that ships it to
/// name the licence, to name its sources, and to carry the attribution.
///
/// **The three sources do not share one licence, and the screen does not
/// pretend they do.** `pwn30` is `WordNet-3.0` — a separate and permissive
/// licence, not share-alike; `omw-arb` is `CC-BY-SA-3.0`; `wikt-en-ar` is
/// `CC-BY-SA-4.0`. One share-alive line for all three would misstate two of
/// them, and the upstream's own licensing rule is that an adapter must
/// determine a licence from the data rather than assume one.
///
/// **Every word on this screen comes out of `meta`.** The build tool writes
/// the upstream project, its URL and each source's licence and verbatim
/// credit into the database, from the upstream project's own configuration —
/// `docs/dictionary-attribution.md` records where each string came from.
/// Nothing here is paraphrased and nothing is invented: a fabricated
/// paragraph is not a source.
///
/// **The stale `attributionFile` path is not here.** It pointed at a file on
/// the machine that generated the data; it exists nowhere else, and a path
/// that cannot be resolved is not an attribution.
class AttributionScreen extends StatelessWidget {
  const AttributionScreen({super.key, required this.attribution});

  /// Everything the licence obliges the screen to show, read out of `meta`.
  final DictionaryAttribution attribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final openUrl = context.read<OpenExternalUrl>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(_title),
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.m),
          children: <Widget>[
            AppSurface(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    attribution.name,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleLarge
                        ?.merge(AppText.latinDisplay)
                        .copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    attribution.source,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodySmall
                        ?.merge(AppText.latin)
                        .copyWith(color: secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(_licenseHeading, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            AppSurface(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    attribution.license,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleSmall?.merge(AppText.latin),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    attribution.licenseUrl,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodySmall
                        ?.merge(AppText.latin)
                        .copyWith(color: secondary),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: () => _open(context, openUrl),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(_openLink),
                      style: OutlinedButton.styleFrom(
                        elevation: 0,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  // **The upstream project, by name and URL.** The licence
                  // obliges the app to name where the work came from, and
                  // `meta.source` names the *build* rather than the project.
                  if (attribution.upstreamProject.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      _upstreamLabel,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: secondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      attribution.upstreamProject,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium?.merge(AppText.latin),
                    ),
                    Text(
                      attribution.upstreamProjectUrl,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall
                          ?.merge(AppText.latin)
                          .copyWith(color: secondary),
                    ),
                    if (attribution.upstreamTagline.isNotEmpty)
                      Text(
                        attribution.upstreamTagline,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall
                            ?.merge(AppText.latin)
                            .copyWith(color: secondary),
                      ),
                    if (attribution.upstreamPairDescription.isNotEmpty)
                      Text(
                        attribution.upstreamPairDescription,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall
                            ?.merge(AppText.latin)
                            .copyWith(color: secondary),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(_sourcesHeading, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            AppSurface(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final id in attribution.sourceIds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: _SourceRow(
                        id: id,
                        credit: attribution.creditOf(id),
                        license: attribution.licenseOf(id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(_countsHeading, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            AppSurface(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Count(label: 'كلمة', value: attribution.entryCount),
                  _Count(label: 'معنى', value: attribution.senseCount),
                  _Count(
                      label: 'معنى بالعربية', value: attribution.arabicSenseCount),
                  _Count(label: 'مثال', value: attribution.exampleCount),
                  _Count(label: 'كلمة بنطق مكتوب', value: attribution.ipaEntryCount),
                  _Count(label: 'مفتاح عربي', value: attribution.arabicKeyCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, OpenExternalUrl openUrl) {
    final url = Uri.tryParse(attribution.licenseUrl);
    if (url == null) return;
    openUrl(url).ignore();
  }
}

/// One source: its id, its verbatim credit, and **its own licence**.
///
/// **The licence is the point of the row.** The three licences differ, and a
/// list of three sources under one share-alive heading would misstate two of
/// them.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.id,
    required this.credit,
    required this.license,
  });

  final String id;
  final String credit;
  final String license;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          id,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.titleSmall?.merge(AppText.latin),
        ),
        if (credit.isNotEmpty)
          Text(
            credit,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodyMedium?.merge(AppText.latin),
          ),
        if (license.isNotEmpty)
          Text(
            license,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodySmall
                ?.merge(AppText.latin)
                .copyWith(color: secondary),
          ),
      ],
    );
  }
}

/// One figure and its label. The number is a Latin run and says so.
class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              '$value',
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleSmall?.merge(AppText.latinDisplay),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
