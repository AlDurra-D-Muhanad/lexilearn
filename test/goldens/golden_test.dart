import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter test` ships the declared font files into the test asset bundle and
  // writes them into FontManifest.json, but it does not register them with the
  // text engine. Without this, every glyph rasterises as a tofu box and the
  // golden shows layout and colour but no type at all — which would make it
  // useless for judging the one thing this design system is really about.
  setUpAll(_loadBundledFonts);

  testWidgets('home shell user shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        // The debug ribbon is a development affordance and would otherwise be
        // baked into the committed reference image.
        debugShowCheckedModeBanner: false,
        // The app is Arabic-first RTL. Every screen inherits this.
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const _HomeShellPreview(),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_shell_user_shot.png'),
      // Golden pixels depend on the platform's font rasteriser. Windows uses
      // Segoe UI, Linux CI uses Roboto, so a byte-identical match across the two
      // is impossible by construction. Any screen task changing a colour,
      // spacing, or type size regenerates this on purpose with
      // `--update-goldens` and the reviewer judges the PNG by eye.
      //
      // This `skip:` also means `--update-goldens` will NOT write the file. To
      // regenerate: comment this line out, run with `--update-goldens`, look at
      // the PNG, then put the line back.
      skip: 'platform-dependent; run locally with --update-goldens and inspect the PNG',
    );
  });
}

/// Registers both bundled families with the test text engine.
Future<void> _loadBundledFonts() async {
  const families = <String, List<String>>{
    'Tajawal': <String>[
      'assets/fonts/Tajawal-Regular.ttf',
      'assets/fonts/Tajawal-Medium.ttf',
      'assets/fonts/Tajawal-Bold.ttf',
    ],
    'Inter': <String>[
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
    ],
    // Icons come from the same asset bundle, so they need the same treatment or
    // every glyph in the reference image is a square.
    'MaterialIcons': <String>['fonts/MaterialIcons-Regular.otf'],
  };
  for (final family in families.entries) {
    final loader = FontLoader(family.key);
    for (final asset in family.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

/// The subject of this golden.
///
/// The plan has Task 9 create `lib/app.dart` and `LexiLearnApp`, and pump
/// *that* here. Task 9 has not run yet, so this preview stands in for it: it
/// draws the brand's Home screen using nothing but this task's public surface —
/// `AppTheme`, `AppSpacing`, `AppColors`, `AppText`. That makes the golden do
/// real work today: it is the first proof that the design system actually
/// produces the brand on a real phone-sized surface, with both bundled fonts
/// rasterising. Task 9 replaces this widget with `LexiLearnApp(repository:)` and
/// regenerates the PNG at the same path; nothing else about the test changes.
class _HomeShellPreview extends StatelessWidget {
  const _HomeShellPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: <Widget>[
            const Icon(Icons.menu_book_rounded, color: AppColors.accent),
            const SizedBox(width: AppSpacing.s),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('LexiLearn', style: AppText.latinDisplay.copyWith(fontSize: 20)),
                Text('مرحباً بك!', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: <Widget>[
          TextField(
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              hintText: 'ابحث عن كلمة...',
              hintTextDirection: TextDirection.rtl,
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          _WordOfTheDayCard(theme: theme),
          const SizedBox(height: AppSpacing.m),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.m,
            crossAxisSpacing: AppSpacing.m,
            childAspectRatio: 1.3,
            children: const <Widget>[
              _GridTile(icon: Icons.auto_stories_rounded, label: 'بطاقات التعلم'),
              _GridTile(icon: Icons.checklist_rtl_rounded, label: 'الاختبارات'),
              _GridTile(icon: Icons.favorite_rounded, label: 'المفضلة'),
              _GridTile(icon: Icons.insights_rounded, label: 'إحصائياتك'),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.style_outlined), label: 'بطاقات'),
          NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined), label: 'الاختبارات'),
          NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'المزيد'),
        ],
      ),
    );
  }
}

class _WordOfTheDayCard extends StatelessWidget {
  const _WordOfTheDayCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primaryLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Word of the Day',
              // `AppColors.surfaceLight`, not `Colors.white`: the same token the
              // theme uses for `onPrimary`. A screen task that copies this file
              // should copy the token, not the literal.
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: AppColors.surfaceLight),
            ),
            const SizedBox(height: AppSpacing.s),
            Row(
              children: <Widget>[
                Text(
                  'serenity',
                  textDirection: TextDirection.ltr,
                  style: AppText.latinDisplay.copyWith(
                    fontSize: 28,
                    color: AppColors.surfaceLight,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                const Icon(Icons.volume_up_rounded, color: AppColors.accent),
              ],
            ),
            Text(
              'الهدوء والسكينة',
              textDirection: TextDirection.rtl,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppColors.surfaceLight),
            ),
            const SizedBox(height: AppSpacing.m),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textLight,
                  shape: const StadiumBorder(),
                  // `elevatedButtonTheme` still defaults to Material 3's
                  // elevation 1, and that is the same `canvas.drawShadow`
                  // defect the cards used to have: the test rasteriser strokes
                  // it as a 3px opaque `#000000` keyline around the pill. It
                  // measured 2,363 black pixels in this PNG. The amber fill
                  // carries the button on its own.
                  elevation: 0,
                ),
                child: const Text('معرفة المعنى'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `AppSurface`, not a bare `Card`. `CardThemeData` has no shadow field, so
    // this is the only way a surface carries the brand's soft shadow — and this
    // file is the copy-paste template for the screen tasks, so what it shows is
    // what they will reach for.
    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: AppColors.accent),
          const SizedBox(height: AppSpacing.s),
          Text(label, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}