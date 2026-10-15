import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

void main() {
  test('the colour scheme is the brand palette, not Material\'s tonal guess', () {
    // `ColorScheme.fromSeed` does not produce the brand's colours: seeding with
    // `#885CF6` gives a primary of `#65558F`. Asserting `isNot(light, dark)`
    // passed happily against that pair, which is why these are pinned by hex.
    final light = AppTheme.light().colorScheme;
    final dark = AppTheme.dark().colorScheme;

    expect(light.primary, AppColors.primaryLight);
    expect(dark.primary, AppColors.primaryDark);
    expect(light.primary, isNot(dark.primary));

    expect(light.secondary, AppColors.primaryLight);
    expect(dark.secondary, AppColors.primaryDark);

    expect(light.surface, AppColors.surfaceLight);
    expect(dark.surface, AppColors.surfaceDark);
    expect(light.onSurface, AppColors.textLight);
    expect(dark.onSurface, AppColors.textDark);
    expect(light.onSurfaceVariant, AppColors.textSecondaryLight);
    expect(dark.onSurfaceVariant, AppColors.textSecondaryDark);
    expect(light.outline, AppColors.borderLight);
    expect(dark.outline, AppColors.borderDark);
    expect(light.outlineVariant, AppColors.borderLight);
    expect(dark.outlineVariant, AppColors.borderDark);
    expect(light.error, AppColors.errorLight);
    expect(dark.error, AppColors.errorDark);

    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().useMaterial3, isTrue);
  });

  test('light and dark themes use the two brand primaries', () {
    // The failure this replaces asserted only `isNot(light.primary,
    // dark.primary)`, which the pair `#65558F` / `#A78BFA` satisfied happily
    // while the whole app rendered the wrong purple. Both the primary and the
    // body ink are pinned by token, per brightness.
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.colorScheme.primary, AppColors.primaryLight);
    expect(dark.colorScheme.primary, AppColors.primaryDark);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));

    expect(light.textTheme.bodyMedium?.color, AppColors.textLight);
    expect(dark.textTheme.bodyMedium?.color, AppColors.textDark);
    expect(light.textTheme.bodyMedium?.color,
        isNot(dark.textTheme.bodyMedium?.color));

    expect(light.scaffoldBackgroundColor, AppColors.backgroundLight);
    expect(dark.scaffoldBackgroundColor, AppColors.backgroundDark);
  });

  test('text roles are inked with the brand text colour, not a derived one', () {
    // The generated text theme coloured every stock role `#1D1B20` on light,
    // which is visibly not the brand's `#1F2937`.
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    for (final role in <TextStyle?>[
      light.textTheme.displayLarge,
      light.textTheme.titleLarge,
      light.textTheme.bodyMedium,
      light.textTheme.labelSmall,
    ]) {
      expect(role?.color, AppColors.textLight);
    }
    for (final role in <TextStyle?>[
      dark.textTheme.displayLarge,
      dark.textTheme.titleLarge,
      dark.textTheme.bodyMedium,
      dark.textTheme.labelSmall,
    ]) {
      expect(role?.color, AppColors.textDark);
    }
    expect(light.primaryTextTheme.bodyMedium?.color, AppColors.textLight);
    expect(dark.primaryTextTheme.bodyMedium?.color, AppColors.textDark);
  });

  testWidgets('AppSurface paints the brand shadow and hairline, and no elevation shadow',
      (tester) async {
    Future<BoxDecoration> decorationFor(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: AppSurface(child: SizedBox.expand())),
      ));
      await tester.pumpAndSettle();
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppSurface),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    final light = await decorationFor(AppTheme.light());
    expect(light.boxShadow, AppShadows.light);
    expect((light.border! as Border).top.color, AppColors.borderLight);
    expect(light.color, AppColors.surfaceLight);
    expect(light.borderRadius, BorderRadius.circular(AppRadii.md));

    final dark = await decorationFor(AppTheme.dark());
    expect(dark.boxShadow, AppShadows.none);
    expect((dark.border! as Border).top.color, AppColors.borderDark);
    expect(dark.color, AppColors.surfaceDark);
  });

  test('no theme surface turns elevation into a shadow', () {
    // Material's elevation shadow is ~4x the brand's umbra alpha, and the test
    // rasteriser strokes it as an opaque black keyline. `CardThemeData` cannot
    // carry the brand shadow, so the only safe elevation is zero.
    expect(AppTheme.light().cardTheme.elevation, 0);
    expect(AppTheme.dark().cardTheme.elevation, 0);
  });

  test('cards use the brand surface colour and a rounded outline', () {
    final light = AppTheme.light();
    expect(light.cardTheme.color, AppColors.surfaceLight);
    final lightShape = light.cardTheme.shape as RoundedRectangleBorder;
    expect(lightShape.side.color, AppColors.borderLight);
    expect(lightShape.borderRadius, BorderRadius.circular(AppRadii.md));

    final darkShape = AppTheme.dark().cardTheme.shape as RoundedRectangleBorder;
    expect(darkShape.side.color, AppColors.borderDark);
  });

  test('search fields are pill shaped, matching the artwork', () {
    final decoration = AppTheme.light().inputDecorationTheme;
    expect(decoration.filled, isTrue);
    expect(decoration.border, isA<OutlineInputBorder>());
    final border = decoration.border as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(AppRadii.pill));
    expect(decoration.fillColor, AppColors.surfaceLight);
    expect(decoration.hintStyle?.color, AppColors.textSecondaryLight);
  });

  test('both themes bind Tajawal, which is what renders every Arabic string', () {
    // `ThemeData` takes a `fontFamily` but exposes no getter for it: the family
    // is baked into every style of the text theme, which is what a screen
    // actually renders. So the assertion is made there instead. Covering four
    // roles in both themes is strictly more than checking one field twice.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final styles = theme.textTheme;
      expect(styles.displayLarge?.fontFamily, 'Tajawal');
      expect(styles.titleLarge?.fontFamily, 'Tajawal');
      expect(styles.bodyMedium?.fontFamily, 'Tajawal');
      expect(styles.labelSmall?.fontFamily, 'Tajawal');
    }
  });

  test('scaffold backgrounds match the brand, not Material\'s default', () {
    expect(AppTheme.light().scaffoldBackgroundColor, AppColors.backgroundLight);
    expect(AppTheme.dark().scaffoldBackgroundColor, AppColors.backgroundDark);
  });

  test('fromColorScheme is a pure function of the scheme', () {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primaryLight);
    expect(AppTheme.fromColorScheme(scheme).colorScheme.primary, scheme.primary);
  });
}