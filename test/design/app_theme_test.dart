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

  test('every button family is pinned at zero elevation, hovered included',
      () {
    // Amendment 6's defect, fixed a second time and now prevented rather than
    // patched. The defaults these replace, read out of this SDK's
    // `packages/flutter/lib/src/material/` and not from a blog post:
    //
    // | Widget           | resting | hovered | pressed | source |
    // |------------------|---------|---------|---------|--------|
    // | `ElevatedButton` | **1.0** | **3.0** | 1.0     | `elevated_button.dart:570-585` |
    // | `FilledButton`   | 0.0     | **1.0** | 0.0     | `filled_button.dart:588-603`   |
    // | `OutlinedButton` | 0.0     | 0.0     | 0.0     | `outlined_button.dart:512-513` |
    // | `Chip`           | 0.0     | --      | 0.0     | `chip.dart:1350-1352` `?? 0`  |
    //
    // **`hovered` is the half that matters and the half that is easy to leave
    // out.** `FilledButton` rests at 0, so an assertion that resolves only the
    // resting state passes against an unmodified theme while a mouse-over still
    // paints the keyline — and no golden can catch it, because a screenshot is
    // taken with no pointer over anything.
    //
    // **Per-widget opt-out did not hold, and this is the evidence.** Measured
    // across `lib/ui/`: three widgets shipped with no elevation override at all
    // — `quiz_result_screen.dart`'s `FilledButton`, `stats_screen.dart`'s
    // `_Notice` `OutlinedButton`, and `quiz_setup_screen.dart`'s
    // `ActionChip`. Only the ones somebody happened to remember were safe.
    const hovering = <WidgetState>{WidgetState.hovered};
    const pressed = <WidgetState>{WidgetState.pressed};

    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final families = <String, ButtonStyle?>{
        'elevated': theme.elevatedButtonTheme.style,
        'filled': theme.filledButtonTheme.style,
        'outlined': theme.outlinedButtonTheme.style,
      };
      families.forEach((name, style) {
        for (final entry in <String, Set<WidgetState>>{
          'resting': const <WidgetState>{},
          'hovered': hovering,
          'pressed': pressed,
        }.entries) {
          expect(
            style?.elevation?.resolve(entry.value),
            0.0,
            reason: 'the $name button paints elevation in its ${entry.key} state',
          );
        }
      });

      // `ChipThemeData.elevation` is a plain `double?`, not a
      // `WidgetStateProperty`: `chip.dart:1350` reads it straight into a
      // `?? 0` chain, so there is nothing to resolve and pretending otherwise
      // would be inventing an API. Pinned because a reader cannot otherwise see
      // that a chip is already safe — and `cardTheme.elevation` says nothing
      // about a chip at all.
      expect(theme.chipTheme.elevation, 0.0);
      expect(theme.chipTheme.pressElevation, 0.0);
    }
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